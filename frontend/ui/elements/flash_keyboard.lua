local _ = require("gettext")

return {
    text = _("Flash keyboard"),
    checked_func = function()
        return G_reader_settings:nilOrTrue("flash_keyboard")
    end,
    callback = function()
        local disabled = G_reader_settings:nilOrTrue("flash_keyboard")
        G_reader_settings:saveSetting("flash_keyboard", not disabled)
    end,
}
