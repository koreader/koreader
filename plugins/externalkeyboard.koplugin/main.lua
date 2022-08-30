local FindKeyboard = require("find-keyboard")
local MultiConfirmBox = require("ui/widget/multiconfirmbox")
local Device =  require("device")
local InfoMessage = require("ui/widget/infomessage")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

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

local ExternalKeyboard = WidgetContainer:new{
    name = "external_keyboard",
    is_doc_only = false,
}

function ExternalKeyboard:init()
    self.ui.menu:registerToMainMenu(self)
    if G_reader_settings:isTrue("external_keyboard_otg_always") then
        self:setOTG(USB_ROLE_HOST)
    end
end

function ExternalKeyboard:addToMainMenu(menu_items)
    menu_items.otg_keyboard = {
        text = _("External Keyboard"),
        callback = function()
            return self:showDialog()
        end,
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
        logger.info("ExternalKeyboard:getOtgRole " .. debug_role)
        return self:chipideaRoleToUSBRole(debug_role)
    end
    return role
end

function ExternalKeyboard:setOTG(role)
    logger.info("ExternalKeyboard:setOTG setting to " .. role)
    local file = io.open(OTG_CHIPIDEA_ROLE_PATH, "w")
    if file then
        file:write(self:USBRoleToChipideaRole(role))
        file:close()
    end
end

function ExternalKeyboard:usbPlugIn()
    logger.info("ExternalKeyboard:usbPlugIn")
end

function ExternalKeyboard:usbPlugOut()
    logger.info("ExternalKeyboard:usbPlugOut")
end

-- koreader-base has assumption that only charging may happen in this mode. Really, it is addition of any device.
function ExternalKeyboard:onCharging()
    logger.info(debug.traceback())
    logger.info("ExternalKeyboard:onCharging")
end

function ExternalKeyboard:onNotCharging()
    logger.info("ExternalKeyboard:onNotCharging")
end

function ExternalKeyboard:showDialog()
    local role = self:getOtgRole()
    local new_role = (role == USB_ROLE_DEVICE) and USB_ROLE_HOST or USB_ROLE_DEVICE

    local confirm_box = MultiConfirmBox:new{
        text = role == USB_ROLE_DEVICE and _("The USB configuration in the regular mode.\nDo you want to switch USB to OTG mode to connect an external keyboard?")
        or _("The USB configuration is in the OTG mode.\nDo you want to switch USB to the regular mode?"),
        choice1_text = _("Yes"),
        choice1_callback = function()
            -- G_reader_settings:saveSetting("external_keyboard_otg_always", check_button_always.checked)
            self:setOTG(new_role)
            UIManager:show(InfoMessage:new{
                text = new_role == USB_ROLE_DEVICE and _("OTG is disabled") or _("OTG is enabled"),
            })
        end,
        choice2_text = _("Find Keyboard"),
        choice2_callback = function()
            local event_path = FindKeyboard:find()
            UIManager:show(InfoMessage:new{
                text = "Event path: " .. tostring(event_path),
            })
            if event_path then
                Device.input.open(event_path)
                logger.info("Device event_map: " .. tostring(Device.input.event_map))
            end
        end,
    }
    UIManager:show(confirm_box)
end

return ExternalKeyboard
