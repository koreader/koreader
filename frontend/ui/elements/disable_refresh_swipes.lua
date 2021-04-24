local _ = require("gettext")

return {
    text = _("Disable refresh swipes"),
    checked_func = function()
        return G_reader_settings:isTrue("disable_refresh_swipes")
    end,
    callback = function()
        G_reader_settings:toggle("disable_refresh_swipes")
    end
}
