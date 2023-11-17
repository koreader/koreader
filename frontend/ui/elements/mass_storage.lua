local Device = require("device")
local Event = require("ui/event")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local _ = require("gettext")

local MassStorage = {}

-- if required a popup will ask before entering mass storage mode
function MassStorage:requireConfirmation()
    return not G_reader_settings:isTrue("mass_storage_confirmation_disabled")
end

function MassStorage:isEnabled()
    return not G_reader_settings:isTrue("mass_storage_disabled")
end

-- mass storage settings menu
function MassStorage:getSettingsMenuTable()
    return {
        {
            text = _("Disable confirmation popup"),
            help_text = _([[This will ONLY affect what happens when you plug in the device!]]),
            checked_func = function() return not self:requireConfirmation() end,
            callback = function()
                G_reader_settings:saveSetting("mass_storage_confirmation_disabled", self:requireConfirmation())
            end,
        },
        {
            text = _("Disable mass storage functionality"),
            help_text = _([[In case your device uses an unsupported setup where you know it won't work properly.]]),
            checked_func = function() return not self:isEnabled() end,
            callback = function()
                G_reader_settings:saveSetting("mass_storage_disabled", self:isEnabled())
            end,
        },
    }
end

-- mass storage actions
function MassStorage:getActionsMenuTable()
    return {
        text = _("Start USB storage"),
        enabled_func = function() return self:isEnabled() end,
        callback = function()
            self:start(false)
        end,
    }
end

-- exit KOReader and start mass storage mode.
function MassStorage:start(with_confirmation)
    if not Device:canToggleMassStorage() or not self:isEnabled() then
        return
    end

    local ask
    if with_confirmation ~= nil then
        ask = with_confirmation
    else
        ask = self:requireConfirmation()
    end

    if ask then
        local ConfirmBox = require("ui/widget/confirmbox")
        self.usbms_widget = ConfirmBox:new{
            text = _("Share storage via USB?"),
            ok_text = _("Share"),
            ok_callback = function()
                -- save settings before activating USBMS:
                UIManager:flushSettings()
                logger.info("Exiting KOReader to enter USBMS mode...")
                UIManager:broadcastEvent(Event:new("Close"))
                UIManager:quit(86)
            end,
            cancel_callback = function()
                self:dismiss()
            end,
        }

        UIManager:show(self.usbms_widget)
    else
        -- save settings before activating USBMS:
        UIManager:flushSettings()
        logger.info("Exiting KOReader to enter USBMS mode...")
        UIManager:broadcastEvent(Event:new("Close"))
        UIManager:quit(86)
    end
end

-- Dismiss the ConfirmBox
function MassStorage:dismiss()
    if not self.usbms_widget then
        return
    end

    UIManager:close(self.usbms_widget)
    self.usbms_widget = nil
end

return MassStorage
