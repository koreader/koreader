local Device = require("device")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local T = require("ffi/util").template
local Screen = Device.screen

local eink_settings_table = {
    text = _("E-ink settings"),
    sub_item_table = {
        {
            text = _("Use smaller panning rate"),
            checked_func = function() return Screen.low_pan_rate end,
            callback = function()
                Screen.low_pan_rate = not Screen.low_pan_rate
                G_reader_settings:saveSetting("low_pan_rate", Screen.low_pan_rate)
            end,
        },
        dofile("frontend/ui/elements/flash_ui.lua"),
        dofile("frontend/ui/elements/flash_keyboard.lua"),
        {
            text = _("Avoid mandatory black flashes in UI"),
            checked_func = function() return G_reader_settings:isTrue("avoid_flashing_ui") end,
            callback = function()
                G_reader_settings:flipNilOrFalse("avoid_flashing_ui")
            end,
        },
        {
            text_func = function()
                local count = G_reader_settings:readSetting("screensaver_extra_flash_count", 0)
                local delay = G_reader_settings:readSetting("screensaver_extra_flash_delay", 1000)
                if count == 0 then
                    return _("Sleep screen anti-ghosting redraws: off")
                end
                return T(_("Sleep screen anti-ghosting redraws: %1×, %2 ms"), count, delay)
            end,
            help_text = _("Redraw the sleep screen image a number of times after it is shown to reduce ghosting. Each redraw flashes black then redraws the cover. Set count to 0 to disable."),
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                local DoubleSpinWidget = require("ui/widget/doublespinwidget")
                local widget = DoubleSpinWidget:new{
                    left_value = G_reader_settings:readSetting("screensaver_extra_flash_count", 0),
                    left_min = 0,
                    left_max = 4,
                    left_step = 1,
                    left_hold_step = 1,
                    left_text = _("Redraws"),
                    right_value = G_reader_settings:readSetting("screensaver_extra_flash_delay", 1000),
                    right_min = 100,
                    right_max = 2000,
                    right_step = 100,
                    right_hold_step = 500,
                    right_text = _("Delay (ms)"),
                    title_text = _("Sleep screen flashes"),
                    ok_text = _("Set"),
                    callback = function(left_value, right_value)
                        G_reader_settings:saveSetting("screensaver_extra_flash_count", left_value)
                        G_reader_settings:saveSetting("screensaver_extra_flash_delay", right_value)
                        touchmenu_instance:updateItems()
                    end,
                }
                UIManager:show(widget)
            end,
        },
    },
}

if Device:hasEinkScreen() then
    table.insert(eink_settings_table.sub_item_table, 1, dofile("frontend/ui/elements/refresh_menu_table.lua"))
    if (Screen.wf_level_max or 0) > 0 then
        table.insert(eink_settings_table.sub_item_table, dofile("frontend/ui/elements/waveform_level.lua"))
    end
end

return eink_settings_table
