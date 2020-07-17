local Device = require("device")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local Screen = Device.screen
local T = require("ffi/util").template

local function custom(refresh_rate_num)
    local default_value
    if refresh_rate_num == "refresh_rate_1" then
        default_value = 12
    elseif refresh_rate_num == "refresh_rate_2" then
        default_value = 22
    else
        default_value = 99
    end
    return (G_reader_settings:readSetting(refresh_rate_num) or default_value), (G_reader_settings:readSetting("night_" .. refresh_rate_num) or G_reader_settings:readSetting(refresh_rate_num) or default_value)
end

local function refreshChecked(savedday, savednight)
    local day, night = UIManager:getRefreshRate()
    return day == savedday and night == savednight
end

local function spinWidgetSetRefresh(touchmenu_instance, refresh_rate_num)
    local left, right = custom(refresh_rate_num)
    local DoubleSpinWidget = require("ui/widget/doublespinwidget")
    local items = DoubleSpinWidget:new{
        width = math.floor(Screen:getWidth() * 0.6),
        info_text = _("For every chapter set -1"),
        left_value = left,
        left_min = -1,
        left_max = 200,
        left_step = 1,
        left_hold_step = 10,
        left_text = _("Regular"),
        right_value = right,
        right_min = -1,
        right_max = 200,
        right_step = 1,
        right_hold_step = 10,
        right_text = _("Night"),
        ok_text = _("Set refresh"),
        title_text = _("Set custom refresh rate"),
        callback = function(left_value, right_value)
            G_reader_settings:saveSetting(refresh_rate_num, left_value)
            G_reader_settings:saveSetting("night_" .. refresh_rate_num, right_value)
            UIManager:setRefreshRate(left_value, right_value)
            touchmenu_instance:updateItems()
        end
    }
    UIManager:show(items)
end


return {
    text = _("Full refresh rate"),
    separator = true,
    sub_item_table = {
        {
            text = _("Never"),
            checked_func = function() return refreshChecked(0, 0) end,
            callback = function() UIManager:setRefreshRate(0, 0) end,
        },
        {
            text = _("Every page"),
            checked_func = function() return refreshChecked(1, 1) end,
            callback = function() UIManager:setRefreshRate(1, 1) end,
        },
        {
            text = _("Every 6 pages"),
            checked_func = function() return refreshChecked(6, 6) end,
            callback = function() UIManager:setRefreshRate(6, 6) end,
        },
        {
            text_func = function()
                return T(_("Custom 1: %1:%2 pages"), custom("refresh_rate_1"))
            end,
            checked_func = function() return refreshChecked(custom("refresh_rate_1")) end,
            callback = function() UIManager:setRefreshRate(custom("refresh_rate_1")) end,
            hold_callback = function(touchmenu_instance)
                spinWidgetSetRefresh(touchmenu_instance, "refresh_rate_1")
            end,
        },
        {
            text_func = function()
                return T(_("Custom 2: %1:%2 pages"), custom("refresh_rate_2"))
            end,
            checked_func = function() return refreshChecked(custom("refresh_rate_2")) end,
            callback = function() UIManager:setRefreshRate(custom("refresh_rate_2")) end,
            hold_callback = function(touchmenu_instance)
                spinWidgetSetRefresh(touchmenu_instance, "refresh_rate_2")
            end,
        },
        {
            text_func = function()
                return T(_("Custom 3: %1:%2 pages"), custom("refresh_rate_3"))
            end,
            checked_func = function() return refreshChecked(custom("refresh_rate_3")) end,
            callback = function() UIManager:setRefreshRate(custom("refresh_rate_3")) end,
            hold_callback = function(touchmenu_instance)
                spinWidgetSetRefresh(touchmenu_instance, "refresh_rate_3")
            end,
        },
        {
            text = _("Every chapter"),
            checked_func = function() return refreshChecked(-1, -1) end,
            callback = function() UIManager:setRefreshRate(-1, -1) end,
        },
    }
}
