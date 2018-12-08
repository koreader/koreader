local _ = require("gettext")
local Screen = require("device").screen
local T = require("ffi/util").template


local function dpi() return G_reader_settings:readSetting("screen_dpi") end

local function custom() return G_reader_settings:readSetting("custom_screen_dpi") end

local function setDPI(_dpi)
    local InfoMessage = require("ui/widget/infomessage")
    local UIManager = require("ui/uimanager")
    UIManager:show(InfoMessage:new{
        text = T(_("DPI set to %1. This will take effect after restarting."), _dpi),
    })
    G_reader_settings:saveSetting("screen_dpi", _dpi)
    Screen:setDPI(_dpi)
end

local dpi_auto = Screen:getDPI()
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
            text = T(_("Auto DPI (%1)"), dpi_auto),
            help_text = _("The DPI of your screen is automatically detected so items can be drawn with the right amount of pixels. This will usually display at (roughly) the same size on different devices, while remaining sharp. Increasing the DPI setting will result in larger text and icons, while a lower DPI setting will look smaller on the screen."),
            checked_func = function()
                return dpi() == nil
            end,
            callback = function() setDPI() end
        },
        {
            text = T(_("Small (%1)"), dpi_small),
            checked_func = function()
                local _dpi, _custom = dpi(), custom()
                return _dpi and _dpi <= 140 and _dpi ~= _custom
            end,
            callback = function() setDPI(dpi_small) end
        },
        {
            text = T(_("Medium (%1)"), dpi_medium),
            checked_func = function()
                local _dpi, _custom = dpi(), custom()
                return _dpi and _dpi > 140 and _dpi <= 200 and _dpi ~= _custom
            end,
            callback = function() setDPI(dpi_medium) end
        },
        {
            text = T(_("Large (%1)"), dpi_large),
            checked_func = function()
                local _dpi, _custom = dpi(), custom()
                return _dpi and _dpi > 200 and _dpi <= 280 and _dpi ~= _custom
            end,
            callback = function() setDPI(dpi_large) end
        },
        {
            text = T(_("Extra large (%1)"), dpi_xlarge),
            checked_func = function()
                local _dpi, _custom = dpi(), custom()
                return _dpi and _dpi > 280 and _dpi <= 400 and _dpi ~= _custom
            end,
            callback = function() setDPI(dpi_xlarge) end
        },
        {
            text = T(_("Extra-Extra Large (%1)"), dpi_xxlarge),
            checked_func = function()
                local _dpi, _custom = dpi(), custom()
                return _dpi and _dpi > 400 and _dpi <= 560 and _dpi ~= _custom
            end,
            callback = function() setDPI(dpi_xxlarge) end
        },
        {
            text = T(_("Extra-Extra-Extra Large (%1)"), dpi_xxxlarge),
            checked_func = function()
                local _dpi, _custom = dpi(), custom()
                return _dpi and _dpi > 560 and _dpi ~= _custom
            end,
            callback = function() setDPI(dpi_xxxlarge) end
        },
        {
            text_func = function()
                return T(_("Custom DPI: %1 (hold to set)"), custom() or dpi_auto)
            end,
            checked_func = function()
                local _dpi, _custom = dpi(), custom()
                return _custom and _dpi == _custom
            end,
            callback = function() setDPI(custom() or dpi_auto) end,
            hold_input = {
                title = _("Enter custom screen DPI"),
                type = "number",
                hint = "(90 - 900)",
                callback = function(input)
                    local _dpi = tonumber(input)
                    _dpi = _dpi < 90 and 90 or _dpi
                    _dpi = _dpi > 900 and 900 or _dpi
                    G_reader_settings:saveSetting("custom_screen_dpi", _dpi)
                    setDPI(_dpi)
                end,
                ok_text = _("Set custom DPI"),
            },
        },
    }
}
