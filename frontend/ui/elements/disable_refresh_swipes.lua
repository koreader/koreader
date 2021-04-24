local _ = require("gettext")

return {
    text = _("Disable refresh swipes"),
    help_text = _("Disables fullscreen refreshes triggered by non-horizontal swipes. This setting applies only to in-reader swipes."),
    checked_func = function()
        return G_reader_settings:isTrue("disable_refresh_swipes")
    end,
    callback = function()
        G_reader_settings:toggle("disable_refresh_swipes")
    end
}
