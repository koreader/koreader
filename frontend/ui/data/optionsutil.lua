--[[--
This module contains miscellaneous helper functions for the creoptions and koptoptions.
]]

local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local T = require("ffi/util").template
local logger = require("logger")

local optionsutil = {}

function optionsutil.enableIfEquals(configurable, option, value)
    return configurable[option] == value
end

function optionsutil.showValues(configurable, option, prefix, document)
    local default = G_reader_settings:readSetting(prefix.."_"..option.name)
    local current = configurable[option.name]
    local value_default, value_current
    if option.toggle and option.values then
        -- build a table so we can see if current/default settings map
        -- to a known setting with a name (in option.toggle)
        local arg_table = {}
        for i=1,#option.values do
            local val = option.values[i]
            -- flatten table to a string for easy lookup via arg_table
            if type(val) == "table" then val = table.concat(val, ",") end
            arg_table[val] = option.toggle[i]
        end
        value_current = current
        if type(current) == "table" then current = table.concat(current, ",") end
        current = arg_table[current]
        if not current then
            current = option.name_text_true_values and _("custom") or value_current
        end
        if option.show_true_value_func then
            value_current = option.show_true_value_func(value_current)
        end
        if default then
            value_default = default
            if type(default) == "table" then default = table.concat(default, ",") end
            default = arg_table[default]
            if not default then
                default = option.name_text_true_values and _("custom") or value_default
            end
            if option.show_true_value_func then
                value_default = option.show_true_value_func(value_default)
            end
        end
    elseif option.labels and option.values then
        if option.more_options_param and option.more_options_param.value_table then
            if option.more_options_param.args_table then
                for k,v in pairs(option.more_options_param.args_table) do
                    if v == current then
                        current = k
                        break
                    end
                end
            end
            current = option.more_options_param.value_table[current]
            if default then
                if option.more_options_param.args_table then
                    for k,v in pairs(option.more_options_param.args_table) do
                        if v == default then
                            default = k
                            break
                        end
                    end
                end
                default = option.more_options_param.value_table[default]
            end
        else
            if default then
                for i=1,#option.labels do
                    if default == option.values[i] then
                        default = option.labels[i]
                        break
                    end
                end
            end
            for i=1,#option.labels do
                if current == option.values[i] then
                    current = option.labels[i]
                    break
                end
            end
        end
    elseif option.show_true_value_func and option.values then
        current = option.show_true_value_func(current)
        if default then
            default = option.show_true_value_func(default)
        end
    end
    if not default then
        default = _("not set")
    end
    local help_text = ""
    if option.help_text then
        help_text = T("\n%1\n", option.help_text)
    end
    if option.help_text_func then
        -- Allow for concatenating a dynamic help_text_func to a static help_text
        help_text = T("%1\n%2\n", help_text, option.help_text_func(configurable, document))
    end
    local text
    local name_text = option.name_text_func
                      and option.name_text_func(configurable)
                       or option.name_text
    if option.name_text_true_values and option.toggle and option.values then
        if value_default then
            text = T(_("%1\n%2\nCurrent value: %3 (%4)\nDefault value: %5 (%6)"), name_text, help_text,
                                            current, value_current, default, value_default)
        else
            text = T(_("%1\n%2\nCurrent value: %3 (%4)\nDefault value: %5"), name_text, help_text,
                                            current, value_current, default)
        end
    else
        text = T(_("%1\n%2\nCurrent value: %3\nDefault value: %4"), name_text, help_text, current, default)
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

function optionsutil:generateOptionText()
    local CreOptions = require("ui/data/creoptions")

    self.option_text_table = {}
    self.option_args_table = {}
    for i = 1, #CreOptions do
        for j = 1, #CreOptions[i].options do
            local option = CreOptions[i].options[j]
            if option.event then
                if option.labels then
                    self.option_text_table[option.event] = option.labels
                elseif option.toggle then
                    self.option_text_table[option.event] = option.toggle
                end
                self.option_args_table[option.event] = option.args
            end
        end
    end
end

function optionsutil:getOptionText(event, val)
    if not self.option_text_table then
        self:generateOptionText()
    end
    if not event or val == nil then
        logger.err("[OptionsCatalog:getOptionText] Either event or val not set. This should not happen!")
        return ""
    end
    if not self.option_text_table[event] then
        logger.err("[OptionsCatalog:getOptionText] Event:" .. event .. " not found in option_text_table")
        return ""
    end

    local text
    if type(val) == "number" then
        text = self.option_text_table[event][val + 1] -- options count from zero
    end

    -- if there are args, try to find the adequate toggle
    if self.option_args_table[event] then
        for i, args in pairs(self.option_args_table[event]) do
            if args == val then
                text = self.option_text_table[event][i]
            end
        end
    end

    if text then
        return text
    else
        return val
    end
end

return optionsutil
