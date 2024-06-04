local Device = require("device")
local Event = require("ui/event")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

-- This whole menu is hidden behind a hasKeys device cap.
local PhysicalButtons = {
    text = _("Physical buttons"), -- Mainly so as to differentiate w/ "Page Turns" when in readermenu...
    sub_item_table = {
        {
            text = _("Invert page turn buttons"),
            enabled_func = function()
                return not (G_reader_settings:isTrue("input_invert_left_page_turn_keys") or G_reader_settings:isTrue("input_invert_right_page_turn_keys"))
            end,
            checked_func = function()
                return G_reader_settings:isTrue("input_invert_page_turn_keys")
            end,
            callback = function()
                UIManager:broadcastEvent(Event:new("SwapPageTurnButtons"))
            end,
            separator = true,
        }
    },
}

if Device:hasDPad() and Device:useDPadAsActionKeys() then
    table.insert(PhysicalButtons.sub_item_table, {
        text = _("Invert left-side page turn buttons"),
        enabled_func = function()
            return not G_reader_settings:isTrue("input_invert_page_turn_keys")
        end,
        checked_func = function()
            return G_reader_settings:isTrue("input_invert_left_page_turn_keys")
        end,
        callback = function()
            G_reader_settings:flipNilOrFalse("input_invert_left_page_turn_keys")
            Device:invertButtonsLeft()
        end,
    })
    table.insert(PhysicalButtons.sub_item_table, {
        text = _("Invert right-side page turn buttons"),
        enabled_func = function()
            return not G_reader_settings:isTrue("input_invert_page_turn_keys")
        end,
        checked_func = function()
            return G_reader_settings:isTrue("input_invert_right_page_turn_keys")
        end,
        callback = function()
            G_reader_settings:flipNilOrFalse("input_invert_right_page_turn_keys")
            Device:invertButtonsRight()
        end,
    })
end

if Device:canKeyRepeat() then
    table.insert(PhysicalButtons.sub_item_table, {
        text = _("Disable key repeat"),
        help_text = _("Useful if you don't like the behavior or if your device has faulty switches"),
        checked_func = function()
            return G_reader_settings:isTrue("input_no_key_repeat")
        end,
        callback = function()
            UIManager:broadcastEvent(Event:new("ToggleKeyRepeat"))
        end,
        separator = true,
    })
end

return PhysicalButtons
