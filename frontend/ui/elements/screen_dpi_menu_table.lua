local _ = require("gettext")
local Device = require("device")
local Screen = Device.screen
local T = require("ffi/util").template

local function isAutoDPI() return Screen.dpi_override == nil end

local function dpi() return Screen:getDPI() end

local function custom() return G_reader_settings:readSetting("custom_screen_dpi") end

local function setDPI(dpi_val)
    local UIManager = require("ui/uimanager")
    local text = dpi_val and T(_("DPI set to %1. This will take effect after restarting."), dpi_val)
               or _("DPI set to auto. This will take effect after restarting.")
    -- If this is set to nil, reader.lua doesn't call setScreenDPI
    G_reader_settings:saveSetting("screen_dpi", dpi_val)
    -- Passing a nil properly resets to defaults/auto
    Device:setScreenDPI(dpi_val)
    UIManager:askForRestart(text)
end

local function spinWidgetSetDPI(touchmenu_instance)
    local SpinWidget = require("ui/widget/spinwidget")
    local UIManager = require("ui/uimanager")
    local items = SpinWidget:new{
        value = custom() or dpi(),
        value_min = 90,
        value_max = 900,
        value_step = 10,
        value_hold_step = 50,
        ok_text = _("Set DPI"),
        title_text = _("Set custom screen DPI"),
        callback = function(spin)
            G_reader_settings:saveSetting("custom_screen_dpi", spin.value)
            setDPI(spin.value)
            touchmenu_instance:updateItems()
        end
    }
    UIManager:show(items)
end

local dpi_auto = Screen.device.screen_dpi
local dpi_small = 120
local dpi_medium = 160
local dpi_large = 240
local dpi_xlarge = 320
local dpi_xxlarge = 480
local dpi_xxxlarge = 640

return {
    text = _("Screen DPI"),
    sub_item_table = {
        {
            text = dpi_auto and T(_("Auto DPI (%1)"), dpi_auto) or _("Auto DPI"),
            help_text = _("The DPI of your screen is automatically detected so items can be drawn with the right amount of pixels. This will usually display at (roughly) the same size on different devices, while remaining sharp. Increasing the DPI setting will result in larger text and icons, while a lower DPI setting will look smaller on the screen."),
            checked_func = isAutoDPI,
            radio = true,
            callback = function() setDPI() end
        },
        {
            text = T(_("Small (%1)"), dpi_small),
            checked_func = function()
                if isAutoDPI() then return false end
                local _dpi, _custom = dpi(), custom()
                return _dpi and _dpi <= 140 and _dpi ~= _custom
            end,
            radio = true,
            callback = function() setDPI(dpi_small) end
        },
        {
            text = T(_("Medium (%1)"), dpi_medium),
            checked_func = function()
                if isAutoDPI() then return false end
                local _dpi, _custom = dpi(), custom()
                return _dpi and _dpi > 140 and _dpi <= 200 and _dpi ~= _custom
            end,
            radio = true,
            callback = function() setDPI(dpi_medium) end
        },
        {
            text = T(_("Large (%1)"), dpi_large),
            checked_func = function()
                if isAutoDPI() then return false end
                local _dpi, _custom = dpi(), custom()
                return _dpi and _dpi > 200 and _dpi <= 280 and _dpi ~= _custom
            end,
            radio = true,
            callback = function() setDPI(dpi_large) end
        },
        {
            text = T(_("Extra large (%1)"), dpi_xlarge),
            checked_func = function()
                if isAutoDPI() then return false end
                local _dpi, _custom = dpi(), custom()
                return _dpi and _dpi > 280 and _dpi <= 400 and _dpi ~= _custom
            end,
            radio = true,
            callback = function() setDPI(dpi_xlarge) end
        },
        {
            text = T(_("Extra-Extra Large (%1)"), dpi_xxlarge),
            checked_func = function()
                if isAutoDPI() then return false end
                local _dpi, _custom = dpi(), custom()
                return _dpi and _dpi > 400 and _dpi <= 560 and _dpi ~= _custom
            end,
            radio = true,
            callback = function() setDPI(dpi_xxlarge) end
        },
        {
            text = T(_("Extra-Extra-Extra Large (%1)"), dpi_xxxlarge),
            checked_func = function()
                if isAutoDPI() then return false end
                local _dpi, _custom = dpi(), custom()
                return _dpi and _dpi > 560 and _dpi ~= _custom
            end,
            radio = true,
            callback = function() setDPI(dpi_xxxlarge) end
        },
        {
            text_func = function()
                local custom_dpi = custom() or dpi_auto
                if custom_dpi then
                    return T(_("Custom DPI: %1 (hold to set)"), custom() or dpi_auto)
                else
                    return _("Custom DPI")
                end
            end,
            checked_func = function()
                if isAutoDPI() then return false end
                local _dpi, _custom = dpi(), custom()
                return _custom and _dpi == _custom
            end,
            radio = true,
            callback = function(touchmenu_instance)
                if custom() then
                    setDPI(custom() or dpi_auto)
                else
                    spinWidgetSetDPI(touchmenu_instance)
                end
            end,
            hold_callback = function(touchmenu_instance)
                spinWidgetSetDPI(touchmenu_instance)
            end,
        },
    }
}
