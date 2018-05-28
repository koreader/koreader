local _ = require("gettext")

return {
    text = _("Avoid mandatory black flashes in UI"),
    checked_func = function()
        return G_reader_settings:isTrue("avoid_flashing_ui")
    end,
    callback = function()
        G_reader_settings:flipNilOrFalse("avoid_flashing_ui")
    end,
}

