local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

return {
    text = _("Disable double tap"),
    checked_func = function()
        return G_reader_settings:readSetting("disable_double_tap") ~= false
    end,
    callback = function()
        local disabled = G_reader_settings:readSetting("disable_double_tap") ~= false
        G_reader_settings:saveSetting("disable_double_tap", not disabled)
        UIManager:show(InfoMessage:new{
            text = _("This will take effect on next restart."),
        })
    end,
}
