local Device = require("device")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local Screen = Device.screen
local T = require("ffi/util").template

local function custom(refresh_rate_type)
    local default_value
    if refresh_rate_type == "refresh_rate_1" then
        default_value = 12
    elseif refresh_rate_type == "refresh_rate_2" then
        default_value = 22
    else
        default_value = 99
    end
    return G_reader_settings:readSetting(refresh_rate_type) or default_value
end

local function spinWidgetSetRefresh(touchmenu_instance, refresh_rate_type)
    local SpinWidget = require("ui/widget/spinwidget")
    local items = SpinWidget:new{
        width = Screen:getWidth() * 0.6,
        value = custom(refresh_rate_type),
        value_min = 0,
        value_max = 200,
        value_step = 1,
        value_hold_step = 10,
        ok_text = _("Set refresh"),
        title_text = _("Set custom refresh rate"),
        callback = function(spin)
            G_reader_settings:saveSetting(refresh_rate_type, spin.value)
            UIManager:setRefreshRate(spin.value)
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
            text = _("Never refresh"),
            checked_func = function() return UIManager:getRefreshRate() == 0 end,
            callback = function() UIManager:setRefreshRate(0) end,
        },
        {
            text = _("Every page"),
            checked_func = function() return UIManager:getRefreshRate() == 1 end,
            callback = function() UIManager:setRefreshRate(1) end,
        },
        {
            text = _("Every 6 pages"),
            checked_func = function() return UIManager:getRefreshRate() == 6 end,
            callback = function() UIManager:setRefreshRate(6) end,
        },
        {
            text_func = function()
                return T(_("Custom 1: %1 pages"), custom("refresh_rate_1"))
            end,
            checked_func = function() return UIManager:getRefreshRate() == custom("refresh_rate_1") end,
            callback = function() UIManager:setRefreshRate(custom("refresh_rate_1")) end,
            hold_callback = function(touchmenu_instance)
                spinWidgetSetRefresh(touchmenu_instance, "refresh_rate_1")
            end,
        },
        {
            text_func = function()
                return T(_("Custom 2: %1 pages"), custom("refresh_rate_2"))
            end,
            checked_func = function() return UIManager:getRefreshRate() == custom("refresh_rate_2") end,
            callback = function() UIManager:setRefreshRate(custom("refresh_rate_2")) end,
            hold_callback = function(touchmenu_instance)
                spinWidgetSetRefresh(touchmenu_instance, "refresh_rate_2")
            end,
        },
        {
            text_func = function()
                return T(_("Custom 3: %1 pages"), custom("refresh_rate_3"))
            end,
            checked_func = function() return UIManager:getRefreshRate() == custom("refresh_rate_3") end,
            callback = function() UIManager:setRefreshRate(custom("refresh_rate_3")) end,
            hold_callback = function(touchmenu_instance)
                spinWidgetSetRefresh(touchmenu_instance, "refresh_rate_3")
            end,
        },
        {
            text = _("Every chapter"),
            checked_func = function() return UIManager:getRefreshRate() == -1 end,
            callback = function() UIManager:setRefreshRate(-1) end,
        },
    }
}
