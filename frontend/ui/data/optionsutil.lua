--[[--
This module contains miscellaneous helper functions for the creoptions and koptoptions.
]]

local Device = require("device")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local C_ = _.pgettext
local T = require("ffi/util").template
local logger = require("logger")
local Screen = Device.screen

local optionsutil = {
    rotation_labels = {
        C_("Rotation", "⤹ 90°"),
        C_("Rotation", "↑ 0°"),
        C_("Rotation", "⤸ 90°"),
        C_("Rotation", "↓ 180°"),
    },
    rotation_modes = {
        Screen.DEVICE_ROTATED_COUNTER_CLOCKWISE, -- 3
        Screen.DEVICE_ROTATED_UPRIGHT,           -- 0
        Screen.DEVICE_ROTATED_CLOCKWISE,         -- 1
        Screen.DEVICE_ROTATED_UPSIDE_DOWN,       -- 2
    },
}

function optionsutil.enableIfEquals(configurable, option, value)
    return configurable[option] == value
end

-- Converts flex px/pt sizes to absolute px, mm, inch or pt
local function convertSizeTo(px, format)
    local format_factor

    if format == "px" then
        return Screen:scaleBySize(px)
    elseif format == "pt" then
        -- PostScript point,
        -- c.f., https://en.wikipedia.org/wiki/Metric_typographic_units
        --     & https://freetype.org/freetype2/docs/glyphs/glyphs-2.html
        format_factor = 72
    elseif format == "in" then
        format_factor = 1
    else
        -- i.e., Metric
        format_factor = 25.4
    end

    -- We want the actual physical screen DPI if available, not a user override
    local display_dpi = Device:getDeviceScreenDPI() or Screen:getDPI()
    return Screen:scaleBySize(px) / display_dpi * format_factor
end

local function formatFlexSize(value, unit)
    if not value then
        -- This shouldn't really ever happen...
        return ""
    end
    if not unit then
        return tostring(value)
    end

    local size = tonumber(value)
    if not size then
        return tostring(value)
    end

    local shown_unit = unit
    local fmt = "%d (%.2f %s)"
    if unit == "pt" then
        shown_unit = C_("Font size", "pt")
    elseif unit == "mm" then
        shown_unit = C_("Length", "mm")
    elseif unit == "in" then
        shown_unit = C_("Length", "in")
    elseif unit == "px" then
        shown_unit = C_("Pixels", "px")
        -- We don't do subpixel positioning ;)
        fmt = "%d (%d %s)"
    end

    if G_reader_settings:isTrue("dimension_units_append_px") and unit ~= "px" then
        local px_str = C_("Pixels", "px")
        return string.format(fmt .. " [%d %s]", size, convertSizeTo(size, unit), shown_unit,
                                                      convertSizeTo(size, "px"), px_str)
    else
        return string.format(fmt, size, convertSizeTo(size, unit), shown_unit)
    end
end

-- Public wrapper for callers outside of ConfigOption, where we can't pull name_text_unit from option
function optionsutil.formatFlexSize(value, unit)
    unit = unit or G_reader_settings:readSetting("dimension_units", "mm")
    return formatFlexSize(value, unit)
end

-- This is used extensively in ui/data/(cre|kopt)options as a `name_text_hold_callback`.
-- `ConfigOption` will *never* pass the `unit` argument, though,
-- so if it's unset, we'll try to pull it from `option`'s `name_text_unit` field.
-- This field can be left unset (which is the vast majority of cases),
-- in which case we don't do anything fancy with the value,
-- or it can be set to an explicit unit (e.g., "pt" or "px"),
-- in which case we append the results of a conversion to that unit in the final string.
-- It can also be set to `true`, in which case the unit is pulled from user settings ("dimension_units").
function optionsutil.showValues(configurable, option, prefix, document, unit)
    local default = G_reader_settings:readSetting(prefix.."_"..option.name)
    local current = configurable[option.name]
    local value_default, value_current
    unit = unit or option.name_text_unit
    if unit and unit ~= "pt" then
        unit = G_reader_settings:readSetting("dimension_units", "mm")
    end
    if option.toggle and option.values then
        -- build a table so we can see if current/default settings map
        -- to a known setting with a name (in option.toggle)
        local arg_table = {}
        for i=1, #option.values do
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
            local table_shift = option.more_options_param.value_table_shift or 0
            current = option.more_options_param.value_table[current + table_shift]
            if default then
                default = option.more_options_param.value_table[default + table_shift]
            end
        else
            if default then
                for i=1, #option.labels do
                    if default == option.values[i] then
                        default = option.labels[i]
                        break
                    end
                end
            end
            for i=1, #option.labels do
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
        local more_text = option.help_text_func(configurable, document)
        if more_text and more_text ~= "" then
            help_text = T("%1\n%2\n", help_text, more_text)
        end
    end
    local text
    local name_text = option.name_text_func
                      and option.name_text_func(configurable)
                      or option.name_text
    if option.name_text_true_values and option.toggle and option.values then
        local nb_current, nb_default = tonumber(current), tonumber(default)
        if nb_current == nil or nb_default == nil then
            text = T(_("%1\n%2\nCurrent value: %3\nDefault value: %4"), name_text, help_text,
                                            formatFlexSize(value_current or current, unit),
                                            formatFlexSize(value_default or default, unit))
        elseif value_default then
            text = T(_("%1\n%2\nCurrent value: %3 (%4)\nDefault value: %5 (%6)"), name_text, help_text,
                                            current, formatFlexSize(value_current, unit),
                                            default, formatFlexSize(value_default, unit))
        else
            text = T(_("%1\n%2\nCurrent value: %3 (%4)\nDefault value: %5"), name_text, help_text,
                                            current, formatFlexSize(value_current, unit),
                                            default)
        end
    else
        text = T(_("%1\n%2\nCurrent value: %3\nDefault value: %4"), name_text, help_text,
                                            formatFlexSize(current, unit),
                                            formatFlexSize(default, unit))
    end
    UIManager:show(InfoMessage:new{ text=text })
end

function optionsutil.showValuesHMargins(configurable, option)
    local default = G_reader_settings:readSetting("copt_"..option.name)
    local current = configurable[option.name]
    local unit = G_reader_settings:readSetting("dimension_units", "mm")
    if not default then
        UIManager:show(InfoMessage:new{
            text = T(_([[
Current margins:
  left: %1
  right: %2
Default margins: not set]]),
                formatFlexSize(current[1], unit),
                formatFlexSize(current[2], unit))
        })
    else
        UIManager:show(InfoMessage:new{
            text = T(_([[
Current margins:
  left: %1
  right: %2
Default margins:
  left: %3
  right: %4]]),
                formatFlexSize(current[1], unit),
                formatFlexSize(current[2], unit),
                formatFlexSize(default[1], unit),
                formatFlexSize(default[2], unit))
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
