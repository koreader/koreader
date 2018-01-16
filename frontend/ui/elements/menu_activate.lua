local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local function activateMenu() return G_reader_settings:readSetting("activate_menu") end

return {
    text = _("Activate menu"),
    sub_item_table = {
        {
            text = _("Swipe and tap"),
            checked_func = function()
                local activate_menu = activateMenu()
                if activate_menu == nil or activate_menu == "swipe_tap" then
                    return true
                else
                    return false
                end
            end,
            callback = function()
                G_reader_settings:saveSetting("activate_menu", "swipe_tap")
                UIManager:show(InfoMessage:new{
                    text = _("This will take effect on next restart."),
                })
            end
        },
        {
            text = _("Only swipe"),
            checked_func = function()
                if activateMenu() == "swipe" then
                    return true
                else
                    return false
                end
            end,
            callback = function()
                G_reader_settings:saveSetting("activate_menu", "swipe")
                UIManager:show(InfoMessage:new{
                    text = _("This will take effect on next restart."),
                })
            end
        },
        {
            text = _("Only tap"),
            checked_func = function()
                if activateMenu() == "tap" then
                    return true
                else
                    return false
                end
            end,
            callback = function()
                G_reader_settings:saveSetting("activate_menu", "tap")
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
