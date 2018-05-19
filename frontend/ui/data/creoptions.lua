local Device = require("device")
local InfoMessage = require("ui/widget/infomessage")
local S = require("ui/data/strings")
local UIManager = require("ui/uimanager")
local Screen = Device.screen
local T = require("ffi/util").template

local _ = require("gettext")

-- add multiply operator to Aa dict
local Aa = setmetatable({"Aa"}, {
    __mul = function(t, mul)
        local new = {}
        for i = 1, mul do
            for _, v in ipairs(t) do table.insert(new, v) end
        end
        return new
    end
})

local function enable_if_equals(configurable, option, value)
    return configurable[option] == value
end

local function showValues(configurable, option)
    local default = G_reader_settings:readSetting("copt_"..option.name)
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
    if option.name_text_true_values and option.toggle and option.values and value_default then
        UIManager:show(InfoMessage:new{
            text = T(_("%1:\nCurrent value: %2 (%5%4)\nDefault value: %3 (%6%4)"), option.name_text,
                current, default, suffix, value_current, value_default)
        })
    elseif option.name_text_true_values and option.toggle and option.values and not value_default then
        UIManager:show(InfoMessage:new{
            text = T(_("%1:\nCurrent value: %2 (%5%4)\nDefault value: %3"), option.name_text,
                current, default, suffix, value_current)
        })
    else
        UIManager:show(InfoMessage:new{
            text = T(_("%1:\nCurrent value: %2%4\nDefault value: %3%4"), option.name_text, current,
                default, suffix)
        })
    end
end

local function tableComp(a,b)
    if #a ~= #b then return false end
    for i=1,#a do
        if a[i] ~= b[i] then return false end
    end
    return true
end

local function showValuesMargins(configurable, option)
    local default = G_reader_settings:readSetting("copt_"..option.name)
    local current = configurable[option.name]
    local current_string
    for i=1,#option.toggle do
        if tableComp(current, option.values[i]) then
            current_string = option.toggle[i]
            break
        end
    end
    if not default then
        UIManager:show(InfoMessage:new{
            text = T(_([[
%1:
Current value: %2
  left: %3
  top: %4
  right: %5
  bottom: %6
Default value: not set]]),
                option.name_text, current_string, current[1], current[2], current[3], current[4])
        })
    else
        local default_string
        for i=1,#option.toggle do
            if tableComp(default, option.values[i]) then
                default_string = option.toggle[i]
                break
            end
        end
        UIManager:show(InfoMessage:new{
            text = T(_([[
%1:
Current value: %2
  left: %3
  top: %4
  right: %5
  bottom: %6
Default value: %7
  left: %8
  top: %9
  right: %10
  bottom: %11]]),
                option.name_text, current_string, current[1], current[2], current[3], current[4],
                default_string, default[1], default[2], default[3], default[4])
        })
    end
end

