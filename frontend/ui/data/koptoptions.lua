local Screen = require("device").screen
local S = require("ui/data/strings")

local _ = require("gettext")

local KoptOptions = {
    prefix = 'kopt',
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
                event = "SetScreenMode",
            }
        }
    },
    {
        icon = "resources/icons/appbar.crop.large.png",
        options = {
            {
                name = "trim_page",
                name_text = S.PAGE_CROP,
                width = 225,
                toggle = {S.MANUAL, S.AUTO, S.SEMIAUTO},
                alternate = false,
                values = {0, 1, 2},
                default_value = DKOPTREADER_CONFIG_TRIM_PAGE,
                event = "PageCrop",
                args = {"manual", "auto", "semi-auto"},
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
                event = "ToggleScrollMode",
                args = {true, false},
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
            },
            {
                name = "page_margin",
                name_text = S.PAGE_MARGIN,
                toggle = {S.SMALL, S.MEDIUM, S.LARGE},
                values = {0.05, 0.10, 0.15},
                default_value = DKOPTREADER_CONFIG_PAGE_MARGIN,
                event = "MarginUpdate",
            },
            {
                name = "line_spacing",
                name_text = S.LINE_SPACING,
                toggle = {S.SMALL, S.MEDIUM, S.LARGE},
                values = {1.0, 1.2, 1.4},
                default_value = DKOPTREADER_CONFIG_LINE_SPACING,
                advanced = true,
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
            },
            {
                name = "font_fine_tune",
                name_text = S.FONTSIZE_FINE_TUNING,
                toggle = {S.DECREASE, S.INCREASE},
                values = {-0.05, 0.05},
                default_value = 0.05,
                event = "FineTuningFontSize",
                args = {-0.05, 0.05},
                alternate = false,
                height = 60,
            }
        }
    },
    {
        icon = "resources/icons/appbar.grade.b.large.png",
        options = {
            {
                name = "contrast",
                name_text = S.CONTRAST,
                name_align_right = 0.25,
                item_text = {S.LIGHTER, S.DEFAULT, S.DARKER, S.DARKEST},
                item_font_size = 18,
                item_align_center = 0.7,
                values = {1.5, 1.0, 0.5, 0.2},
                default_value = DKOPTREADER_CONFIG_CONTRAST,
                event = "GammaUpdate",
                args = {0.8, 1.0, 2.0, 4.0},
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
                }
            },
            {
                name = "page_opt",
                name_text = S.DEWATERMARK,
                toggle = {S.ON, S.OFF},
                values = {1, 0},
                default_value = 0,
            },
            {
                name="doc_language",
                name_text = S.DOC_LANG,
                toggle = DKOPTREADER_CONFIG_DOC_LANGS_TEXT,
                values = DKOPTREADER_CONFIG_DOC_LANGS_CODE,
                default_value = DKOPTREADER_CONFIG_DOC_DEFAULT_LANG_CODE,
                event = "DocLangUpdate",
                args = DKOPTREADER_CONFIG_DOC_LANGS_CODE,
            },
            {
                name = "word_spacing",
                name_text = S.WORD_GAP,
                toggle = {S.SMALL, S.AUTO, S.LARGE},
                values = DKOPTREADER_CONFIG_WORD_SPACINGS,
                default_value = DKOPTREADER_CONFIG_DEFAULT_WORD_SPACING,
            },
            {
                name = "writing_direction",
                name_text = S.WRITING_DIR,
                toggle = {S.LTR, S.RTL, S.TBRTL},
                values = {0, 1, 2},
                default_value = 0,
            },
            {
                name = "quality",
                name_text = S.RENDER_QUALITY,
                toggle = {S.LOW, S.DEFAULT, S.HIGH},
                values={0.5, 1.0, 1.5},
                default_value = DKOPTREADER_CONFIG_RENDER_QUALITY,
                advanced = true,
            },
            {
                name = "forced_ocr",
                name_text = S.FORCED_OCR,
                toggle = {S.ON, S.OFF},
                values = {1, 0},
                default_value = 0,
                advanced = true,
            },
            {
                name = "defect_size",
                name_text = S.DEFECT_SIZE,
                toggle = {S.SMALL, S.MEDIUM, S.LARGE},
                values = {1.0, 3.0, 5.0},
                default_value = DKOPTREADER_CONFIG_DEFECT_SIZE,
                event = "DefectSizeUpdate",
                show = false,
            },
            {
                name = "auto_straighten",
                name_text = S.AUTO_STRAIGHTEN,
                toggle = {S.ZERO_DEG, S.FIVE_DEG, S.TEN_DEG},
                values = {0, 5, 10},
                default_value = DKOPTREADER_CONFIG_AUTO_STRAIGHTEN,
                show = false,
            },
            {
                name = "detect_indent",
                name_text = S.INDENTATION,
                toggle = {S.ON, S.OFF},
                values = {1, 0},
                default_value = DKOPTREADER_CONFIG_DETECT_INDENT,
                show = false,
            },
        }
    },
}

return KoptOptions
