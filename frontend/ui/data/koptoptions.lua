local BD = require("ui/bidi")
local Device = require("device")
local IsoLanguage = require("ui/data/isolanguage")
local optionsutil = require("ui/data/optionsutil")
local util = require("util")
local _ = require("gettext")
local C_ = _.pgettext
local Screen = Device.screen

-- The values used for Font Size are not actually font sizes, but kopt zoom levels.
local FONT_SCALE_FACTORS = {0.2, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0, 1.1, 1.3, 1.6, 2.0}
-- Font sizes used for the font size widget only
local FONT_SCALE_DISPLAY_SIZE = {12, 14, 15, 16, 17, 18, 19, 20, 22, 25, 30, 35}

local KOPTREADER_CONFIG_DOC_LANGS_TEXT = {}
for _, lang in ipairs(G_defaults:readSetting("DKOPTREADER_CONFIG_DOC_LANGS_CODE")) do
    local langName = IsoLanguage:getLocalizedLanguage(lang)
    if langName then
        table.insert(KOPTREADER_CONFIG_DOC_LANGS_TEXT, langName)
    else
        table.insert(KOPTREADER_CONFIG_DOC_LANGS_TEXT, lang)
    end
end

-- Get font scale numbers as a table of strings
local tableOfNumbersToTableOfStrings = function(numbers)
    local t = {}
    for i, v in ipairs(numbers) do
        table.insert(t, string.format("%0.1f", v))
    end
    return t
end

