local Event = require("ui/event")
local FindKeyboard = require("find-keyboard")
local MultiConfirmBox = require("ui/widget/multiconfirmbox")
local Device =  require("device")
local InfoMessage = require("ui/widget/infomessage")
local InputText = require("ui/widget/inputtext")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local event_map_keyboard = require("event_map_keyboard")
local util = require("util")
local _ = require("gettext")
local ffi = require("ffi")
local C = ffi.C
require("ffi/posix_h")

-- The include/linux/usb/role.h calls the USB roles "host" and "device". The Chipidea driver calls them "host" and "gadget".
-- This plugin sticks to Linux naming except when interacting with Chipidea drivers.
local USB_ROLE_DEVICE = "device"
local USB_ROLE_HOST = "host"
-- This path exists on Kobo Clara and newer. Other devices Chipidea drivers should have it too.
-- Also, the kernel must be compiled with CONFIG_DEBUG_FS and the debugfs must be mounted.
local OTG_CHIPIDEA_ROLE_PATH = "/sys/kernel/debug/ci_hdrc.0/role"

local function setupDebugFS()
    os.execute("plugins/externalkeyboard.koplugin/setup-debugfs.sh")
end

if lfs.attributes("/sys/kernel/debug", "mode") == "directory" then
    -- This should be in init() but the check must come first. So this part of initialization is here. It is quick and safe enough to be in a check.
    setupDebugFS()
    if lfs.attributes(OTG_CHIPIDEA_ROLE_PATH, "mode") ~= "file" then
        return { disabled = true }
    end
else
    return { disabled = true }
end

local function yes() return true end
local function no() return false end  -- luacheck: ignore

local ExternalKeyboard = WidgetContainer:new{
    name = "external_keyboard",
    is_doc_only = false,
    original_device_values = nil,
    keyboard_fds = {},
}

function ExternalKeyboard:init()
    self.ui.menu:registerToMainMenu(self)
    local role = self:getOtgRole()
    logger.dbg("ExternalKeyboard: role", role)

    if role == USB_ROLE_DEVICE and G_reader_settings:isTrue("external_keyboard_otg_mode_on_start") then
        self:setOTG(USB_ROLE_HOST)
        role = USB_ROLE_HOST
    end
    if role == USB_ROLE_HOST then
        self:findAndSetupKeyboard()
    end
end

function ExternalKeyboard:addToMainMenu(menu_items)
    menu_items.external_keyboard = {
        text = _("External Keyboard"),
        sub_item_table = {
            {
                text = _("Enable OTG mode to connect peripherals"),
                keep_menu_open = true,
                checked_func = function()
                    return self:getOtgRole() == USB_ROLE_HOST
                end,
                callback = function(touchmenu_instance)
                    local role = self:getOtgRole()
                    local new_role = (role == USB_ROLE_DEVICE) and USB_ROLE_HOST or USB_ROLE_DEVICE
                    self:setOTG(new_role)
                    touchmenu_instance:updateItems()
                end,
            },
            {
                text = _("Automatically enable OTG mode on start"),
                keep_menu_open = true,
                checked_func = function()
                     return G_reader_settings:isTrue("external_keyboard_otg_mode_on_start")
                end,
                callback = function(touchmenu_instance)
                    G_reader_settings:flipNilOrFalse("external_keyboard_otg_mode_on_start")
                end,
            },
            {
                text = _("Help"),
                keep_menu_open = true,
                callback = function()
                    self:showHelp()
                end,
            },
        }
    }
end

function ExternalKeyboard:chipideaRoleToUSBRole(role)
    if role == "host" then
        return USB_ROLE_HOST
    elseif role == "gadget" then
        return USB_ROLE_DEVICE
    else
        error('Unknown Chipidea role: ' .. tostring(role))
    end
end

function ExternalKeyboard:USBRoleToChipideaRole(role)
    if role == USB_ROLE_HOST then
        return "host"
    elseif role == USB_ROLE_DEVICE then
        return "gadget"
    else
        error('Invalid USB role: ' .. tostring(role))
    end
end

function ExternalKeyboard:getOtgRole()
    local role = USB_ROLE_DEVICE
    local file = io.open(OTG_CHIPIDEA_ROLE_PATH, "r")

    -- Do not throw exception if the file for role does not exist.
    -- If it does not exist, the USB must be in the default device mode.
    if file then
        local debug_role = file:read("l")
        file:close()
        return self:chipideaRoleToUSBRole(debug_role)
    end
    return role
