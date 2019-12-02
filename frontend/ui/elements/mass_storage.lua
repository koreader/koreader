local UIManager = require("ui/uimanager")
local _ = require("gettext")

local MassStorage = {}

-- if required a popup will ask before entering mass storage mode
function MassStorage:requireConfirmation()
    return not G_reader_settings:isTrue("mass_storage_confirmation_disabled")
end

-- mass storage settings menu
function MassStorage:getSettingsMenuTable()
    return {
        {
            text = _("Disable confirmation popup"),
            checked_func = function() return not self:requireConfirmation() end,
            callback = function()
                G_reader_settings:saveSetting("mass_storage_confirmation_disabled", self:requireConfirmation())
            end,
        },
    }
end

-- mass storage actions
function MassStorage:getActionsMenuTable()
    return {
        {
            text = _("Start USB storage"),
            callback = function()
                self:start()
            end,
        },
    }
end

-- exit KOReader and start mass storage mode.
function MassStorage:start()
    if self:requireConfirmation() then
        local ConfirmBox = require("ui/widget/confirmbox")
        UIManager:show(ConfirmBox:new{
            text = _("Share storage via USB?\n"),
            ok_text = _("Share"),
            ok_callback = function()
                UIManager:quit()
                UIManager._exit_code = 86
            end,
        })
    else
        UIManager:quit()
        UIManager._exit_code = 86
    end
end

return MassStorage
