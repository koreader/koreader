local Device = require("device")
local S = require("ui/data/strings")
local optionsutil = require("ui/data/optionsutil")
local _ = require("gettext")
local Screen = Device.screen

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
                name_text_hold_callback = optionsutil.showValues,
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
                name_text_hold_callback = optionsutil.showValues,
            },
            {
                name = "render_dpi",
                name_text = S.ZOOM_DPI,
                toggle = {S.OFF, "48", "96¹’¹", "167", "212", "300"},
                values = {0, 48, 96, 167, 212, 300},
                default_value = 96,
                args = {0, 48, 96, 167, 212, 300},
                event = "SetRenderDPI",
                name_text_hold_callback = optionsutil.showValues,
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
                name_text_hold_callback = optionsutil.showValues,
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
                name_text_hold_callback = optionsutil.showValuesMargins,
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
                name_text_hold_callback = function(configurable, __, prefix)
                    local opt = {
                        name = "font_size",
                        name_text = _("Font Size"),
                    }
                    optionsutil.showValues(configurable, opt, prefix)
                end,
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
                name_text_hold_callback = optionsutil.showValues,
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
                name_text_hold_callback = optionsutil.showValues,
            },
            {
                name = "font_hinting",
                name_text = S.FONT_HINT,
                toggle = {S.OFF, S.NATIVE, S.AUTO},
                values = {0, 1, 2},
                default_value = 2,
                args = {0, 1, 2},
                event = "SetFontHinting",
                name_text_hold_callback = optionsutil.showValues,
            },
            {
                name = "space_condensing",
                name_text = S.WORD_GAP,
                toggle = {S.SMALL, S.MEDIUM, S.LARGE},
                values = {
                    DCREREADER_CONFIG_WORD_GAP_SMALL,
                    DCREREADER_CONFIG_WORD_GAP_MEDIUM,
                    DCREREADER_CONFIG_WORD_GAP_LARGE,
                },
                default_value = DCREREADER_CONFIG_WORD_GAP_MEDIUM,
                args = {
                    DCREREADER_CONFIG_WORD_GAP_SMALL,
                    DCREREADER_CONFIG_WORD_GAP_MEDIUM,
                    DCREREADER_CONFIG_WORD_GAP_LARGE,
                    },
                event = "SetSpaceCondensing",
                name_text_hold_callback = optionsutil.showValues,
                -- used by showValues
                name_text_suffix = "%",
                name_text_true_values = true,
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
                name_text_hold_callback = optionsutil.showValues,
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
                name_text_hold_callback = optionsutil.showValues,
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
                    return optionsutil.enableIfEquals(configurable, "embedded_css", 1)
                end,
                name_text_hold_callback = optionsutil.showValues,
            },
        },
    },
}

return CreOptions
