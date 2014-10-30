local _ = require("gettext")
local Screen = require("device").screen


local function dpi() return G_reader_settings:readSetting("screen_dpi") end

local function custom() return G_reader_settings:readSetting("custom_screen_dpi") end

local function setDPI(dpi)
    local InfoMessage = require("ui/widget/infomessage")
    local UIManager = require("ui/uimanager")
    UIManager:show(InfoMessage:new{
        text = _("This will take effect on next restart."),
    })
    Screen:setDPI(dpi)
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
                local dpi, custom = dpi(), custom()
                return dpi and dpi <= 140 and dpi ~= custom
            end,
            callback = function() setDPI(120) end
        },
        {
            text = _("Medium"),
            checked_func = function()
                local dpi, custom = dpi(), custom()
                return dpi and dpi > 140 and dpi <= 200 and dpi ~= custom
            end,
            callback = function() setDPI(160) end
        },
        {
            text = _("Large"),
            checked_func = function()
                local dpi, custom = dpi(), custom()
                return dpi and dpi > 200 and dpi ~= custom
            end,
            callback = function() setDPI(240) end
        },
        {
            text = _("Custom DPI") .. ": " .. (custom() or 160),
            checked_func = function()
                local dpi, custom = dpi(), custom()
                return custom and dpi == custom
            end,
            callback = function() setDPI(custom() or 160) end,
            hold_input = {
                title = _("Input screen DPI"),
                type = "number",
                hint = "(90 - 330)",
                callback = function(input)
                    local dpi = tonumber(input)
                    dpi = dpi < 90 and 90 or dpi
                    dpi = dpi > 330 and 330 or dpi
                    G_reader_settings:saveSetting("custom_screen_dpi", dpi)
                    setDPI(dpi)
                end,
            },
        },
    }
}
