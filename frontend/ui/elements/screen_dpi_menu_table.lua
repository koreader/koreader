local _ = require("gettext")
local Screen = require("device").screen
local T = require("ffi/util").template


local function dpi() return G_reader_settings:readSetting("screen_dpi") end

local function custom() return G_reader_settings:readSetting("custom_screen_dpi") end

local function setDPI(_dpi)
    local InfoMessage = require("ui/widget/infomessage")
    local UIManager = require("ui/uimanager")
    UIManager:show(InfoMessage:new{
        text = _("This will take effect after restarting."),
    })
    Screen:setDPI(_dpi)
end


return {
    text = _("Screen DPI"),
    sub_item_table = {
        {
            text = _("Auto"),
            checked_func = function()
                return dpi() == nil
            end,
            callback = function() setDPI() end
        },
        {
            text = _("Small"),
            checked_func = function()
                local _dpi, _custom = dpi(), custom()
                return _dpi and _dpi <= 140 and _dpi ~= _custom
            end,
            callback = function() setDPI(120) end
        },
        {
            text = _("Medium"),
            checked_func = function()
                local _dpi, _custom = dpi(), custom()
                return _dpi and _dpi > 140 and _dpi <= 200 and _dpi ~= _custom
            end,
            callback = function() setDPI(160) end
        },
        {
            text = _("Large"),
            checked_func = function()
                local _dpi, _custom = dpi(), custom()
                return _dpi and _dpi > 200 and _dpi ~= _custom
            end,
            callback = function() setDPI(240) end
        },
        {
            text = T(_("Custom DPI: %1 (hold to set)"), custom() or 160),
            checked_func = function()
                local _dpi, _custom = dpi(), custom()
                return _custom and _dpi == _custom
            end,
            callback = function() setDPI(custom() or 160) end,
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
