local _ = require("gettext")

return {
    text = _("Flash buttons and menu items"),
    checked_func = function()
        return G_reader_settings:nilOrTrue("flash_ui")
    end,
    callback = function()
        G_reader_settings:flipNilOrTrue("flash_ui")
    end,
}
