local BD = require("ui/bidi")
local Device = require("device")
local S = require("ui/data/strings")
local optionsutil = require("ui/data/optionsutil")
local _ = require("gettext")
local Screen = Device.screen

-- The values used for Font Size are not actually font sizes, but kopt zoom levels.
local FONT_SCALE_FACTORS = {0.2, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0, 1.1, 1.3, 1.6, 2.0}
-- Font sizes used for the font size widget only
local FONT_SCALE_DISPLAY_SIZE = {12, 14, 15, 16, 17, 18, 19, 20, 22, 25, 30, 35}

-- Get font scale numbers as a table of strings
local tableOfNumbersToTableOfStrings = function(numbers)
    local t = {}
    for i, v in ipairs(numbers) do
        table.insert(t, string.format("%0.1f", v))
    end
    return t
end

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
                -- manual=0, auto=1, semi-auto=2, none=3
                -- ordered from least to max cropping done or possible
                toggle = {S.NONE, S.AUTO, S.SEMIAUTO, S.MANUAL},
                alternate = false,
                values = {3, 1, 2, 0},
                default_value = DKOPTREADER_CONFIG_TRIM_PAGE,
                enabled_func = Device.isTouchDevice,
                event = "PageCrop",
                args = {"none", "auto", "semi-auto", "manual"},
                name_text_hold_callback = optionsutil.showValues,
                help_text = _([[Allows cropping blank page margins in the original document.
This might be needed on scanned documents, that may have speckles or fingerprints in the margins, to be able to use zoom to fit content width.
- 'none' does not cut the original document margins.
- 'auto' finds content area automatically.
- 'semi-auto" finds content area automatically, inside some larger area defined manually.
- 'manual" uses the area defined manually as-is.

In 'semi-auto' and 'manual' modes, you may need to define areas once on an odd page number, and once on an even page number (these areas will then be used for all odd, or even, page numbers).]]),
            },
            {
                name = "page_margin",
                name_text = S.PAGE_MARGIN,
                toggle = {S.SMALL, S.MEDIUM, S.LARGE},
                values = {0.05, 0.10, 0.25},
                default_value = DKOPTREADER_CONFIG_PAGE_MARGIN,
                event = "MarginUpdate",
                name_text_hold_callback = optionsutil.showValues,
                help_text = _([[Set margins to be applied after page-crop and zoom modes are applied.]]),
            },
        }
    },
    {
        icon = "resources/icons/appbar.column.two.large.png",
        options = {
            {
                name = "page_scroll",
                name_text = S.VIEW_MODE,
                toggle = {S.VIEW_PAGE, S.VIEW_SCROLL},
                values = {0, 1},
                default_value = 1,
                event = "SetScrollMode",
                args = {false, true},
                name_text_hold_callback = optionsutil.showValues,
                help_text = _([[- 'page' mode shows only one page of the document at a time.
- 'continuous' mode allows you to scroll the pages like you would in a web browser.]]),
            },
            {
                name = "page_gap_height",
                name_text = S.PAGE_GAP,
                toggle = {S.NONE, S.SMALL, S.MEDIUM, S.LARGE},
                values = {0, 8, 16, 32},
                default_value = 8,
                args = {0, 8, 16, 32},
                event = "PageGapUpdate",
                enabled_func = function (configurable)
                    return optionsutil.enableIfEquals(configurable, "page_scroll", 1)
                end,
                name_text_hold_callback = optionsutil.showValues,
                help_text = _([[In continuous view mode, sets the thickness of the separator between document pages.]]),
            },
            {
                name = "full_screen",
                name_text = S.PROGRESS_BAR,
                toggle = {S.OFF, S.ON},
                values = {1, 0},
                default_value = 1,
                event = "SetFullScreen",
                args = {true, false},
                show = false, -- toggling bottom status can be done via tap
                name_text_hold_callback = optionsutil.showValues,
            },
            {
                name = "line_spacing",
                name_text = S.LINE_SPACING,
                toggle = {S.SMALL, S.MEDIUM, S.LARGE},
                values = {1.0, 1.2, 1.4},
                default_value = DKOPTREADER_CONFIG_LINE_SPACING,
                advanced = true,
                enabled_func = function(configurable)
                    -- seems to only work in reflow mode
                    return optionsutil.enableIfEquals(configurable, "text_wrap", 1)
                end,
                name_text_hold_callback = optionsutil.showValues,
                help_text = _([[In reflow mode, sets the spacing between lines.]]),
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
                help_text = _([[In reflow mode, sets the text alignment.
The first option ("auto") tries to automatically align reflowed text as it is in the original document.]]),
            },
        }
    },
    {
        icon = "resources/icons/appbar.text.size.large.png",
        options = {
            {
                name = "font_size",
                item_text = tableOfNumbersToTableOfStrings(FONT_SCALE_FACTORS),
                item_align_center = 1.0,
                spacing = 15,
                height = 60,
                item_font_size = FONT_SCALE_DISPLAY_SIZE,
                args = FONT_SCALE_FACTORS,
                values = FONT_SCALE_FACTORS,
                default_value = DKOPTREADER_CONFIG_FONT_SIZE,
                event = "FontSizeUpdate",
                enabled_func = function(configurable, document)
                    if document.is_reflowable then return true end
                    return optionsutil.enableIfEquals(configurable, "text_wrap", 1)
                end,
            },
            {
                name = "font_fine_tune",
                name_text = S.FONT_SIZE,
                toggle = Device:isTouchDevice() and {S.DECREASE, S.INCREASE} or nil,
                item_text = not Device:isTouchDevice() and {S.DECREASE, S.INCREASE} or nil,
                values = {-0.05, 0.05},
                default_value = 0.05,
                event = "FineTuningFontSize",
                args = {-0.05, 0.05},
                alternate = false,
                enabled_func = function(configurable, document)
                    if document.is_reflowable then return true end
                    return optionsutil.enableIfEquals(configurable, "text_wrap", 1)
                end,
                name_text_hold_callback = function(configurable, __, prefix)
                    local opt = {
                        name = "font_size",
                        name_text = _("Font Size"),
                        help_text = _([[In reflow mode, sets a font scaling factor that is applied to the original document font sizes.]]),
                    }
                    optionsutil.showValues(configurable, opt, prefix)
                end,
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
                help_text = _([[In reflow mode, sets the spacing between words.]]),
            },
            {
                name = "text_wrap",
                name_text = S.REFLOW,
                toggle = {S.OFF, S.ON},
                values = {0, 1},
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
                help_text = _([[Reflow mode extracts text and images from the original document, possibly discarding some formatting, and reflows it on the screen for easier reading.
Some of the other settings are only available when reflow mode is enabled.]]),
            },
        }
    },
    {
        icon = "resources/icons/appbar.grade.b.large.png",
        options = {
            {
                name = "contrast",
                name_text = S.CONTRAST,
                buttonprogress = true,
                -- See https://github.com/koreader/koreader/issues/1299#issuecomment-65183895
                -- For pdf reflowing mode (kopt_contrast):
                values = {1/0.8, 1/1.0, 1/1.5, 1/2.0, 1/4.0, 1/6.0, 1/10.0, 1/50.0},
                default_pos = 2,
                default_value = DKOPTREADER_CONFIG_CONTRAST,
                event = "GammaUpdate",
                -- For pdf non-reflowing mode (mupdf):
                args =   {0.8, 1.0, 1.5, 2.0, 4.0, 6.0, 10.0, 50.0},
                labels = {0.8, 1.0, 1.5, 2.0, 4.0, 6.0, 10.0, 50.0},
                name_text_hold_callback = optionsutil.showValues,
            },
            {
                name = "page_opt",
                name_text = S.DEWATERMARK,
                toggle = {S.OFF, S.ON},
                values = {0, 1},
                default_value = 0,
                name_text_hold_callback = optionsutil.showValues,
                help_text = _([[Remove watermarks from the rendered document.
This can also be used to remove some gray background or to convert a grayscale or color document to black & white and get more contrast for easier reading.]]),
            },
            {
                name = "hw_dithering",
                name_text = S.HW_DITHERING,
                toggle = {S.OFF, S.ON},
                values = {0, 1},
                default_value = 0,
                advanced = true,
                show = Device:hasEinkScreen() and Device:canHWDither(),
                name_text_hold_callback = optionsutil.showValues,
                help_text = _([[Enable Hardware dithering.]]),
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
                help_text = _([[In reflow mode, sets the quality of the text and image extraction processing and output.]]),
            },
        }
    },
    {
        icon = "resources/icons/appbar.settings.large.png",
        options = {
            {
                name="doc_language",
                name_text = S.DOC_LANG,
                toggle = DKOPTREADER_CONFIG_DOC_LANGS_TEXT,
                values = DKOPTREADER_CONFIG_DOC_LANGS_CODE,
                default_value = DKOPTREADER_CONFIG_DOC_DEFAULT_LANG_CODE,
                event = "DocLangUpdate",
                args = DKOPTREADER_CONFIG_DOC_LANGS_CODE,
                name_text_hold_callback = optionsutil.showValues,
                help_text = _([[Set the language to be used by the OCR engine.]]),
            },
            {
                name = "forced_ocr",
                name_text = S.FORCED_OCR,
                toggle = {S.OFF, S.ON},
                values = {0, 1},
                default_value = 0,
                advanced = true,
                name_text_hold_callback = optionsutil.showValues,
                help_text = _([[Force the use of OCR for text selection, even if the document has a text layer.]]),
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
                help_text = _([[In reflow mode, sets the original text direction. This needs to be set to RTL to correctly extract and reflow RTL languages like Arabic or Hebrew.]]),
            },
            {
                name = "defect_size",
                name_text = S.DEFECT_SIZE,
                toggle = {S.SMALL, S.MEDIUM, S.LARGE},
                values = {1.0, 3.0, 5.0},
                default_value = DKOPTREADER_CONFIG_DEFECT_SIZE,
                event = "DefectSizeUpdate",
                show = false, -- might work somehow, but larger values than 1.0 might easily eat content
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
                show = false, -- does not work (and slows rendering)
                enabled_func = function(configurable)
                    return optionsutil.enableIfEquals(configurable, "text_wrap", 1)
                end,
                name_text_hold_callback = optionsutil.showValues,
            },
            {
                name = "detect_indent",
                name_text = S.INDENTATION,
                toggle = {S.OFF, S.ON},
                values = {0, 1},
                default_value = DKOPTREADER_CONFIG_DETECT_INDENT,
                show = false, -- does not work
                enabled_func = function(configurable)
                    return optionsutil.enableIfEquals(configurable, "text_wrap", 1)
                end,
                name_text_hold_callback = optionsutil.showValues,
            },
            {
                name = "max_columns",
                name_text = S.DOCUMENT_COLUMNS,
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
                help_text = _([[In reflow mode, sets the max number of columns to try to detect in the original document.
You might need to set it to 1 column if, in a full width document, text is incorrectly detected as multiple columns because of unlucky word spacing.]]),
            },
        }
    },
}

if BD.mirroredUILayout() then
    -- The justification items {AUTO, LEFT, CENTER, RIGHT, JUSTIFY} will
    -- be mirrored - but that's not enough: we need to swap LEFT and RIGHT,
    -- so they appear in a more expected and balanced order to RTL users:
    -- {JUSTIFY, LEFT, CENTER, RIGHT, AUTO}
    local j = KoptOptions[3].options[5]
    assert(j.name == "justification")
    j.item_icons[2], j.item_icons[4] = j.item_icons[4], j.item_icons[2]
    j.values[2], j.values[4] = j.values[4], j.values[2]
    j.labels[2], j.labels[4] = j.labels[4], j.labels[2]
end

return KoptOptions