local CreOptions = {
    prefix = 'copt',
    {
        icon = "resources/icons/appbar.transform.rotate.right.large.png",
        options = {
            {
                name = "screen_mode",
                name_text = S.SCREEN_MODE,
                toggle = {S.PORTRAIT, S.LANDSCAPE},
                alternate = false,
                args = {"portrait", "landscape"},
                default_arg = "portrait",
                current_func = function() return Screen:getScreenMode() end,
                event = "ChangeScreenMode",
                name_text_hold_callback = showValues,
            }
        }
    },
    {
        icon = "resources/icons/appbar.column.two.large.png",
        options = {
            {
                name = "view_mode",
                name_text = S.VIEW_MODE,
                toggle = {S.VIEW_SCROLL, S.VIEW_PAGE},
                values = {1, 0},
                default_value = 0,
                args = {"scroll", "page"},
                default_arg = "page",
                event = "SetViewMode",
                name_text_hold_callback = showValues,
            },
            {
                name = "line_spacing",
                name_text = S.LINE_SPACING,
                toggle = {S.SMALL, S.MEDIUM, S.LARGE},
                values = {
                    DCREREADER_CONFIG_LINE_SPACE_PERCENT_SMALL,
                    DCREREADER_CONFIG_LINE_SPACE_PERCENT_MEDIUM,
                    DCREREADER_CONFIG_LINE_SPACE_PERCENT_LARGE,
                },
                default_value = DCREREADER_CONFIG_LINE_SPACE_PERCENT_MEDIUM,
                event = "SetLineSpace",
                args = {
                    DCREREADER_CONFIG_LINE_SPACE_PERCENT_SMALL,
                    DCREREADER_CONFIG_LINE_SPACE_PERCENT_MEDIUM,
                    DCREREADER_CONFIG_LINE_SPACE_PERCENT_LARGE,
                },
                name_text_hold_callback = showValues,
                -- used by showValues
                name_text_suffix = "%",
                name_text_true_values = true,
            },
            {
                name = "page_margins",
                name_text = S.PAGE_MARGIN,
                toggle = {S.SMALL, S.MEDIUM, S.LARGE},
                values = {
                    DCREREADER_CONFIG_MARGIN_SIZES_SMALL,
                    DCREREADER_CONFIG_MARGIN_SIZES_MEDIUM,
                    DCREREADER_CONFIG_MARGIN_SIZES_LARGE,
                },
                default_value = DCREREADER_CONFIG_MARGIN_SIZES_MEDIUM,
                event = "SetPageMargins",
                args = {
                    DCREREADER_CONFIG_MARGIN_SIZES_SMALL,
                    DCREREADER_CONFIG_MARGIN_SIZES_MEDIUM,
                    DCREREADER_CONFIG_MARGIN_SIZES_LARGE,
                },
                name_text_hold_callback = showValuesMargins,
            },
        }
    },
    {
        icon = "resources/icons/appbar.text.size.large.png",
        options = {
            {
                name = "font_size",
                item_text = Aa * #DCREREADER_CONFIG_FONT_SIZES,
                item_align_center = 1.0,
                spacing = 15,
                item_font_size = DCREREADER_CONFIG_FONT_SIZES,
                values = DCREREADER_CONFIG_FONT_SIZES,
                default_value = DCREREADER_CONFIG_DEFAULT_FONT_SIZE,
                args = DCREREADER_CONFIG_FONT_SIZES,
                event = "SetFontSize",
            },
            {
                name = "font_fine_tune",
                name_text = S.FONTSIZE_FINE_TUNING,
                toggle = Device:isTouchDevice() and {S.DECREASE, S.INCREASE} or nil,
                item_text = not Device:isTouchDevice() and {S.DECREASE, S.INCREASE} or nil,
                event = "ChangeSize",
                args = {"decrease", "increase"},
                alternate = false,
                name_text_hold_callback = function(configurable)
                    local opt = {
                        name = "font_size",
                        name_text = _("Font Size"),
                    }
                    showValues(configurable, opt)
                end
            }
        }
    },
    {
        icon = "resources/icons/appbar.grade.b.large.png",
        options = {
            {
                name = "font_weight",
                name_text = S.FONT_WEIGHT,
                toggle = {S.REGULAR, S.BOLD},
                values = {0, 1},
                default_value = 0,
                args = {0, 1},
                event = "ToggleFontBolder",
                name_text_hold_callback = showValues,
            },
            {
                name = "font_gamma",
                name_text = S.CONTRAST,
                buttonprogress = true,
                default_value = 15, -- gamma = 1.0
                default_pos = 2,
                values = {10, 15, 25, 30, 36, 43, 49, 56},
                event = "SetFontGamma",
                args = {10, 15, 25, 30, 36, 43, 49, 56},
                -- gamma values for these indexes are:
                labels = {0.8, 1.0, 1.45, 1.90, 2.50, 4.0, 8.0, 15.0},
                name_text_hold_callback = showValues,
            },
            {
                name = "font_hinting",
                name_text = S.FONT_HINT,
                toggle = {S.OFF, S.NATIVE, S.AUTO},
                values = {0, 1, 2},
                default_value = 2,
                args = {0, 1, 2},
                event = "SetFontHinting",
                name_text_hold_callback = showValues,
            }
        }
    },
    {
        icon = "resources/icons/appbar.settings.large.png",
        options = {
            {
                name = "status_line",
                name_text = S.PROGRESS_BAR,
                toggle = {S.FULL, S.MINI},
                values = {0, 1},
                default_value = DCREREADER_PROGRESS_BAR,
                args = {0, 1},
                default_arg = DCREREADER_PROGRESS_BAR,
                event = "SetStatusLine",
                name_text_hold_callback = showValues,
            },
            {
                name = "embedded_css",
                name_text = S.EMBEDDED_STYLE,
                toggle = {S.ON, S.OFF},
                values = {1, 0},
                default_value = 1,
                args = {true, false},
                default_arg = nil,
                event = "ToggleEmbeddedStyleSheet",
                name_text_hold_callback = showValues,
            },
            {
                name = "embedded_fonts",
                name_text = S.EMBEDDED_FONTS,
                toggle = {S.ON, S.OFF},
                values = {1, 0},
                default_value = 1,
                args = {true, false},
                default_arg = nil,
                event = "ToggleEmbeddedFonts",
                enabled_func = function(configurable)
                    return enable_if_equals(configurable, "embedded_css", 1)
                end,
                name_text_hold_callback = showValues,
            },
        },
    },
}

return CreOptions