end

function ExternalKeyboard:setOTG(role)
    logger.dbg("ExternalKeyboard:setOTG setting to", role)
    local file = io.open(OTG_CHIPIDEA_ROLE_PATH, "w")
    if file then
        file:write(self:USBRoleToChipideaRole(role))
        file:close()
    end
end

ExternalKeyboard.onUsbDevicePlugIn = UIManager:debounce(0.5, false, function(self)
    self:findAndSetupKeyboard()
end)

ExternalKeyboard.onUsbDevicePlugOut = UIManager:debounce(0.5, false, function(self)
    logger.dbg("ExternalKeyboard: onUsbDevicePlugOut")

    local is_any_disconnected = false
    -- Check that a keyboard really was disconnected. It could've been another USB device.
    for event_path, fd in ipairs(self.keyboard_fds) do
        if lfs.attributes(event_path, "mode") == nil then
            is_any_disconnected = true
        end
    end

    if not is_any_disconnected then
        return
    end

    logger.dbg("ExternalKeyboard: USB keyboard was disconnected")

    self.keyboard_fds = {}
    if self.original_device_values then
        Device.input.event_map = self.original_device_values.event_map
        Device.keyboard_layout = self.original_device_values.keyboard_layout
        Device.hasKeyboard = self.original_device_values.hasKeyboard
        Device.hasDPad = self.original_device_values.hasDPad
    end

    -- Broadcasting events throught UIManager would only get to InputText if there is an active widget on the window stack.
    -- So, calling a static function is the only choice.
    -- InputText.setKeyboard(require("ui/widget/virtualkeyboard"))
    -- Update the existing input widgets. It must be issued after the static state of InputText is updated.
    InputText.initInputEvents()
    UIManager:broadcastEvent(Event:new("PhysicalKeyboardDisconnected"))
end)

-- The keyboard events with the same key codes would override the original events.
-- That may cause embedded buttons to lose their original function and produce letters.
-- Can we tell from which device a key press comes? The koreader-base passes values of input_event which do not have file descriptors.
function ExternalKeyboard:findAndSetupKeyboard()
    local keyboards = FindKeyboard:find()
    local is_new_keyboard_setup = false
    local has_dpad_func = Device.hasDPad

    -- A USB keyboard may be recognized as several devices under a hub. And several of them may
    -- have keyboard capabilities set. Yet, only one would emit the events. The solution is to open all of them.
    for __, keyboard_info in ipairs(keyboards) do
        logger.dbg("ExternalKeyboard:findAndSetupKeyboard found event path", keyboard_info.event_path, "has_dpad", keyboard_info.has_dpad)
        -- Check if the event file already was open.
        if self.keyboard_fds[keyboard_info.event_path] == nil then
            local ok, fd = pcall(Device.input.open, keyboard_info.event_path)
            if not ok then
                UIManager:show(InfoMessage:new{
                    text = "Error opening the keyboard device " .. keyboard_info.event_path .. ":\n" .. tostring(fd),
                })
                return
            end

            is_new_keyboard_setup = true
            self.keyboard_fds[keyboard_info.event_path] = fd

            if keyboard_info.has_dpad then
                has_dpad_func = yes
            end
        end
    end

    if is_new_keyboard_setup then
        -- The setting for input_invert_page_turn_keys wouldn't mess up the new event map. Device module applies it on initialization, not dynamically.
        self.original_device_values = {
            event_map = Device.input.event_map,
            keyboard_layout = Device.keyboard_layout,
            hasKeyboard = Device.hasKeyboard,
            hasDPad = Device.hasDPad,
        }

        -- Using a new table avoids mutating the original event map.
        local event_map = {}
        util.tableMerge(event_map, Device.input.event_map)
        util.tableMerge(event_map, event_map_keyboard)
        Device.input.event_map = event_map
        Device.hasKeyboard = yes
        Device.hasDPad = has_dpad_func

        UIManager:show(InfoMessage:new{
            text = _("Keyboard connected"),
            timeout = 1,
        })
        InputText.initInputEvents()
        UIManager:broadcastEvent(Event:new("PhysicalKeyboardConnected"))
    end
end

function ExternalKeyboard:showHelp()
	UIManager:show(InfoMessage:new {
		text = _([[
Note that in the OTG mode the device would not be recognized as a USB drive by a computer.

Troubleshooting:
- If the keyboard is not recognized after plugging it in, try switching the USB mode to regular and back to OTG again.
]]),
	})
end

return ExternalKeyboard
