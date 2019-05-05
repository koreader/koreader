local Device = require("device")
local S = require("ui/data/strings")
local optionsutil = require("ui/data/optionsutil")
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
                current_func = function() return Device.screen:getScreenMode() end,
                event = "ChangeScreenMode",
                name_text_hold_callback = optionsutil.showValues,
            },
            {
                name = "visible_pages",
                name_text = S.DUAL_PAGES,
                toggle = {S.OFF, S.ON},
                values = {1, 2},
                default_value = 1,
                args = {1, 2},
                default_arg = 1,
                event = "SetVisiblePages",
                current_func = function()
                    -- If not in landscape mode, shows "1" as selected
                    if Device.screen:getScreenMode() ~= "landscape" then
                        return 1
                    end
                    -- if we return nil, ConfigDialog will pick the one from the
                    -- configurable as if we hadn't provided this 'current_func'
                end,
                enabled_func = function(configurable)
                    return Device.screen:getScreenMode() == "landscape" and
                        optionsutil.enableIfEquals(configurable, "view_mode", 0) -- "page"
                end,
                name_text_hold_callback = optionsutil.showValues,
                help_text = _([[In landscape mode, you can choose to display one or two pages of the book on the screen.
Note that this may not be ensured under some conditions: in scroll mode, when a very big font size is used, or on devices with a very low aspect ratio.]]),
            },
        }
    },
    {
        icon = "resources/icons/appbar.crop.large.png",
        options = {
            {
                name = "h_page_margins",
                name_text = S.H_PAGE_MARGINS,
                buttonprogress = true,
                values = {
                    DCREREADER_CONFIG_H_MARGIN_SIZES_SMALL,
                    DCREREADER_CONFIG_H_MARGIN_SIZES_MEDIUM,
                    DCREREADER_CONFIG_H_MARGIN_SIZES_LARGE,
                    DCREREADER_CONFIG_H_MARGIN_SIZES_X_LARGE,
                    DCREREADER_CONFIG_H_MARGIN_SIZES_XX_LARGE,
                    DCREREADER_CONFIG_H_MARGIN_SIZES_XXX_LARGE,
                    DCREREADER_CONFIG_H_MARGIN_SIZES_HUGE,
                    DCREREADER_CONFIG_H_MARGIN_SIZES_X_HUGE,
                    DCREREADER_CONFIG_H_MARGIN_SIZES_XX_HUGE,
                },
                default_pos = 2,
                default_value = DCREREADER_CONFIG_H_MARGIN_SIZES_MEDIUM,
                event = "SetPageHorizMargins",
                args = {
                    DCREREADER_CONFIG_H_MARGIN_SIZES_SMALL,
                    DCREREADER_CONFIG_H_MARGIN_SIZES_MEDIUM,
                    DCREREADER_CONFIG_H_MARGIN_SIZES_LARGE,
                    DCREREADER_CONFIG_H_MARGIN_SIZES_X_LARGE,
                    DCREREADER_CONFIG_H_MARGIN_SIZES_XX_LARGE,
                    DCREREADER_CONFIG_H_MARGIN_SIZES_XXX_LARGE,
                    DCREREADER_CONFIG_H_MARGIN_SIZES_HUGE,
                    DCREREADER_CONFIG_H_MARGIN_SIZES_X_HUGE,
                    DCREREADER_CONFIG_H_MARGIN_SIZES_XX_HUGE,
                },
                delay_repaint = true,
                name_text_hold_callback = optionsutil.showValuesHMargins,
            },
            {
                name = "sync_t_b_page_margins",
                name_text = S.SYNC_T_B_PAGE_MARGINS,
                toggle = {S.OFF, S.ON},
                values = {0, 1},
                default_value = 0,
                event = "SyncPageTopBottomMargins",
                args = {false, true},
                default_arg = false,
                delay_repaint = true,
                name_text_hold_callback = optionsutil.showValues,
                help_text = _([[Keep top and bottom margins synchronized.
- 'off' allows different top and bottom margins.
- 'on' keeps top and bottom margins locked, ensuring text is vertically centered in the page.

In the top menu → Settings → Status bar, you can choose whether the bottom margin applies from the bottom of the screen, or from above the status bar.]]),
            },
            {
                name = "t_page_margin",
                name_text = S.T_PAGE_MARGIN,
                buttonprogress = true,
                fine_tune = true,
                values = {
                    DCREREADER_CONFIG_T_MARGIN_SIZES_SMALL,
                    DCREREADER_CONFIG_T_MARGIN_SIZES_MEDIUM,
                    DCREREADER_CONFIG_T_MARGIN_SIZES_LARGE,
                    DCREREADER_CONFIG_T_MARGIN_SIZES_X_LARGE,
                    DCREREADER_CONFIG_T_MARGIN_SIZES_XX_LARGE,
                    DCREREADER_CONFIG_T_MARGIN_SIZES_XXX_LARGE,
                    DCREREADER_CONFIG_T_MARGIN_SIZES_HUGE,
                    DCREREADER_CONFIG_T_MARGIN_SIZES_X_HUGE,
                    DCREREADER_CONFIG_T_MARGIN_SIZES_XX_HUGE,
                },
                default_pos = 3,
                default_value = DCREREADER_CONFIG_T_MARGIN_SIZES_LARGE,
                event = "SetPageTopMargin",
                args = {
                    DCREREADER_CONFIG_T_MARGIN_SIZES_SMALL,
                    DCREREADER_CONFIG_T_MARGIN_SIZES_MEDIUM,
                    DCREREADER_CONFIG_T_MARGIN_SIZES_LARGE,
                    DCREREADER_CONFIG_T_MARGIN_SIZES_X_LARGE,
                    DCREREADER_CONFIG_T_MARGIN_SIZES_XX_LARGE,
                    DCREREADER_CONFIG_T_MARGIN_SIZES_XXX_LARGE,
                    DCREREADER_CONFIG_T_MARGIN_SIZES_HUGE,
                    DCREREADER_CONFIG_T_MARGIN_SIZES_X_HUGE,
                    DCREREADER_CONFIG_T_MARGIN_SIZES_XX_HUGE,
                },
                delay_repaint = true,
                name_text_hold_callback = optionsutil.showValues,
            },
            {
                name = "b_page_margin",
                name_text = S.B_PAGE_MARGIN,
                buttonprogress = true,
                fine_tune = true,
                values = {
                    DCREREADER_CONFIG_B_MARGIN_SIZES_SMALL,
                    DCREREADER_CONFIG_B_MARGIN_SIZES_MEDIUM,
                    DCREREADER_CONFIG_B_MARGIN_SIZES_LARGE,
                    DCREREADER_CONFIG_B_MARGIN_SIZES_X_LARGE,
                    DCREREADER_CONFIG_B_MARGIN_SIZES_XX_LARGE,
                    DCREREADER_CONFIG_B_MARGIN_SIZES_XXX_LARGE,
                    DCREREADER_CONFIG_B_MARGIN_SIZES_HUGE,
                    DCREREADER_CONFIG_B_MARGIN_SIZES_X_HUGE,
                    DCREREADER_CONFIG_B_MARGIN_SIZES_XX_HUGE,
                },
                default_pos = 3,
                default_value = DCREREADER_CONFIG_B_MARGIN_SIZES_LARGE,
                event = "SetPageBottomMargin",
                args = {
                    DCREREADER_CONFIG_B_MARGIN_SIZES_SMALL,
                    DCREREADER_CONFIG_B_MARGIN_SIZES_MEDIUM,
                    DCREREADER_CONFIG_B_MARGIN_SIZES_LARGE,
                    DCREREADER_CONFIG_B_MARGIN_SIZES_X_LARGE,
                    DCREREADER_CONFIG_B_MARGIN_SIZES_XX_LARGE,
                    DCREREADER_CONFIG_B_MARGIN_SIZES_XXX_LARGE,
                    DCREREADER_CONFIG_B_MARGIN_SIZES_HUGE,
                    DCREREADER_CONFIG_B_MARGIN_SIZES_X_HUGE,
                    DCREREADER_CONFIG_B_MARGIN_SIZES_XX_HUGE,
                },
                delay_repaint = true,
                name_text_hold_callback = optionsutil.showValues,
                help_text = _([[In the top menu → Settings → Status bar, you can choose whether the bottom margin applies from the bottom of the screen, or from above the status bar.]]),
            },
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
                help_text = _([[- 'scroll' mode allows you to scroll the text like you would in a web browser (the 'Page Overlap' setting is only available in this mode).
- 'page' mode splits the text into pages, at the most acceptable places (page numbers and the number of pages may change when you change fonts, margins, styles, etc.).]]),
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
                help_text = _([[Sets the DPI used to scale absolute CSS units and images:
- off: ignore absolute units (old engine behavior).
- 96¹’¹: at 96 DPI, 1 CSS pixel = 1 screen pixel and images are rendered at their original dimensions.
- other values scale CSS absolute units and images by a factor (300 DPI = x3, 48 DPI = x0.5)
Using your device's actual DPI will ensure 1 cm in CSS actually translates to 1 cm on screen.
Note that your selected font size is not affected by this setting.]]),
            },
            {
                name = "line_spacing",
                name_text = S.LINE_SPACING,
                buttonprogress = true,
                values = {
                    DCREREADER_CONFIG_LINE_SPACE_PERCENT_X_TINY,
                    DCREREADER_CONFIG_LINE_SPACE_PERCENT_TINY,
                    DCREREADER_CONFIG_LINE_SPACE_PERCENT_XX_SMALL,
                    DCREREADER_CONFIG_LINE_SPACE_PERCENT_X_SMALL,
                    DCREREADER_CONFIG_LINE_SPACE_PERCENT_SMALL,
                    DCREREADER_CONFIG_LINE_SPACE_PERCENT_L_SMALL,
                    DCREREADER_CONFIG_LINE_SPACE_PERCENT_MEDIUM,
                    DCREREADER_CONFIG_LINE_SPACE_PERCENT_L_MEDIUM,
                    DCREREADER_CONFIG_LINE_SPACE_PERCENT_XL_MEDIUM,
                    DCREREADER_CONFIG_LINE_SPACE_PERCENT_XXL_MEDIUM,
                    DCREREADER_CONFIG_LINE_SPACE_PERCENT_LARGE,
                    DCREREADER_CONFIG_LINE_SPACE_PERCENT_X_LARGE,
                    DCREREADER_CONFIG_LINE_SPACE_PERCENT_XX_LARGE,
                },
                default_pos = 7,
                default_value = DCREREADER_CONFIG_LINE_SPACE_PERCENT_MEDIUM,
                event = "SetLineSpace",
                args = {
                    DCREREADER_CONFIG_LINE_SPACE_PERCENT_X_TINY,
                    DCREREADER_CONFIG_LINE_SPACE_PERCENT_TINY,
                    DCREREADER_CONFIG_LINE_SPACE_PERCENT_XX_SMALL,
                    DCREREADER_CONFIG_LINE_SPACE_PERCENT_X_SMALL,
                    DCREREADER_CONFIG_LINE_SPACE_PERCENT_SMALL,
                    DCREREADER_CONFIG_LINE_SPACE_PERCENT_L_SMALL,
                    DCREREADER_CONFIG_LINE_SPACE_PERCENT_MEDIUM,
                    DCREREADER_CONFIG_LINE_SPACE_PERCENT_L_MEDIUM,
                    DCREREADER_CONFIG_LINE_SPACE_PERCENT_XL_MEDIUM,
                    DCREREADER_CONFIG_LINE_SPACE_PERCENT_XXL_MEDIUM,
                    DCREREADER_CONFIG_LINE_SPACE_PERCENT_LARGE,
                    DCREREADER_CONFIG_LINE_SPACE_PERCENT_X_LARGE,
                    DCREREADER_CONFIG_LINE_SPACE_PERCENT_XX_LARGE,
                },
                name_text_hold_callback = optionsutil.showValues,
                -- used by showValues
                name_text_suffix = "%",
                name_text_true_values = true,
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
                help_text = _([[Font hinting is the process by which fonts are adjusted for maximum readability on the screen's pixel grid.

- off: no hinting.
- native: use the font internal hinting instructions.
- auto: use FreeType's hinting algorithm, ignoring font instructions.]]),
            },
            {
                name = "font_kerning",
                name_text = S.FONT_KERNING,
                toggle = {S.OFF, S.FAST, S.GOOD, S.BEST},
                values = {0, 1, 2, 3},
                default_value = 1,
                args = {0, 1, 2, 3},
                event = "SetFontKerning",
                name_text_hold_callback = optionsutil.showValues,
                help_text = _([[Font kerning is the process of adjusting the spacing between individual letter forms, to achieve a visually pleasing result.

- off: no kerning.
- fast: use FreeType's kerning implementation (no ligatures).
- good: use HarfBuzz's light kerning implementation (faster than full but no ligatures and limited support for non-western scripts)
- best: use HarfBuzz's full kerning implementation (slower, but may support ligatures with some fonts).

(Font Hinting may need to be adjusted for the best result with either kerning implementation.)]]),
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
                help_text = _([[Tells the rendering engine how much each 'space' character in the text can be reduced from its regular width to make words fit on a line (100% means no reduction).]]),
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
                help_text = _([[- 'full' displays a status bar at the top of the screen (this status bar can't be customized).
- 'mini' displays a status bar at the bottom of the screen, which can be toggled by tapping. The items displayed can be customized via the main menu.]]),
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
                help_text = _([[Enable or disable publisher stylesheets embedded in the book.
(Note that less radical changes can be achieved via Style Tweaks in the main menu.)]]),
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
                help_text = _([[Enable or disable the use of the fonts embedded in the book.
(Disabling the fonts specified in the publisher stylesheets can also be achieved via Style Tweaks in the main menu.)]]),
            },
            {
                name = "smooth_scaling",
                name_text = S.IMAGE_SCALING,
                toggle = {S.FAST, S.BEST},
                values = {0, 1},
                default_value = 0,
                args = {false, true},
                default_arg = nil,
                event = "ToggleImageScaling",
                name_text_hold_callback = optionsutil.showValues,
                help_text = _([[- 'fast' uses a fast but inaccurate scaling algorithm when scaling images.
- 'best' switches to a more costly but vastly more pleasing and accurate algorithm.]]),
            },
        },
    },
}

return CreOptions
