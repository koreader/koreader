local Event = require("ui/event")
local Device =  require("device")
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

-- The include/linux/usb/role.h calls the USB roles "host" and "device".
local USB_ROLE_DEVICE = "device"
local USB_ROLE_HOST   = "host"
-- The Chipidea driver calls them "host" and "gadget".
-- This plugin sticks to Linux naming except when interacting with drivers.
local CHIPIDEA_TO_USB = {
    host   = USB_ROLE_HOST,
    gadget = USB_ROLE_DEVICE,
}
local USB_TO_CHIPIDEA = {
    [USB_ROLE_HOST]   = "host",
    [USB_ROLE_DEVICE] = "gadget",
}
-- sunxi just adds a "usb_" prefix
local SUNXI_TO_USB = {
    usb_host   = USB_ROLE_HOST,
    usb_device = USB_ROLE_DEVICE,
}
local USB_TO_SUNXI = {
    [USB_ROLE_HOST]   = "usb_host",
    [USB_ROLE_DEVICE] = "usb_device",
}

-- This path exists on Kobo Clara and newer. Other devices w/ Chipidea drivers should have it too.
-- Also, the kernel must be compiled with CONFIG_DEBUG_FS and the debugfs must be mounted (we'll ensure the latter).
local OTG_CHIPIDEA_ROLE_PATH = "/sys/kernel/debug/ci_hdrc.0/role"
-- This one is for devices on a sunxi SoC (tested on a B300, as found on the Kobo Elipsa & Sage).
-- It does not require debugfs, but the point is moot as debugfs is mounted by default on those,
-- as Nickel relies on it for PM interaction with the display driver.
local OTG_SUNXI_ROLE_PATH = "/sys/devices/platform/soc/usbc0/otg_role"
-- NOTE: See https://www.mobileread.com/forums/showthread.php?p=4135724 if your keyboard reports itself as an Apple keyboard.
--       (We currently don't do this here, but that may change in the future).

local function setupDebugFS()
    local mounts = io.open("/proc/mounts", "re")
    if not mounts then
        return false
    end

    local found = false
    for line in mounts:lines() do
        if line:find("^none /sys/kernel/debug debugfs") or
           line:find("^debugfs /sys/kernel/debug debugfs") then
            found = true
            break
        end
    end
    mounts:close()

    if not found then
        -- If we're not root, we won't be able to mount it
        if C.getuid() ~= 0 then
            logger.dbg("ExternalKeyboard: Cannot mount debugfs (unprivileged user)")
            return false
        end

        if os.execute("mount -t debugfs none /sys/kernel/debug") ~= 0 then
            logger.dbg("ExternalKeyboard: Failed to mount debugfs")
            return false
        end
    end

    return true
end

-- The mount point probably doesn't exist on kernels built w/o CONFIG_DEBUG_FS
if lfs.attributes("/sys/kernel/debug", "mode") == "directory" then
    -- This should be in init() but the check must come first. So this part of initialization is here.
    -- It is quick and harmless enough to be in a check.
    if not setupDebugFS() then
        return { disabled = true }
    end
    if lfs.attributes(OTG_CHIPIDEA_ROLE_PATH, "mode") ~= "file" and
       lfs.attributes(OTG_SUNXI_ROLE_PATH,    "mode") ~= "file" then
        return { disabled = true }
    end
else
    return { disabled = true }
end

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

    -- Check if we should go with the sunxi otg manager, or the chipidea driver...
    if lfs.attributes(OTG_SUNXI_ROLE_PATH, "mode") == "file" then
        self.getOTGRole = self.sunxiGetOTGRole
        self.setOTGRole = self.sunxiSetOTGRole
    else
        self.getOTGRole = self.chipideaGetOTGRole
        self.setOTGRole = self.chipideaSetOTGRole
    end

    local role = self:getOTGRole()
    logger.dbg("ExternalKeyboard: role", role)

    if role == USB_ROLE_DEVICE and G_reader_settings:isTrue("external_keyboard_otg_mode_on_start") then
        self:setOTGRole(USB_ROLE_HOST)
        role = USB_ROLE_HOST
    end
    if role == USB_ROLE_HOST then
        -- Sweep the full class/input sysfs tree to look for keyboards
        self:findAndSetupKeyboards()
    end
end

function ExternalKeyboard:addToMainMenu(menu_items)
    menu_items.external_keyboard = {
        text = _("External Keyboard"),
        sub_item_table = {
            {
                text = _("Enable OTG mode to connect peripherals"),
                checked_func = function()
                    return self:getOTGRole() == USB_ROLE_HOST
                end,
                callback = function(touchmenu_instance)
                    local role = self:getOTGRole()
                    local new_role = (role == USB_ROLE_DEVICE) and USB_ROLE_HOST or USB_ROLE_DEVICE
                    self:setOTGRole(new_role)
                end,
            },
            {
                text = _("Always enable OTG mode"),
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

function ExternalKeyboard:chipideaGetOTGRole()
    local role = USB_ROLE_DEVICE
    local file = io.open(OTG_CHIPIDEA_ROLE_PATH, "re")

    -- Do not throw exception if the file for role does not exist.
    -- If it does not exist, the USB must be in the default device mode.
    if file then
        local chipidea_role = file:read("l")
        file:close()
        return CHIPIDEA_TO_USB[chipidea_role] or role
    end
    return role
end

function ExternalKeyboard:sunxiGetOTGRole()
    local file = io.open(OTG_SUNXI_ROLE_PATH, "re")

    -- File should always be present
    if file then
        local sunxi_role = file:read("l")
        file:close()
        return SUNXI_TO_USB[sunxi_role]
    end
end

function ExternalKeyboard:getOTGRole() end

function ExternalKeyboard:chipideaSetOTGRole(role)
    -- Writing role to file will fail if the role is the same as the current role.
    -- Check current role before calling.
    logger.dbg("ExternalKeyboard:chipideaSetOTGRole setting to", role)
    local file = io.open(OTG_CHIPIDEA_ROLE_PATH, "we")
    if file then
        file:write(USB_TO_CHIPIDEA[role])
        file:close()
    end
end

function ExternalKeyboard:sunxiSetOTGRole(role)
    -- Sunxi being what it is, there's no sanity check at all, it'll happily reset USB to set the same role again.
    logger.dbg("ExternalKeyboard:sunxiSetOTGRole setting to", role)
    local file = io.open(OTG_SUNXI_ROLE_PATH, "we")
    if file then
        file:write(USB_TO_SUNXI[role])
        file:close()
    end
end

function ExternalKeyboard:setOTGRole(role) end

function ExternalKeyboard:onExit()
    logger.dbg("ExternalKeyboard:onExit")
    local role = self:getOTGRole()
    if role == USB_ROLE_HOST then
        self:setOTGRole(USB_ROLE_DEVICE)
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

    -- Close our Input handle on it
    Device.input:close(event_path)

    ExternalKeyboard.keyboard_fds[event_path] = nil
    ExternalKeyboard.connected_keyboards = ExternalKeyboard.connected_keyboards - 1
    logger.dbg("ExternalKeyboard: USB keyboard", event_path, "was disconnected; total:", ExternalKeyboard.connected_keyboards)
    -- If that was the last keyboard we knew about, restore native input-related device caps.
    if ExternalKeyboard.connected_keyboards == 0 and ExternalKeyboard.original_device_values then
        Device.input.event_map = ExternalKeyboard.original_device_values.event_map
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
        if not ok then
            UIManager:show(InfoMessage:new{
                text = "Error opening keyboard:\n" .. tostring(fd),
            })
            logger.warn("Error opening keyboard:", fd)
            return
        end

        ExternalKeyboard.keyboard_fds[keyboard_info.event_path] = fd
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
