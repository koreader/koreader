local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local android = require("device/android/device")

return {
    text = _("Fullscreen"),
    checked_func = function()
        return G_reader_settings:readSetting("disable_fullscreen") ~= false
    end,
    callback = function()
        local disabled = G_reader_settings:readSetting("disable_fullscreen") ~= false
        G_reader_settings:saveSetting("disable_fullscreen", not disabled)
        android.setFullscreen(disabled)
        UIManager:show(InfoMessage:new{
            text = _("This will take effect on next restart."),
        })
    end,
}
