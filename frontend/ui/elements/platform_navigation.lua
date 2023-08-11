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

if Device:canKeyRepeat() then
    table.insert(PlatformNav.sub_item_table, {
        text = _("Disable key repeats"),
        help_text = _("Useful if you don't like the behavior or if your device has faulty switches"),
        checked_func = function()
            return G_reader_settings:isTrue("input_no_key_repeats")
        end,
        callback = function()
            UIManager:broadcastEvent(Event:new("ToggleKeyRepeat"))
        end,
        separator = true,
    })
end

return PlatformNav
