local UIManager = require("ui/uimanager")
local _ = require("gettext")

return {
    text = _("Disable double tap"),
    checked_func = function()
        return G_reader_settings:nilOrTrue("disable_double_tap")
    end,
    callback = function()
        local disabled = G_reader_settings:nilOrTrue("disable_double_tap")
        G_reader_settings:saveSetting("disable_double_tap", not disabled)
        UIManager:askForRestart()
    end,
}
