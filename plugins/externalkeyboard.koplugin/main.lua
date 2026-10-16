local Device =  require("device")

if not Device:supportsExternalKeyboard() then
    return { disabled = true }
end

local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local InputText = require("ui/widget/inputtext")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local util = require("util")
local _ = require("gettext")

local ffi = require("ffi")
local C = ffi.C
require("ffi/posix_h")
require("ffi/fbink_input_h")

local USB_ROLE_DEVICE = "device"
local USB_ROLE_HOST   = "host"

local KEYBOARD_LAYOUTS_DIR = "plugins/externalkeyboard.koplugin/keyboard_layouts"
-- NOTE: See https://www.mobileread.com/forums/showthread.php?p=4135724 if your keyboard reports itself as an Apple keyboard.
--       (We currently don't do this here, but that may change in the future).

local function yes() return true end
local function no() return false end  -- luacheck: ignore

local ExternalKeyboard = WidgetContainer:extend{
    name = "external_keyboard",
    is_doc_only = false,
    original_device_values = nil,
    keyboard_fds = {},
    connected_keyboards = 0,
}

function ExternalKeyboard:init()
    self.ui.menu:registerToMainMenu(self)
    self.has_otg_role = Device:hasOTGManagement()

    if self.has_otg_role then
        -- Kobo: set up OTG role management
        local role = Device:getOTGRole()
        logger.dbg("ExternalKeyboard: role", role)

        if role == USB_ROLE_DEVICE and G_reader_settings:isTrue("external_keyboard_otg_mode_on_start") then
            Device:setOTGRole(USB_ROLE_HOST)
            role = USB_ROLE_HOST
        end
        if role == USB_ROLE_HOST then
            self:findAndSetupKeyboards()
        end
    else
        -- Kindle: no OTG role management, but scan for any keyboards that
        -- may already be present (e.g., UHID device created before KOReader
        -- started). New keyboards are handled via EvdevInputInsert events.
        self:findAndSetupKeyboards()
    end
end

function ExternalKeyboard:addToMainMenu(menu_items)
    local sub_items = {}

    -- OTG role management is only available on platforms with OTG sysfs knobs (Kobo)
    if self.has_otg_role then
        table.insert(sub_items, {
            text = _("Enable OTG mode to connect peripherals"),
            checked_func = function()
                return Device:getOTGRole() == USB_ROLE_HOST
            end,
            callback = function(touchmenu_instance)
                local role = Device:getOTGRole()
                local new_role = (role == USB_ROLE_DEVICE) and USB_ROLE_HOST or USB_ROLE_DEVICE
                Device:setOTGRole(new_role)
            end,
        })
        table.insert(sub_items, {
            text = _("Always enable OTG mode"),
            checked_func = function()
                 return G_reader_settings:isTrue("external_keyboard_otg_mode_on_start")
            end,
            callback = function(touchmenu_instance)
                G_reader_settings:flipNilOrFalse("external_keyboard_otg_mode_on_start")
            end,
        })
    end

    table.insert(sub_items, {
        text = _("Keyboard layout"),
        sub_item_table_func = function()
            return self:getKeyboardLayoutMenu()
        end,
    })

    table.insert(sub_items, {
        text = _("Help"),
        keep_menu_open = true,
        callback = function()
            self:showHelp()
        end,
    })

    menu_items.external_keyboard = {
        text = _("External Keyboard"),
        sub_item_table = sub_items,
    }
end

function ExternalKeyboard:getKeyboardLayoutMenu()
    local layouts_by_language = {}
    for filename in lfs.dir(KEYBOARD_LAYOUTS_DIR) do
        local layout = filename:match("^([%w_-]+)%.lua$")
        if layout then
            local language = layout:match("^([%w_]+)%-") or layout
            layouts_by_language[language] = layouts_by_language[language] or {}
            table.insert(layouts_by_language[language], layout)
        end
    end

    local languages = {}
    for language in pairs(layouts_by_language) do table.insert(languages, language) end
    table.sort(languages)
    local items = {}
    for __, language in ipairs(languages) do
        local layouts = layouts_by_language[language]
        table.sort(layouts)
        local layout_items = {}
        local language_name = language
        for dummy, layout in ipairs(layouts) do
            local loader = loadfile(KEYBOARD_LAYOUTS_DIR .. "/" .. layout .. ".lua")
            local layout_data = loader and loader()
            if layout == language and layout_data and layout_data.name then
                language_name = layout_data.name
            end
            table.insert(layout_items, {
                text = layout_data and layout_data.name or (layout == language and _("Default") or layout:sub(#language + 2)),
                checked_func = function()
                    return G_reader_settings:readSetting("external_keyboard_layout", "us") == layout
                end,
                callback = function()
                    G_reader_settings:saveSetting("external_keyboard_layout", layout)
                    logger.dbg("ExternalKeyboard: selected layout", layout)
                end,
            })
        end
        table.insert(items, {
            text = language_name,
            sub_item_table = layout_items,
        })
    end
    return items
end

function ExternalKeyboard:onExit()
    logger.dbg("ExternalKeyboard:onExit")
    if self.has_otg_role then
        local role = Device:getOTGRole()
        if role == USB_ROLE_HOST then
            Device:setOTGRole(USB_ROLE_DEVICE)
        end
    end
end

function ExternalKeyboard:_onEvdevInputInsert(event_path)
    self:setupKeyboard(event_path)
end

function ExternalKeyboard:onEvdevInputInsert(path)
    -- Leave time for the kernel to actually create the device
    UIManager:scheduleIn(0.5, self._onEvdevInputInsert, self, path)
end

function ExternalKeyboard:_onEvdevInputRemove(event_path)
    -- Check that a keyboard we know about really was disconnected. Another input device could've been unplugged.
    if not ExternalKeyboard.keyboard_fds[event_path] then
        logger.dbg("ExternalKeyboard:onEvdevInputRemove:", event_path, "was not a keyboard we knew about")
        return
    end

    -- Double-check that it's really gone.
    local event_file_attrs = lfs.attributes(event_path, "mode")
    if event_file_attrs ~= nil then
        logger.warn("ExternalKeyboard:onEvdevInputRemove:", event_path, "is still connected?!")
        return
    end

    -- Clear the screen-rotation exemption before its fd can be reused.
    Device.input.rotation_ignored_fds[ExternalKeyboard.keyboard_fds[event_path]] = nil

    -- Close our Input handle on it
    Device.input:close(event_path)

    ExternalKeyboard.keyboard_fds[event_path] = nil
    ExternalKeyboard.connected_keyboards = ExternalKeyboard.connected_keyboards - 1
    logger.dbg("ExternalKeyboard: USB keyboard", event_path, "was disconnected; total:", ExternalKeyboard.connected_keyboards)
    -- If that was the last keyboard we knew about, restore native input-related device caps.
    if ExternalKeyboard.connected_keyboards == 0 and ExternalKeyboard.original_device_values then
        Device.input.event_map = ExternalKeyboard.original_device_values.event_map
        Device.input.hw_text_layout = ExternalKeyboard.original_device_values.hw_text_layout
        Device.keyboard_layout = ExternalKeyboard.original_device_values.keyboard_layout
        Device.hasKeyboard = ExternalKeyboard.original_device_values.hasKeyboard
        Device.hasKeys = ExternalKeyboard.original_device_values.hasKeys
        Device.hasFewKeys = ExternalKeyboard.original_device_values.hasFewKeys
        Device.hasDPad = ExternalKeyboard.original_device_values.hasDPad
        ExternalKeyboard.original_device_values = nil
    end

    -- Only show this once
    if ExternalKeyboard.connected_keyboards == 0 then
        UIManager:show(InfoMessage:new{
            text = _("Keyboard disconnected"),
            timeout = 1,
        })
    end
    -- There's a two-pronged approach here:
    -- * Call a static class method to modify the class state for future instances of said class
    -- * Broadcast an Event so that all currently displayed widgets update their own state.
    --   This must come after, because widgets *may* rely on static class members,
    --   we have no guarantee about Event delivery order.
    self:_broadcastDisconnected()
end

function ExternalKeyboard:onEvdevInputRemove(path)
    UIManager:scheduleIn(0.5, self._onEvdevInputRemove, self, path)
end

ExternalKeyboard._broadcastDisconnected = UIManager:debounce(0.5, false, function()
    InputText.initInputEvents()
    UIManager:broadcastEvent(Event:new("PhysicalKeyboardDisconnected"))
end)

-- Implement FindKeyboard:find & check via FBInkInput
local function findKeyboards()
    local keyboards = {}

    local FBInkInput = ffi.loadlib("fbink_input", 1)
    local dev_count = ffi.new("size_t[1]")
    local devices = FBInkInput.fbink_input_scan(C.INPUT_KEYBOARD, 0, 0, dev_count)
    if devices ~= nil then
        for i = 0, tonumber(dev_count[0]) - 1 do
            local dev = devices[i]
            if dev.matched then
                -- Check if it provides a DPad, too.
                local has_dpad = bit.band(dev.type, C.INPUT_DPAD) ~= 0
                table.insert(keyboards, { event_fd = tonumber(dev.fd), event_path = ffi.string(dev.path), name = ffi.string(dev.name), has_dpad = has_dpad })
            end
        end
        C.free(devices)
    end

    return keyboards
end

local function checkKeyboard(path)
    local keyboard

    local FBInkInput = ffi.loadlib("fbink_input", 1)
    local dev = FBInkInput.fbink_input_check(path, C.INPUT_KEYBOARD, 0, 0)
    if dev ~= nil then
        if dev.matched then
            keyboard = {
                event_fd = tonumber(dev.fd),
                event_path = ffi.string(dev.path),
                name = ffi.string(dev.name),
                has_dpad = bit.band(dev.type, C.INPUT_DPAD) ~= 0
            }
        end
        C.free(dev)
    end

    return keyboard
end

-- The keyboard events with the same key codes would override the original events.
-- That may cause embedded buttons to lose their original function and produce letters,
-- as we cannot tell which device a key press comes from.
function ExternalKeyboard:findAndSetupKeyboards()
    local keyboards = findKeyboards()

    -- A USB keyboard may be recognized as several devices under a hub. And several of them may
    -- have keyboard capabilities set. Yet, only one would emit the events. The solution is to open all of them.
    for __, keyboard_info in ipairs(keyboards) do
        self:setupKeyboard(keyboard_info)
    end
end

function ExternalKeyboard:setupKeyboard(data)
    local keyboard_info
    if type(data) == "table" then
        -- We came from findAndSetupKeyboards, no need to-re-check the device
        keyboard_info = data
    else
        -- We came from a USB hotplug event handler, check the specified path
        local event_path = data

        keyboard_info = checkKeyboard(event_path)
        if not keyboard_info then
            logger.dbg("ExternalKeyboard:setupKeyboard:", event_path, "doesn't look like a keyboard")
            return
        end
    end

    local has_dpad_func = Device.hasDPad

    logger.dbg("ExternalKeyboard:setupKeyboard", keyboard_info.name, "@", keyboard_info.event_path, "- has_dpad:", keyboard_info.has_dpad)
    -- Check if we already know about this event file.
    if ExternalKeyboard.keyboard_fds[keyboard_info.event_path] == nil then
        local ok, fd = pcall(Device.input.fdopen, Device.input, keyboard_info.event_fd, keyboard_info.event_path, keyboard_info.name)
        -- fdopen returns nil (not an error) when the device is already open.
        if ok and not fd then
            fd = require("device/input").opened_devices[keyboard_info.event_path]
        end
        if not ok or not fd then
            UIManager:show(InfoMessage:new{
                text = "Error opening keyboard:\n" .. tostring(fd),
            })
            logger.warn("Error opening keyboard:", fd)
            return
        end

        ExternalKeyboard.keyboard_fds[keyboard_info.event_path] = fd
        -- External keyboard arrows are keyboard-relative, not device-relative.
        Device.input.rotation_ignored_fds[fd] = true
        ExternalKeyboard.connected_keyboards = ExternalKeyboard.connected_keyboards + 1
        logger.dbg("ExternalKeyboard: USB keyboard", keyboard_info.name, "@", keyboard_info.event_path, "was connected; total:", ExternalKeyboard.connected_keyboards)

        if keyboard_info.has_dpad then
            has_dpad_func = yes
        end
    end

    -- If this is our first external input device, keep a snapshot of the native input-related device caps.
    -- The setting for input_invert_page_turn_keys wouldn't mess up the new event map. Device module applies it on initialization, not dynamically.
    if not ExternalKeyboard.original_device_values then
        ExternalKeyboard.original_device_values = {
            event_map = Device.input.event_map,
            hw_text_layout = Device.input.hw_text_layout,
            keyboard_layout = Device.keyboard_layout,
            hasKeyboard = Device.hasKeyboard,
            hasKeys = Device.hasKeys,
            hasFewKeys = Device.hasFewKeys,
            hasDPad = Device.hasDPad,
        }
    end

    -- Using a new table avoids mutating the original event map.
    local event_map = {}
    util.tableMerge(event_map, Device.input.event_map)
    util.tableMerge(event_map, dofile("plugins/externalkeyboard.koplugin/event_map_keyboard.lua"))
    Device.input.event_map = event_map
    local KeyboardLayout = dofile("plugins/externalkeyboard.koplugin/keyboard_layout.lua")
    Device.input.hw_text_layout = function(key_name, modifiers)
        local layout_name = G_reader_settings:readSetting("external_keyboard_layout", "us")
        local text = KeyboardLayout.resolve(layout_name, key_name, modifiers)
        logger.dbg("ExternalKeyboard: layout", layout_name, "key", key_name, "AltGr", modifiers.AltGr, "Shift", modifiers.Shift, "=>", text)
        return text
    end
    Device.hasKeyboard = yes
    Device.hasKeys = yes
    Device.hasFewKeys = no
    Device.hasDPad = has_dpad_func

    -- Only show this once
    if ExternalKeyboard.connected_keyboards == 1 then
        UIManager:show(InfoMessage:new{
            text = _("Keyboard connected"),
            timeout = 1,
        })
    end
    self:_broadcastConnected()
end

ExternalKeyboard._broadcastConnected = UIManager:debounce(0.5, false, function()
    InputText.initInputEvents()
    UIManager:broadcastEvent(Event:new("PhysicalKeyboardConnected"))
end)

function ExternalKeyboard:showHelp()
    UIManager:show(InfoMessage:new {
        text = _("Note that in OTG mode the device will not be recognized as a USB drive by a computer."),
    })
end

return ExternalKeyboard
