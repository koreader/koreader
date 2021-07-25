local Device = require("device")
local Event = require("ui/event")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local PageTurns = {
    text = _("Page turns"),
    sub_item_table = {
        {
            text = _("With taps"),
            checked_func = function()
                return G_reader_settings:nilOrFalse("page_turns_disable_tap")
            end,
            callback = function()
                G_reader_settings:flipNilOrFalse("page_turns_disable_tap")
            end,
        },
        {
            text = _("With swipes"),
            checked_func = function()
                return G_reader_settings:nilOrFalse("page_turns_disable_swipe")
            end,
            callback = function()
                G_reader_settings:flipNilOrFalse("page_turns_disable_swipe")
            end,
            separator = true,
        },
        {
            text_func = function()
                local text = _("Invert page turn taps and swipes")
                if G_reader_settings:isTrue("inverse_reading_order") then
                    text = text .. "   ★"
                end
                return text
            end,
            checked_func = function()
                local ui = require("apps/reader/readerui"):_getRunningInstance()
                if ui.document.info.has_pages then
                    return ui.paging.inverse_reading_order
                else
                    return ui.rolling.inverse_reading_order
                end
            end,
            callback = function()
                UIManager:broadcastEvent(Event:new("ToggleReadingOrder"))
            end,
            hold_callback = function(touchmenu_instance)
                local inverse_reading_order = G_reader_settings:isTrue("inverse_reading_order")
                local MultiConfirmBox = require("ui/widget/multiconfirmbox")
                UIManager:show(MultiConfirmBox:new{
                    text = inverse_reading_order and _("The default (★) for newly opened books is right-to-left (RTL) page turning.\n\nWould you like to change it?")
                    or _("The default (★) for newly opened books is left-to-right (LTR) page turning.\n\nWould you like to change it?"),
                    choice1_text_func = function()
                        return inverse_reading_order and _("LTR") or _("LTR (★)")
                    end,
                    choice1_callback = function()
                        G_reader_settings:makeFalse("inverse_reading_order")
                        if touchmenu_instance then touchmenu_instance:updateItems() end
                    end,
                    choice2_text_func = function()
                        return inverse_reading_order and _("RTL (★)") or _("RTL")
                    end,
                    choice2_callback = function()
                        G_reader_settings:makeTrue("inverse_reading_order")
                        if touchmenu_instance then touchmenu_instance:updateItems() end
                    end,
                })
            end,
        }
    }
}

if Device:hasKeys() then
    table.insert(PageTurns.sub_item_table, {
        text = _("Invert page turn buttons"),
        checked_func = function()
            return G_reader_settings:isTrue("input_invert_page_turn_keys")
        end,
        callback = function()
            G_reader_settings:flipNilOrFalse("input_invert_page_turn_keys")
            Device:invertButtons()
        end,
    })
end
return PageTurns
