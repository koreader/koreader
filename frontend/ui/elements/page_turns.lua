local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local function pageTurnsMenu() return G_reader_settings:readSetting("page_turns") end

return {
    text = _("Page turns"),
    sub_item_table = {
        {
            text = _("Swipe and tap"),
            checked_func = function()
                local page_turns = pageTurnsMenu()
                if page_turns == nil or page_turns == "swipe_tap" then
                    return true
                else
                    return false
                end
            end,
            callback = function()
                G_reader_settings:saveSetting("page_turns", "swipe_tap")
            end
        },
        {
            text = _("Only swipe"),
            checked_func = function()
                if pageTurnsMenu() == "swipe" then
                    return true
                else
                    return false
                end
            end,
            callback = function()
                G_reader_settings:saveSetting("page_turns", "swipe")
            end
        },
        {
            text = _("Only tap"),
            checked_func = function()
                if pageTurnsMenu() == "tap" then
                    return true
                else
                    return false
                end
            end,
            callback = function()
                G_reader_settings:saveSetting("page_turns", "tap")
            end,
            separator = true,
        },
    }
}
