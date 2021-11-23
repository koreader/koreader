local Device = require("device")
local Event = require("ui/event")
local ReaderUI = require("apps/reader/readerui")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local T = require("ffi/util").template

local page_turns_tap_zones_sub_items = {} -- build the Tap zones submenu
local tap_zones = {
    default = _("Default"),
    left_right = _("Left/right"),
    top_bottom = _("Top/bottom"),
}
local function genTapZonesMenu(tap_zones_type)
    table.insert(page_turns_tap_zones_sub_items, {
        text = tap_zones[tap_zones_type],
        checked_func = function()
            return G_reader_settings:readSetting("page_turns_tap_zones", "default") == tap_zones_type
        end,
        callback = function()
            G_reader_settings:saveSetting("page_turns_tap_zones", tap_zones_type)
            ReaderUI.instance.view:setupTouchZones()
        end,
    })
end
genTapZonesMenu("default")
genTapZonesMenu("left_right")
genTapZonesMenu("top_bottom")
table.insert(page_turns_tap_zones_sub_items, {
    text_func = function()
        local size = math.floor(G_reader_settings:readSetting("page_turns_tap_zone_forward_size_ratio", DTAP_ZONE_FORWARD.w) * 100)
        return T(_("Forward tap zone size: %1%"), size)
    end,
    enabled_func = function()
        return G_reader_settings:readSetting("page_turns_tap_zones", "default") ~= "default"
    end,
    keep_menu_open = true,
    callback = function(touchmenu_instance)
        local is_left_right = G_reader_settings:readSetting("page_turns_tap_zones") == "left_right"
        local size = math.floor(G_reader_settings:readSetting("page_turns_tap_zone_forward_size_ratio", DTAP_ZONE_FORWARD.w) * 100)
        UIManager:show(require("ui/widget/spinwidget"):new{
            title_text = is_left_right and _("Forward tap zone width") or _("Forward tap zone height"),
            info_text = is_left_right and _("Percentage of screen width") or _("Percentage of screen height"),
            value = size,
            value_min = 0,
            value_max = 100,
            default_value = math.floor(DTAP_ZONE_FORWARD.w * 100),
            callback = function(spin)
                G_reader_settings:saveSetting("page_turns_tap_zone_forward_size_ratio", spin.value / 100)
                ReaderUI.instance.view:setupTouchZones()
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
        })
    end,
})

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
        },
        {
            text_func = function()
                local tap_zones_type = G_reader_settings:readSetting("page_turns_tap_zones", "default")
                return T(_("Tap zones: %1"), tap_zones[tap_zones_type]:lower())
            end,
            enabled_func = function()
                return G_reader_settings:nilOrFalse("page_turns_disable_tap")
            end,
            sub_item_table = page_turns_tap_zones_sub_items,
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
                return ReaderUI.instance.view.inverse_reading_order
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
