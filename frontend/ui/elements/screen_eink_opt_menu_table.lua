local _ = require("gettext")
local Screen = require("device").screen

return {
    text = _("E-ink Settings"),
    sub_item_table = {
        require("ui/elements/refresh_menu_table"),
        {
            text = _("Use smaller panning rate"),
            checked_func = function() return Screen.low_pan_rate end,
            callback = function()
                Screen.low_pan_rate = not Screen.low_pan_rate
                G_reader_settings:saveSetting("low_pan_rate", Screen.low_pan_rate)
            end,
        },
        {
            text = _("Avoid mandatory black flashes in UI"),
            checked_func = function() return G_reader_settings:isTrue("avoid_flashing_ui") end,
            callback = function()
                G_reader_settings:flipNilOrFalse("avoid_flashing_ui")
            end,
        },

    },
}
