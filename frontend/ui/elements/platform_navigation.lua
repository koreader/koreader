local Device = require("device")

-- Everything in there requires physicla page turn keys ;).
if Device:hasKeys() then
    -- No menu entry at all if we don't have any
    return {}
end

local Event = require("ui/event")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local PlatformNav = {
    text = _("Page turn behavior"), -- Mainly so as to differentiate w/ "Page Turns" when in readermenu...
    sub_item_table = {
        {
            text = _("Invert page turn buttons"),
            checked_func = function()
                return G_reader_settings:isTrue("input_invert_page_turn_keys")
            end,
            callback = function()
                UIManager:broadcastEvent(Event:new("SwapPageTurnButtons"))
            end,
        }
    },
}

return PlatformNav