local KoptOptions = {
    prefix = "kopt",
    {
        icon = "appbar.rotation",
        options = {
            {
                name = "rotation_mode",
                name_text = _("Rotation"),
                item_icons_func = function()
                    local mode = Screen:getRotationMode()
                    if mode == Screen.DEVICE_ROTATED_UPRIGHT then
                        -- P, 0UR
                        return {
                            "rotation.P.90CCW",
                            "rotation.P.0UR",
                            "rotation.P.90CW",
                            "rotation.P.180UD",
                        }
                    elseif mode == Screen.DEVICE_ROTATED_UPSIDE_DOWN then
                        -- P, 180UD
                        return {
                            "rotation.P.90CW",
                            "rotation.P.180UD",
                            "rotation.P.90CCW",
                            "rotation.P.0UR",
                        }
                    elseif mode == Screen.DEVICE_ROTATED_CLOCKWISE then
                        -- L, 90CW
                        return {
                            "rotation.L.90CCW",
                            "rotation.L.0UR",
                            "rotation.L.90CW",
                            "rotation.L.180UD",
                        }
                    else
                        -- L, 90CCW
                        return {
                            "rotation.L.90CW",
                            "rotation.L.180UD",
                            "rotation.L.90CCW",
                            "rotation.L.0UR",
                        }
                    end
                end,
                -- For Dispatcher & onMakeDefault's sake
                labels = optionsutil.rotation_labels,
                alternate = false,
                values = optionsutil.rotation_modes,
                default_value = Screen.DEVICE_ROTATED_UPRIGHT,
                args = optionsutil.rotation_modes,
                current_func = function() return Screen:getRotationMode() end,
                event = "SetRotationMode",
                name_text_hold_callback = optionsutil.showValues,
            }
        }
    },
    {
        icon = "appbar.crop",
        options = {
            {
                name = "trim_page",
                name_text = _("Page Crop"),
                -- manual=0, auto=1, semi-auto=2, none=3
                -- ordered from least to max cropping done or possible
                toggle = {C_("Page crop", "none"), C_("Page crop", "auto"), C_("Page crop", "semi-auto"), C_("Page crop", "manual")},
                alternate = false,
                values = {3, 1, 2, 0},
                default_value = G_defaults:readSetting("DKOPTREADER_CONFIG_TRIM_PAGE"),
                enabled_func = function()
                    return Device:isTouchDevice() or Device:hasDPad()
                end,
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
                name_text = _("Margin"),
                buttonprogress = true,
                values = {0.05, 0.10, 0.25, 0.40, 0.55, 0.70, 0.85, 1.00},
                default_value = G_defaults:readSetting("DKOPTREADER_CONFIG_PAGE_MARGIN"),
                event = "MarginUpdate",
                args = {0.05, 0.10, 0.25, 0.40, 0.55, 0.70, 0.85, 1.00},
                name_text_hold_callback = optionsutil.showValues,
                help_text = _([[Set margins to be applied after page-crop and zoom modes are applied.]]),
                more_options = true,
                more_options_param = {
                    value_step = 0.01, value_hold_step = 0.10,
                    value_min = 0, value_max = 1.50,
                    precision = "%.2f",
                },
            },
            {
                name = "auto_straighten",
                name_text = _("Auto Straighten"),
                toggle = {_("0°"), _("5°"), _("10°"), _("15°"), _("25°")},
                values = {0, 5, 10, 15, 25},
                event = "DummyEvent",
                args = {0, 5, 10, 15, 25},
                more_options = true,
                more_options_param = {
                    unit = "°",
                },
                default_value = G_defaults:readSetting("DKOPTREADER_CONFIG_AUTO_STRAIGHTEN"),
                name_text_hold_callback = optionsutil.showValues,
                help_text = _([[Attempt to automatically straighten tilted source pages.
Will rotate up to specified value.]]),
            },
        }
    },
    {
        icon = "appbar.pagefit",
        options = {
            {
                name = "zoom_overlap_h",
                name_text = _("Horizontal overlap"),
                enabled_func = function(configurable)
                    return optionsutil.enableIfEquals(configurable, "text_wrap", 0)
                end,
                buttonprogress = true,
                more_options = true,
                values = {0, 12, 24, 36, 48, 60, 72, 84},
                default_pos = 4,
                default_value = 36,
                show_func = function(configurable)
                    -- FIXME(ogkevin): this, for some reason, can be nil after zoom in and out
                    return configurable.zoom_mode_genus and configurable.zoom_mode_genus < 3
                end,
                event = "DefineZoom",
                args =   {0, 12, 24, 36, 48, 60, 72, 84},
                labels = {0, 12, 24, 36, 48, 60, 72, 84},
                hide_on_apply = true,
                name_text_hold_callback = optionsutil.showValues,
                help_text = _([[Set horizontal zoom overlap (between columns).]]),
            },
            {
                name = "zoom_overlap_v",
                name_text = _("Vertical overlap"),
                enabled_func = function(configurable)
                    return optionsutil.enableIfEquals(configurable, "text_wrap", 0)
                end,
                buttonprogress = true,
                more_options = true,
                values = {0, 12, 24, 36, 48, 60, 72, 84},
                default_pos = 4,
                default_value = 36,
                show_func = function(configurable)
                    return configurable.zoom_mode_genus and configurable.zoom_mode_genus < 3
                end,
                event = "DefineZoom",
                args =   {0, 12, 24, 36, 48, 60, 72, 84},
                labels = {0, 12, 24, 36, 48, 60, 72, 84},
                hide_on_apply = true,
                name_text_hold_callback = optionsutil.showValues,
                help_text = _([[Set vertical zoom overlap (between lines).]]),
            },
            {
                name = "zoom_mode_type",
                name_text = _("Fit"),
                enabled_func = function(configurable)
                    return optionsutil.enableIfEquals(configurable, "text_wrap", 0) and
                        configurable.page_mode ~= 2
                end,
                toggle = { _("full"), _("width"), _("height") },
                alternate = false,
                values = { 2, 1, 0 },
                default_value = 1,
                show_func = function(configurable)
                    return configurable.zoom_mode_genus and configurable.zoom_mode_genus > 2
                end,
                event = "DefineZoom",
                args = { "full", "width", "height" },
                name_text_hold_callback = optionsutil.showValues,
                help_text = _([[Set how the page should be resized to fit the screen.]]),
            },
            {
                name = "zoom_range_number",
                name_text_func = function(configurable)
                    return ({_("Rows"), _("Columns")})[configurable.zoom_mode_genus]
                end,
                name_text_true_values = true,
                enabled_func = function(configurable)
                    return optionsutil.enableIfEquals(configurable, "text_wrap", 0)
                end,
                show_true_value_func = function(str)
                    return string.format("%.1f", str)
                end,
                toggle =  {"1", "2", "3", "4", "5", "6", "7", "8"},
                more_options = true,
                more_options_param = {
                    value_step = 0.1, value_hold_step = 1,
                    value_min = 0.1, value_max = 8,
                    precision = "%.1f",
                },
                values = {1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0},
                default_pos = 2,
                default_value = 2,
                show_func = function(configurable)
                    return configurable.zoom_mode_genus == 1 or configurable.zoom_mode_genus == 2
                end,
                event = "DefineZoom",
                args =   {1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0},
                hide_on_apply = true,
                name_text_hold_callback = optionsutil.showValues,
                help_text = _([[Set the number of columns or rows into which to split the page.]]),
            },
            {
                name = "zoom_factor",
                name_text = _("Zoom factor"),
                name_text_true_values = true,
                enabled_func = function(configurable)
                    return optionsutil.enableIfEquals(configurable, "text_wrap", 0)
                end,
                show_true_value_func = function(str)
                    return string.format("%.1f", str)
                end,
                toggle =  {"0.7", "1", "1.5", "2", "3", "5", "10", "20"},
                more_options = true,
                more_options_param = {
                    value_step = 0.1, value_hold_step = 1,
                    value_min = 0.1, value_max = 20,
                    precision = "%.1f",
                },
                values = {0.7, 1.0, 1.5, 2.0, 3.0, 5.0, 10.0, 20.0},
                default_pos = 3,
                default_value = 1.5,
                show_func = function(configurable)
                    return configurable.zoom_mode_genus == 0
                end,
                event = "DefineZoom",
                args = {0.7, 1.0, 1.5, 2.0, 3.0, 5.0, 10.0, 20.0},
                hide_on_apply = true,
                name_text_hold_callback = optionsutil.showValues,
            },
            {
                name = "zoom_mode_genus",
                name_text = _("Zoom to"),
                enabled_func = function(configurable)
                    return optionsutil.enableIfEquals(configurable, "text_wrap", 0)
                        and configurable.page_mode ~= 2
                end,
                -- toggle = {_("page"), _("content"), _("columns"), _("rows"), _("manual")},
                item_icons = {
                    "zoom.page",
                    "zoom.content",
                    "zoom.column",
                    "zoom.row",
                    "zoom.manual",
                },
                alternate = false,
                values = { 4, 3, 2, 1, 0 },
                labels = { _("page"), _("content"), _("columns"), _("rows"), _("manual") },
                default_value = 4,
                event = "DefineZoom",
                args = { "page", "content", "columns", "rows", "manual" },
                name_text_hold_callback = optionsutil.showValues,
            },
            {
                name = "zoom_direction",
                name_text = _("Direction"),
                enabled_func = function(configurable)
                    return optionsutil.enableIfEquals(configurable, "text_wrap", 0) and configurable.zoom_mode_genus < 3
                end,
                item_icons = {
                    "direction.LRTB",
                    "direction.TBLR",
                    "direction.LRBT",
                    "direction.BTLR",
                    "direction.BTRL",
                    "direction.RLBT",
                    "direction.TBRL",
                    "direction.RLTB",
                },
                alternate = false,
                values = {7, 6, 5, 4, 3, 2, 1, 0},
                labels = {
                    _("Left to Right, Top to Bottom"),
                    _("Top to Bottom, Left to Right"),
                    _("Left to Right, Bottom to Top"),
                    _("Bottom to Top, Left to Right"),
                    _("Bottom to Top, Right to Left"),
                    _("Right to Left, Bottom to Top"),
                    _("Top to Bottom, Right to Left"),
                    _("Right to Left, Top to Bottom"),
                },
                default_value = 7,
                event = "DefineZoom",
                args = {7, 6, 5, 4, 3, 2, 1, 0},
                hide_on_apply = true,
                name_text_hold_callback = optionsutil.showValues,
                help_text = _([[Set how paging and swiping forward should move the view on the page:
left to right or reverse, top to bottom or reverse.]]),
            },
        }
    },
    {
        icon = "appbar.pageview",
        options = {
            {
                name = "page_scroll",
                name_text = _("View Mode"),
                toggle = {_("page"), _("continuous")},
                values = {0, 1},
                default_value = 1,
                event = "SetScrollMode",
                args = {false, true},
                name_text_hold_callback = optionsutil.showValues,
                help_text = _([[- 'page' mode shows only one page of the document at a time.
- 'continuous' mode allows you to scroll the pages like you would in a web browser.]]),
            },
            {
                name = "page_mode",
                name_text = _("Page Mode"),
                toggle = { _("single"), _("dual") },
                values = { 1, 2 },
                default_value = 0,
                event = "SetPageMode",
                args = { 1, 2 },
                enabled_func = function(configurable, document)
                    local ext = util.getFileNameSuffix(document.file)

                    return optionsutil.enableIfEquals(configurable, "page_scroll", 0) and
                        ext == "cbz" and
                        Screen:getScreenMode() == "landscape"
                end,
                name_text_hold_callback = optionsutil.showValues,
                help_text = _([[- 'single' mode shows only one page of the document at a time.
- 'dual' mode shows two pages at a time

This option only works when the device is in landscape mode!
]]),
            },
            {
                name = "page_gap_height",
                name_text = _("Page Gap"),
                buttonprogress = true,
                values = {0, 2, 4, 8, 16, 32, 64},
                default_pos = 4,
                default_value = 8,
                event = "PageGapUpdate",
                args = {0, 2, 4, 8, 16, 32, 64},
                enabled_func = function (configurable)
                    return optionsutil.enableIfEquals(configurable, "page_scroll", 1)
                end,
                name_text_hold_callback = optionsutil.showValues,
                name_text_unit = true,
                help_text = _([[In continuous view mode, sets the thickness of the separator between document pages.]]),
                more_options = true,
                more_options_param = {
                    value_step = 1, value_hold_step = 10,
                    value_min = 0, value_max = 256,
                    precision = "%.1f",
                },
            },
            {
                name = "line_spacing",
                name_text = _("Line Spacing"),
                toggle = {C_("Line spacing", "small"), C_("Line spacing", "medium"), C_("Line spacing", "large")},
                values = {1.0, 1.2, 1.4},
                default_value = G_defaults:readSetting("DKOPTREADER_CONFIG_LINE_SPACING"),
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
                --- @translators Text alignment. Options given as icons: left, right, center, justify.
                name_text = _("Alignment"),
                item_icons = {
                    "align.auto",
                    "align.left",
                    "align.center",
                    "align.right",
                    "align.justify",
                },
                values = {-1, 0, 1, 2, 3},
                default_value = G_defaults:readSetting("DKOPTREADER_CONFIG_JUSTIFICATION"),
                advanced = true,
                enabled_func = function(configurable)
                    return optionsutil.enableIfEquals(configurable, "text_wrap", 1)
                end,
                labels = {
                    C_("Alignment", "auto"),
                    C_("Alignment", "left"),
                    C_("Alignment", "center"),
                    C_("Alignment", "right"),
                    C_("Alignment", "justify"),
                },
                name_text_hold_callback = optionsutil.showValues,
                help_text = _([[In reflow mode, sets the text alignment.
The first option ("auto") tries to automatically align reflowed text as it is in the original document.]]),
            },
        }
    },
    {
        icon = "appbar.textsize",
        options = {
            {
                name = "font_size",
                item_text = tableOfNumbersToTableOfStrings(FONT_SCALE_FACTORS),
                item_align_center = 1.0,
                spacing = 15,
                item_font_size = FONT_SCALE_DISPLAY_SIZE,
                args = FONT_SCALE_FACTORS,
                values = FONT_SCALE_FACTORS,
                default_value = G_defaults:readSetting("DKOPTREADER_CONFIG_FONT_SIZE"),
                event = "FontSizeUpdate",
                enabled_func = function(configurable)
                    return optionsutil.enableIfEquals(configurable, "text_wrap", 1)
                end,
            },
            {
                name = "font_fine_tune",
                name_text = _("Font Size"),
                toggle = Device:isTouchDevice() and {_("decrease"), _("increase")} or nil,
                item_text = not Device:isTouchDevice() and {_("decrease"), _("increase")} or nil,
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
                        help_text = _([[In reflow mode, sets a font scaling factor that is applied to the original document font sizes.]]),
                    }
                    optionsutil.showValues(configurable, opt, prefix)
                end,
            },
            {
                name = "word_spacing",
                name_text = _("Word Gap"),
                toggle = {C_("Word gap", "small"), C_("Word gap", "auto"), C_("Word gap", "large")},
                values = G_defaults:readSetting("DKOPTREADER_CONFIG_WORD_SPACINGS"),
                default_value = G_defaults:readSetting("DKOPTREADER_CONFIG_DEFAULT_WORD_SPACING"),
                enabled_func = function(configurable)
                    return optionsutil.enableIfEquals(configurable, "text_wrap", 1)
                end,
                name_text_hold_callback = optionsutil.showValues,
                help_text = _([[In reflow mode, sets the spacing between words.]]),
            },
            {
                name = "text_wrap",
                --- @translators Reflow text.
                name_text = _("Reflow"),
                toggle = {_("off"), _("on")},
                values = {0, 1},
                default_value = G_defaults:readSetting("DKOPTREADER_CONFIG_TEXT_WRAP"),
                event = "ReflowUpdated",
                name_text_hold_callback = optionsutil.showValues,
                help_text = _([[Reflow mode extracts text and images from the original document, possibly discarding some formatting, and reflows it on the screen for easier reading.
Some of the other settings are only available when reflow mode is enabled.]]),
            },
        }
    },
    {
        icon = "appbar.contrast",
        options = {
            {
                name = "contrast",
                name_text = _("Contrast"),
                buttonprogress = true,
                -- See https://github.com/koreader/koreader/issues/1299#issuecomment-65183895
                -- For pdf reflowing mode (kopt_contrast):
                values = {0.8, 1.0, 1.5, 2.0, 4.0, 6.0, 10.0, 50.0},
                default_pos = 2,
                default_value = G_defaults:readSetting("DKOPTREADER_CONFIG_CONTRAST"),
                event = "GammaUpdate",
                -- For pdf non-reflowing mode (mupdf):
                args =   {0.8, 1.0, 1.5, 2.0, 4.0, 6.0, 10.0, 50.0},
                labels = {0.8, 1.0, 1.5, 2.0, 4.0, 6.0, 10.0, 50.0},
                name_text_hold_callback = optionsutil.showValues,
                more_options = true,
                more_options_param = {
                    value_step = 0.1, value_hold_step = 1,
                    value_min = 0.8, value_max = 50,
                    precision = "%.1f",
                },
            },
            {
                name = "page_opt",
                name_text = _("Dewatermark"),
                toggle = {_("off"), _("on")},
                values = {0, 1},
                default_value = 0,
                name_text_hold_callback = optionsutil.showValues,
                help_text = _([[Remove watermarks from the rendered document.
This can also be used to remove some gray background or to convert a grayscale or color document to black & white and get more contrast for easier reading.]]),
            },
            {
                name = "hw_dithering",
                name_text = _("Dithering"),
                toggle = {_("off"), _("on")},
                values = {0, 1},
                default_value = 0,
                advanced = true,
                event = "HWDitheringUpdate",
                args = {false, true},
                show = Device:hasEinkScreen() and Device:canHWDither(),
                name_text_hold_callback = optionsutil.showValues,
                help_text = _([[Enable hardware dithering.]]),
            },
            {
                name = "sw_dithering",
                name_text = _("Dithering"),
                toggle = {_("off"), _("on")},
                values = {0, 1},
                default_value = 0,
                advanced = true,
                event = "SWDitheringUpdate",
                args = {false, true},
                show = Device:hasEinkScreen() and not Device:canHWDither() and Device.screen.fb_bpp == 8,
                name_text_hold_callback = optionsutil.showValues,
                help_text = _([[Enable software dithering.]]),
            },
            {
                name = "quality",
                name_text = C_("Quality", "Render Quality"),
                toggle = {C_("Quality", "low"), C_("Quality", "default"), C_("Quality", "high")},
                values={0.5, 1.0, 1.5},
                default_value = G_defaults:readSetting("DKOPTREADER_CONFIG_RENDER_QUALITY"),
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
        icon = "appbar.settings",
        options = {
            {
                name = "doc_language",
                name_text = _("Document Language"),
                toggle = KOPTREADER_CONFIG_DOC_LANGS_TEXT,
                values = G_defaults:readSetting("DKOPTREADER_CONFIG_DOC_LANGS_CODE"),
                default_value = G_defaults:readSetting("DKOPTREADER_CONFIG_DOC_DEFAULT_LANG_CODE"),
                event = "DocLangUpdate",
                args = G_defaults:readSetting("DKOPTREADER_CONFIG_DOC_LANGS_CODE"),
                name_text_hold_callback = optionsutil.showValues,
                help_text = _([[Set the language to be used by the OCR engine.]]),
            },
            {
                name = "forced_ocr",
                --- @translators If OCR is unclear, please see https://en.wikipedia.org/wiki/Optical_character_recognition
                name_text = _("Forced OCR"),
                toggle = {_("off"), _("on")},
                values = {0, 1},
                default_value = 0,
                advanced = true,
                name_text_hold_callback = optionsutil.showValues,
                help_text = _([[Force the use of OCR for text selection, even if the document has a text layer.]]),
            },
            {
                name = "writing_direction",
                name_text = _("Writing Direction"),
                enabled_func = function(configurable)
                    return optionsutil.enableIfEquals(configurable, "text_wrap", 1)
                end,
                toggle = {
                    --- @translators LTR is left to right, which is the regular European writing direction.
                    _("LTR"),
                    --- @translators RTL is right to left, which is the regular writing direction in languages like Hebrew, Arabic, Persian and Urdu.
                    _("RTL"),
                    --- @translators TBRTL is top-to-bottom-right-to-left, which is a traditional Chinese/Japanese writing direction.
                    _("TBRTL"),
                },
                values = {0, 1, 2},
                default_value = 0,
                name_text_hold_callback = optionsutil.showValues,
                help_text = _([[In reflow mode, sets the original text direction. This needs to be set to RTL to correctly extract and reflow RTL languages like Arabic or Hebrew.]]),
            },
            {
                name = "defect_size",
                --- @translators The maximum size of a dust or ink speckle to be ignored instead of being considered a character.
                name_text = _("Reflow Speckle Ignore Size"),
                toggle = {_("small"), _("medium"), _("large")},
                values = {1.0, 3.0, 5.0},
                default_value = G_defaults:readSetting("DKOPTREADER_CONFIG_DEFECT_SIZE"),
                event = "DefectSizeUpdate",
                show = false, -- might work somehow, but larger values than 1.0 might easily eat content
                enabled_func = function(configurable)
                    return optionsutil.enableIfEquals(configurable, "text_wrap", 1)
                end,
                name_text_hold_callback = optionsutil.showValues,
            },
            {
                name = "detect_indent",
                name_text = _("Indentation"),
                toggle = {_("off"), _("on")},
                values = {0, 1},
                default_value = G_defaults:readSetting("DKOPTREADER_CONFIG_DETECT_INDENT"),
                show = false, -- does not work
                enabled_func = function(configurable)
                    return optionsutil.enableIfEquals(configurable, "text_wrap", 1)
                end,
                name_text_hold_callback = optionsutil.showValues,
            },
            {
                name = "max_columns",
                name_text = _("Document Columns"),
                item_icons = {
                    "column.one",
                    "column.two",
                    "column.three",
                },
                values = {1, 2, 3},
                default_value = G_defaults:readSetting("DKOPTREADER_CONFIG_MAX_COLUMNS"),
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
    for _, tab in ipairs(KoptOptions) do
        for _, option in ipairs(tab.options) do
            if option.name == "zoom_direction" then
                -- The zoom direction items will be mirrored, but we want them to
                -- stay as is, as the RTL directions are at the end of the arrays.
                -- By reverting the mirroring, RTL directions will be on the right,
                -- so, at the start of the options for a RTL reader.
                util.arrayReverse(option.item_icons)
                util.arrayReverse(option.values)
                util.arrayReverse(option.args)
                option.default_value = 0
            elseif option.name == "justification" then
                -- The justification items {AUTO, LEFT, CENTER, RIGHT, JUSTIFY} will
                -- be mirrored - but that's not enough: we need to swap LEFT and RIGHT,
                -- so they appear in a more expected and balanced order to RTL users:
                -- {JUSTIFY, LEFT, CENTER, RIGHT, AUTO}
                option.item_icons[2], option.item_icons[4] = option.item_icons[4], option.item_icons[2]
                option.values[2], option.values[4] = option.values[4], option.values[2]
                option.labels[2], option.labels[4] = option.labels[4], option.labels[2]
            end
        end
    end
end

return KoptOptions
