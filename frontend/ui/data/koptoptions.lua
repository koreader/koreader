local Device = require("device")
local S = require("ui/data/strings")
local optionsutil = require("ui/data/optionsutil")
local _ = require("gettext")
local Screen = Device.screen

local KoptOptions = {
    prefix = 'kopt',
    needs_redraw_on_change = true,
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
                event = "SwapScreenMode",
                name_text_hold_callback = optionsutil.showValues,
            }
        }
    },
    {
        icon = "resources/icons/appbar.crop.large.png",
        options = {
            {
                name = "trim_page",
                name_text = S.PAGE_CROP,
                toggle = {S.MANUAL, S.AUTO, S.SEMIAUTO, S.NONE},
                alternate = false,
                values = {0, 1, 2, 3},
                default_value = DKOPTREADER_CONFIG_TRIM_PAGE,
                enabled_func = Device.isTouchDevice,
                event = "PageCrop",
                args = {"manual", "auto", "semi-auto", "none"},
                name_text_hold_callback = optionsutil.showValues,
            }
        }
    },
    {
        icon = "resources/icons/appbar.column.two.large.png",
        options = {
            {
                name = "page_scroll",
                name_text = S.SCROLL_MODE,
                toggle = {S.ON, S.OFF},
                values = {1, 0},
                default_value = DSCROLL_MODE,
                event = "SetScrollMode",
                args = {true, false},
                name_text_hold_callback = optionsutil.showValues,
            },
            {
                name = "full_screen",
                name_text = S.PROGRESS_BAR,
                toggle = {S.OFF, S.ON},
                values = {1, 0},
                default_value = DFULL_SCREEN,
                event = "SetFullScreen",
                args = {true, false},
                show = false,
                name_text_hold_callback = optionsutil.showValues,
            },
            {
                name = "page_margin",
                name_text = S.PAGE_MARGIN,
                toggle = {S.SMALL, S.MEDIUM, S.LARGE},
                values = {0.05, 0.10, 0.25},
                default_value = DKOPTREADER_CONFIG_PAGE_MARGIN,
                event = "MarginUpdate",
                name_text_hold_callback = optionsutil.showValues,
            },
            {
                name = "line_spacing",
                name_text = S.LINE_SPACING,
                toggle = {S.SMALL, S.MEDIUM, S.LARGE},
                values = {1.0, 1.2, 1.4},
                default_value = DKOPTREADER_CONFIG_LINE_SPACING,
                advanced = true,
                name_text_hold_callback = optionsutil.showValues,
            },
            {
                name = "max_columns",
                name_text = S.COLUMNS,
                item_icons = {
                    "resources/icons/appbar.column.one.png",
                    "resources/icons/appbar.column.two.png",
                    "resources/icons/appbar.column.three.png",
                },
                values = {1,2,3},
                default_value = DKOPTREADER_CONFIG_MAX_COLUMNS,
                enabled_func = function(configurable)
                    return optionsutil.enableIfEquals(configurable, "text_wrap", 1)
                end,
                name_text_hold_callback = optionsutil.showValues,
            },
            {
                name = "justification",
                name_text = S.TEXT_ALIGN,
                item_icons = {
                    "resources/icons/appbar.align.auto.png",
                    "resources/icons/appbar.align.left.png",
                    "resources/icons/appbar.align.center.png",
                    "resources/icons/appbar.align.right.png",
                    "resources/icons/appbar.align.justify.png",
                },
                values = {-1,0,1,2,3},
                default_value = DKOPTREADER_CONFIG_JUSTIFICATION,
                advanced = true,
                enabled_func = function(configurable)
                    return optionsutil.enableIfEquals(configurable, "text_wrap", 1)
                end,
                labels = {S.AUTO, S.LEFT, S.CENTER, S.RIGHT, S.JUSTIFY},
                name_text_hold_callback = optionsutil.showValues,
            },
        }
    },
    {
        icon = "resources/icons/appbar.text.size.large.png",
        options = {
            {
                name = "font_size",
                item_text = {"Aa","Aa","Aa","Aa","Aa","Aa","Aa","Aa"},
                item_align_center = 1.0,
                spacing = 15,
                height = 60,
                item_font_size = {24,28,32,34,36,38,42,46},
                values = {0.2, 0.4, 0.6, 0.8, 1.0, 1.2, 1.6, 2.0},
                default_value = DKOPTREADER_CONFIG_FONT_SIZE,
                event = "FontSizeUpdate",
                enabled_func = function(configurable)
                    return optionsutil.enableIfEquals(configurable, "text_wrap", 1)
                end,
            },
            {
                name = "font_fine_tune",
                name_text = S.FONTSIZE_FINE_TUNING,
                toggle = Device:isTouchDevice() and {S.DECREASE, S.INCREASE} or nil,
                item_text = not Device:isTouchDevice() and {S.DECREASE, S.INCREASE} or nil,
                values = {-0.05, 0.05},
                default_value = 0.05,
                event = "FineTuningFontSize",
                args = {-0.05, 0.05},
                alternate = false,
                enabled_func = function(configurable)
                    return optionsutil.enableIfEquals(configurable, "text_wrap", 1)
                end,
                name_text_hold_callback = function(configurable, __, prefix)
                    local opt = {
                        name = "font_size",
                        name_text = _("Font Size"),
                    }
                    optionsutil.showValues(configurable, opt, prefix)
                end
            }
        }
    },
    {
        icon = "resources/icons/appbar.grade.b.large.png",
        options = {
            {
                name = "contrast",
                name_text = S.CONTRAST,
                buttonprogress = true,
                values = {1/0.8, 1/1.0, 1/1.5, 1/2.0, 1/3.0, 1/4.0, 1/6.0, 1/9.0},
                default_pos = 2,
                default_value = DKOPTREADER_CONFIG_CONTRAST,
                event = "GammaUpdate",
                args = {0.8, 1.0, 1.5, 2.0, 3.0, 4.0, 6.0, 9.0},
                labels = {0.8, 1.0, 1.5, 2.0, 3.0, 4.0, 6.0, 9.0},
                name_text_hold_callback = optionsutil.showValues,
            }
        }
    },
    {
        icon = "resources/icons/appbar.settings.large.png",
        options = {
            {
                name = "text_wrap",
                name_text = S.REFLOW,
                toggle = {S.ON, S.OFF},
                values = {1, 0},
                default_value = DKOPTREADER_CONFIG_TEXT_WRAP,
                events = {
                    {
                        event = "RedrawCurrentPage",
                    },
                    {
                        event = "RestoreZoomMode",
                    },
                    {
                        event = "InitScrollPageStates",
                    },
                },
                name_text_hold_callback = optionsutil.showValues,
            },
            {
                name = "page_opt",
                name_text = S.DEWATERMARK,
                toggle = {S.ON, S.OFF},
                values = {1, 0},
                default_value = 0,
                name_text_hold_callback = optionsutil.showValues,
                help_text = _([[Remove watermarks from the rendered document.
This can also be used to remove some gray background or to convert a grayscale or color document to black & white and get more contrast for easier reading.]]),
            },
            {
                name="doc_language",
                name_text = S.DOC_LANG,
                toggle = DKOPTREADER_CONFIG_DOC_LANGS_TEXT,
                values = DKOPTREADER_CONFIG_DOC_LANGS_CODE,
                default_value = DKOPTREADER_CONFIG_DOC_DEFAULT_LANG_CODE,
                event = "DocLangUpdate",
                args = DKOPTREADER_CONFIG_DOC_LANGS_CODE,
                name_text_hold_callback = optionsutil.showValues,
                help_text = _([[(Used by the OCR engine.)]]),
            },
            {
                name = "word_spacing",
                name_text = S.WORD_GAP,
                toggle = {S.SMALL, S.AUTO, S.LARGE},
                values = DKOPTREADER_CONFIG_WORD_SPACINGS,
                default_value = DKOPTREADER_CONFIG_DEFAULT_WORD_SPACING,
                enabled_func = function(configurable)
                    return optionsutil.enableIfEquals(configurable, "text_wrap", 1)
                end,
                name_text_hold_callback = optionsutil.showValues,
            },
            {
                name = "writing_direction",
                name_text = S.WRITING_DIR,
                toggle = {S.LTR, S.RTL, S.TBRTL},
                values = {0, 1, 2},
                default_value = 0,
                enabled_func = function(configurable)
                    return optionsutil.enableIfEquals(configurable, "text_wrap", 1)
                end,
                name_text_hold_callback = optionsutil.showValues,
            },
            {
                name = "quality",
                name_text = S.RENDER_QUALITY,
                toggle = {S.LOW, S.DEFAULT, S.HIGH},
                values={0.5, 1.0, 1.5},
                default_value = DKOPTREADER_CONFIG_RENDER_QUALITY,
                advanced = true,
                enabled_func = function(configurable)
                    return optionsutil.enableIfEquals(configurable, "text_wrap", 1)
                end,
                name_text_hold_callback = optionsutil.showValues,
            },
            {
                name = "hw_dithering",
                name_text = S.HW_DITHERING,
                toggle = {S.ON, S.OFF},
                values = {1, 0},
                default_value = 0,
                advanced = true,
                show = Device:hasEinkScreen() and Device:canHWDither(),
                name_text_hold_callback = optionsutil.showValues,
            },
            {
                name = "forced_ocr",
                name_text = S.FORCED_OCR,
                toggle = {S.ON, S.OFF},
                values = {1, 0},
                default_value = 0,
                advanced = true,
                name_text_hold_callback = optionsutil.showValues,
            },
            {
                name = "defect_size",
                name_text = S.DEFECT_SIZE,
                toggle = {S.SMALL, S.MEDIUM, S.LARGE},
                values = {1.0, 3.0, 5.0},
                default_value = DKOPTREADER_CONFIG_DEFECT_SIZE,
                event = "DefectSizeUpdate",
                show = false,
                enabled_func = function(configurable)
                    return optionsutil.enableIfEquals(configurable, "text_wrap", 1)
                end,
                name_text_hold_callback = optionsutil.showValues,
            },
            {
                name = "auto_straighten",
                name_text = S.AUTO_STRAIGHTEN,
                toggle = {S.ZERO_DEG, S.FIVE_DEG, S.TEN_DEG},
                values = {0, 5, 10},
                default_value = DKOPTREADER_CONFIG_AUTO_STRAIGHTEN,
                show = false,
                enabled_func = function(configurable)
                    return optionsutil.enableIfEquals(configurable, "text_wrap", 1)
                end,
                name_text_hold_callback = optionsutil.showValues,
            },
            {
                name = "detect_indent",
                name_text = S.INDENTATION,
                toggle = {S.ON, S.OFF},
                values = {1, 0},
                default_value = DKOPTREADER_CONFIG_DETECT_INDENT,
                show = false,
                enabled_func = function(configurable)
                    return optionsutil.enableIfEquals(configurable, "text_wrap", 1)
                end,
                name_text_hold_callback = optionsutil.showValues,
            },
        }
    },
}

return KoptOptions
