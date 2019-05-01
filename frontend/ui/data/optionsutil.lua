--[[--
This module contains miscellaneous helper functions for the creoptions and koptoptions.
]]

local Device = require("device")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local Screen = Device.screen
local T = require("ffi/util").template

local optionsutil = {}

function optionsutil.enableIfEquals(configurable, option, value)
    return configurable[option] == value
end

function optionsutil.showValues(configurable, option, prefix)
    local default = G_reader_settings:readSetting(prefix.."_"..option.name)
    local current = configurable[option.name]
    local value_default, value_current
    local suffix = option.name_text_suffix or ""
    if option.name == "screen_mode" then
        current = Screen:getScreenMode()
    end
    local arg_table = {}
    if option.toggle and option.values then
        for i=1,#option.toggle do
            arg_table[option.values[i]] = option.toggle[i]
        end
    end
    if not default then
        default = "not set"
        if option.toggle and option.values then
            value_current = current
            current = arg_table[current]
        end
    elseif option.toggle and option.values then
        value_current = current
        value_default = default
        default = arg_table[default]
        current = arg_table[current]
    end
    if option.labels and option.values then
        for i=1,#option.labels do
            if default == option.values[i] then
                default = option.labels[i]
                break
            end
        end
        for i=1,#option.labels do
            if current == option.values[i] then
                current = option.labels[i]
                break
            end
        end
    end
    local help_text = ""
    if option.help_text then
        help_text = T("\n%1\n", option.help_text)
    end
    local text
    if option.name_text_true_values and option.toggle and option.values and value_default then
        text = T(_("%1:\n%2\nCurrent value: %3 (%6%5)\nDefault value: %4 (%7%5)"), option.name_text, help_text,
            current, default, suffix, value_current, value_default)
    elseif option.name_text_true_values and option.toggle and option.values and not value_default then
        text = T(_("%1\n%2\nCurrent value: %3 (%6%5)\nDefault value: %4"), option.name_text, help_text,
            current, default, suffix, value_current)
    else
        text = T(_("%1\n%2\nCurrent value: %3%5\nDefault value: %4%5"), option.name_text, help_text,
            current, default, suffix)
    end
    UIManager:show(InfoMessage:new{ text=text })
end

function optionsutil.showValuesHMargins(configurable, option)
    local default = G_reader_settings:readSetting("copt_"..option.name)
    local current = configurable[option.name]
    if not default then
        UIManager:show(InfoMessage:new{
            text = T(_([[
Current margins:
  left:  %1
  right: %2
Default margins: not set]]),
                current[1], current[2])
        })
    else
        UIManager:show(InfoMessage:new{
            text = T(_([[
Current margins:
  left:  %1
  right: %2
Default margins:
  left:  %3
  right: %4]]),
                current[1], current[2],
                default[1], default[2])
        })
    end
end

return optionsutil
