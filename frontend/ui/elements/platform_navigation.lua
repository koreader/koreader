local Device = require("device")
local Event = require("ui/event")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local PlatformNav = {
    text = _("Page turn behavior"), -- Mainly so as to differentiate w/ "Page Turns" when in readermenu...
    sub_item_table = {},
}

if Device:canDoSwipeAnimation() then
    table.insert(PlatformNav.sub_item_table, {
        text =_("Page turn animations"),
        checked_func = function()
            return G_reader_settings:isTrue("swipe_animations")
        end,
        callback = function()
            UIManager:broadcastEvent(Event:new("TogglePageChangeAnimation"))
        end,
        separator = true,
    })
end

if Device:hasKeys() then
    table.insert(PlatformNav.sub_item_table, {
        text = _("Invert page turn buttons"),
        checked_func = function()
            return G_reader_settings:isTrue("input_invert_page_turn_keys")
        end,
        callback = function()
            UIManager:broadcastEvent(Event:new("SwapPageTurnButtons"))
        end,
    })
end

-- No menu item at all if it's empty
if #PlatformNav.sub_item_table == 0 then
    return {}
end

return PlatformNav
