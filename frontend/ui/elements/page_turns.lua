local _ = require("gettext")

return {
    text = _("Page turns"),
    sub_item_table = {
        {
            text = _("Disable taps"),
            checked_func = function()
                return G_reader_settings:isTrue("page_turns_disable_tap")
            end,
            callback = function()
                G_reader_settings:toggle("page_turns_disable_tap")
            end
        },
        {
            text = _("Disable swipes"),
            checked_func = function()
                return G_reader_settings:isTrue("page_turns_disable_swipe")
            end,
            callback = function()
                G_reader_settings:toggle("page_turns_disable_swipe")
            end
        },
    }
}
