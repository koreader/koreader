local UIManager = require("ui/uimanager")
local util = require("ffi/util")
local _ = require("gettext")

local function custom_1() return G_reader_settings:readSetting("refresh_rate_1") or 12 end

local function custom_2() return G_reader_settings:readSetting("refresh_rate_2") or 22 end

local function custom_3() return G_reader_settings:readSetting("refresh_rate_3") or 99 end

local function custom_input(name)
    return {
        title = _("Input page number for a full refresh"),
        type = "number",
        hint = "(1 - 99)",
        callback = function(input)
            local rate = tonumber(input)
            G_reader_settings:saveSetting(name, rate)
            UIManager:setRefreshRate(rate)
        end,
    }
end

return {
    text = _("E-ink full refresh rate"),
    sub_item_table = {
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
                return util.template(
                    _("Custom 1: %1 pages"),
                    custom_1()
                )
            end,
            checked_func = function() return UIManager:getRefreshRate() == custom_1() end,
            callback = function() UIManager:setRefreshRate(custom_1()) end,
            hold_input = custom_input("refresh_rate_1")
        },
        {
            text_func = function()
                return util.template(
                    _("Custom 2: %1 pages"),
                    custom_2()
                )
            end,
            checked_func = function() return UIManager:getRefreshRate() == custom_2() end,
            callback = function() UIManager:setRefreshRate(custom_2()) end,
            hold_input = custom_input("refresh_rate_2")
        },
        {
            text_func = function()
                return util.template(
                    _("Custom 3: %1 pages"),
                    custom_3()
                )
            end,
            checked_func = function() return UIManager:getRefreshRate() == custom_3() end,
            callback = function() UIManager:setRefreshRate(custom_3()) end,
            hold_input = custom_input("refresh_rate_3")
        },
    }
}
