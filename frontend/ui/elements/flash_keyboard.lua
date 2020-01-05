local _ = require("gettext")

return {
    text = _("Flash keyboard"),
    checked_func = function()
        return G_reader_settings:readSetting("flash_keyboard") ~= false
    end,
    callback = function()
        local disabled = G_reader_settings:readSetting("flash_keyboard") ~= false
        G_reader_settings:saveSetting("flash_keyboard", not disabled)
    end,
}
