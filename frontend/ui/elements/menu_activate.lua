local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

return {
    text = _("Activate menu"),
    sub_item_table = {
        {
            text = _("Tap"),
            checked_func = function()
                return G_reader_settings:readSetting("activate_menu") ~= "swipe"
            end,
            callback = function()
                if G_reader_settings:readSetting("activate_menu") ~= "swipe" then
                    G_reader_settings:saveSetting("activate_menu", "swipe")
                else
                    G_reader_settings:saveSetting("activate_menu", "swipe_tap")
                end
                UIManager:show(InfoMessage:new{
                    text = _("This will take effect on next restart."),
                })
            end,
        },
        {
            text = _("Swipe"),
            checked_func = function()
                return G_reader_settings:readSetting("activate_menu") ~= "tap"
            end,
            callback = function()
                if G_reader_settings:readSetting("activate_menu") ~= "tap" then
                    G_reader_settings:saveSetting("activate_menu", "tap")
                else
                    G_reader_settings:saveSetting("activate_menu", "swipe_tap")
                end
                UIManager:show(InfoMessage:new{
                    text = _("This will take effect on next restart."),
                })
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
