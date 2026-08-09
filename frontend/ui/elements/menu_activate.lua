local _ = require("gettext")

local ui = require("apps/reader/readerui").instance or require("apps/filemanager/filemanager").instance

return {
    text = _("Activate menu"),
    sub_item_table = {
        {
            text = _("With a tap"),
            checked_func = function()
                return G_reader_settings:readSetting("activate_menu") ~= "swipe"
            end,
            callback = function()
                local value = G_reader_settings:readSetting("activate_menu") ~= "swipe" and "swipe" or "swipe_tap"
                G_reader_settings:saveSetting("activate_menu", value)
                ui.menu.activation_menu = value
                if ui.config then
                    ui.config.activation_menu = value
                end
            end,
        },
        {
            text = _("With a swipe"),
            checked_func = function()
                return G_reader_settings:readSetting("activate_menu") ~= "tap"
            end,
            callback = function()
                local value = G_reader_settings:readSetting("activate_menu") ~= "tap" and "tap" or "swipe_tap"
                G_reader_settings:saveSetting("activate_menu", value)
                ui.menu.activation_menu = value
                if ui.config then
                    ui.config.activation_menu = value
                end
            end,
            separator = true,
        },
        {
            text = _("Auto-show bottom menu"),
            checked_func = function()
                return G_reader_settings:nilOrTrue("show_bottom_menu")
            end,
            callback = function()
                G_reader_settings:flipNilOrTrue("show_bottom_menu")
            end,
        },
    }
}
