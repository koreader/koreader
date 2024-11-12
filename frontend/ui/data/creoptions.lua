local Device = require("device")
local Screen = Device.screen
local ffiUtil = require("ffi/util")
local optionsutil = require("ui/data/optionsutil")
local _ = require("gettext")
local C_ = _.pgettext
local T = ffiUtil.template

-- Get font size numbers as a table of strings
local tableOfNumbersToTableOfStrings = function(numbers)
    local t = {}
    for i, v in ipairs(numbers) do
        -- We turn 17.5 into 17<sup>5</sup>
        table.insert(t, tostring(v%1==0 and v or (v-v%1).."⁵"))
    end
    return t
end

-- OS/2 weight classes map
-- c.f., https://docs.microsoft.com/en-us/typography/opentype/spec/os2#usweightclass
local usWeightClass = {
    [100] = C_("Font weight class", "Thin"),
    [200] = C_("Font weight class", "Extra-light"),
    [300] = C_("Font weight class", "Light"),
    [400] = C_("Font weight class", "Regular"),
    [500] = C_("Font weight class", "Medium"),
    [600] = C_("Font weight class", "Semi-bold"),
    [700] = C_("Font weight class", "Bold"),
    [800] = C_("Font weight class", "Extra-bold"),
    [900] = C_("Font weight class", "Black"),
}

local function weightClassToString(weight)
    if usWeightClass[weight] then
        return T(_("%1 (%2)"), usWeightClass[weight], weight)
    else
        return tostring(weight)
    end
end

local function prettifyCreWeights(t)
    local p = {}
    for __, v in ipairs(t) do
        table.insert(p, weightClassToString(v))
    end
    return p
end

local CreOptions = {
    prefix = "copt",
    {
        icon = "appbar.rotation",
        options = {
            {   -- ReaderView
                name = "rotation_mode",
                name_text = _("Rotation"),
                item_icons_func = function()
                    if Screen:getRotationMode() == Screen.DEVICE_ROTATED_UPRIGHT then
                        -- P, 0UR
                        return {
                            "rotation.P.90CCW",
                            "rotation.P.0UR",
                            "rotation.P.90CW",
                            "rotation.P.180UD",
                        }
                    elseif Screen:getRotationMode() == Screen.DEVICE_ROTATED_UPSIDE_DOWN then
                        -- P, 180UD
                        return {
                            "rotation.P.90CW",
                            "rotation.P.180UD",
                            "rotation.P.90CCW",
                            "rotation.P.0UR",
                        }
                    elseif Screen:getRotationMode() == Screen.DEVICE_ROTATED_CLOCKWISE then
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
            },
            {   -- ReaderRolling
                name = "visible_pages",
                name_text = _("Two Columns"),
                toggle = {_("off"), _("on")},
                values = {1, 2},
                default_value = 1,
                args = {1, 2},
                event = "SetVisiblePages",
                --[[ Commented out, to have it also available in portrait mode
                current_func = function()
                    -- If not in landscape mode, shows "1" as selected
                    if Screen:getScreenMode() ~= "landscape" then
                        return 1
                    end
                    -- if we return nil, ConfigDialog will pick the one from the
                    -- configurable as if we hadn't provided this 'current_func'
                end,
                ]]--
                enabled_func = function(configurable)
                    return optionsutil.enableIfEquals(configurable, "view_mode", 0) -- "page" mode
                        -- and Screen:getScreenMode() == "landscape"
                end,
                name_text_hold_callback = optionsutil.showValues,
                help_text = _([[Render the document on half the screen width and display two pages at once with a single page number. This makes it look like two columns.
This is disabled in scroll mode. Switching from page mode with two columns to scroll mode will cause the document to be re-rendered.]]),
            },
        }
    },
    {
        icon = "appbar.crop",
        options = {
            {   -- ReaderTypeset
                name = "h_page_margins",
                name_text = _("L/R Margins"),
                buttonprogress = true,
                values = {
                    G_defaults:readSetting("DCREREADER_CONFIG_H_MARGIN_SIZES_SMALL"),
                    G_defaults:readSetting("DCREREADER_CONFIG_H_MARGIN_SIZES_MEDIUM"),
                    G_defaults:readSetting("DCREREADER_CONFIG_H_MARGIN_SIZES_LARGE"),
                    G_defaults:readSetting("DCREREADER_CONFIG_H_MARGIN_SIZES_X_LARGE"),
                    G_defaults:readSetting("DCREREADER_CONFIG_H_MARGIN_SIZES_XX_LARGE"),
                    G_defaults:readSetting("DCREREADER_CONFIG_H_MARGIN_SIZES_XXX_LARGE"),
                    G_defaults:readSetting("DCREREADER_CONFIG_H_MARGIN_SIZES_HUGE"),
                    G_defaults:readSetting("DCREREADER_CONFIG_H_MARGIN_SIZES_X_HUGE"),
                    G_defaults:readSetting("DCREREADER_CONFIG_H_MARGIN_SIZES_XX_HUGE"),
                },
                default_pos = 2,
                default_value = G_defaults:readSetting("DCREREADER_CONFIG_H_MARGIN_SIZES_MEDIUM"),
                event = "SetPageHorizMargins",
                args = {
                    G_defaults:readSetting("DCREREADER_CONFIG_H_MARGIN_SIZES_SMALL"),
                    G_defaults:readSetting("DCREREADER_CONFIG_H_MARGIN_SIZES_MEDIUM"),
                    G_defaults:readSetting("DCREREADER_CONFIG_H_MARGIN_SIZES_LARGE"),
                    G_defaults:readSetting("DCREREADER_CONFIG_H_MARGIN_SIZES_X_LARGE"),
                    G_defaults:readSetting("DCREREADER_CONFIG_H_MARGIN_SIZES_XX_LARGE"),
                    G_defaults:readSetting("DCREREADER_CONFIG_H_MARGIN_SIZES_XXX_LARGE"),
                    G_defaults:readSetting("DCREREADER_CONFIG_H_MARGIN_SIZES_HUGE"),
                    G_defaults:readSetting("DCREREADER_CONFIG_H_MARGIN_SIZES_X_HUGE"),
                    G_defaults:readSetting("DCREREADER_CONFIG_H_MARGIN_SIZES_XX_HUGE"),
                },
                hide_on_apply = true,
                name_text_hold_callback = optionsutil.showValuesHMargins,
                more_options = true,
                more_options_param = {
                    name_text = _("Left/Right Margins"),
                    widget_width_factor = 0.6,
                    left_min = 0,
                    left_max = 140,
                    left_step = 1,
                    left_hold_step = 5,
                    right_min = 0,
                    right_max = 140,
                    right_step = 1,
                    right_hold_step = 5,
                },
            },
            {   -- ReaderTypeset
                name = "sync_t_b_page_margins",
                name_text = _("Sync T/B Margins"),
                toggle = {_("off"), _("on")},
                values = {0, 1},
                default_value = 0,
                event = "SyncPageTopBottomMargins",
                args = {false, true},
                hide_on_apply = true,
                name_text_hold_callback = optionsutil.showValues,
                help_text = _([[Keep top and bottom margins synchronized.
- 'off' allows different top and bottom margins.
- 'on' keeps top and bottom margins locked, ensuring text is vertically centered in the page.

In the top menu → Settings → Status bar, you can choose whether the bottom margin applies from the bottom of the screen, or from above the status bar.]]),
            },
            {   -- ReaderTypeset
                name = "t_page_margin",
                name_text = _("Top Margin"),
                buttonprogress = true,
                values = {
                    G_defaults:readSetting("DCREREADER_CONFIG_T_MARGIN_SIZES_SMALL"),
                    G_defaults:readSetting("DCREREADER_CONFIG_T_MARGIN_SIZES_MEDIUM"),
                    G_defaults:readSetting("DCREREADER_CONFIG_T_MARGIN_SIZES_LARGE"),
                    G_defaults:readSetting("DCREREADER_CONFIG_T_MARGIN_SIZES_X_LARGE"),
                    G_defaults:readSetting("DCREREADER_CONFIG_T_MARGIN_SIZES_XX_LARGE"),
                    G_defaults:readSetting("DCREREADER_CONFIG_T_MARGIN_SIZES_XXX_LARGE"),
                    G_defaults:readSetting("DCREREADER_CONFIG_T_MARGIN_SIZES_HUGE"),
                    G_defaults:readSetting("DCREREADER_CONFIG_T_MARGIN_SIZES_X_HUGE"),
                    G_defaults:readSetting("DCREREADER_CONFIG_T_MARGIN_SIZES_XX_HUGE"),
                },
                default_pos = 3,
                default_value = G_defaults:readSetting("DCREREADER_CONFIG_T_MARGIN_SIZES_LARGE"),
                event = "SetPageTopMargin",
                args = {
                    G_defaults:readSetting("DCREREADER_CONFIG_T_MARGIN_SIZES_SMALL"),
                    G_defaults:readSetting("DCREREADER_CONFIG_T_MARGIN_SIZES_MEDIUM"),
                    G_defaults:readSetting("DCREREADER_CONFIG_T_MARGIN_SIZES_LARGE"),
                    G_defaults:readSetting("DCREREADER_CONFIG_T_MARGIN_SIZES_X_LARGE"),
                    G_defaults:readSetting("DCREREADER_CONFIG_T_MARGIN_SIZES_XX_LARGE"),
                    G_defaults:readSetting("DCREREADER_CONFIG_T_MARGIN_SIZES_XXX_LARGE"),
                    G_defaults:readSetting("DCREREADER_CONFIG_T_MARGIN_SIZES_HUGE"),
                    G_defaults:readSetting("DCREREADER_CONFIG_T_MARGIN_SIZES_X_HUGE"),
                    G_defaults:readSetting("DCREREADER_CONFIG_T_MARGIN_SIZES_XX_HUGE"),
                },
                hide_on_apply = true,
                name_text_hold_callback = optionsutil.showValues,
                name_text_unit = true,
                more_options = true,
                more_options_param = {
                    -- Allow this to tune both top and bottom margins, handling
                    -- 2 setting names (we'll get the exact same DoubleSpinWidget
                    -- in the b_page_margin setting just below)
                    name_text = _("Top/Bottom Margins"),
                    names = { "t_page_margin", "b_page_margin" },
                    event = "SetPageTopAndBottomMargin",
                    widget_width_factor = 0.6,
                    left_text = _("Top"),
                    left_min = 0,
                    left_max = 140,
                    left_step = 1,
                    left_hold_step = 5,
                    right_text = _("Bottom"),
                    right_min = 0,
                    right_max = 140,
                    right_step = 1,
                    right_hold_step = 5,
                },
            },
            {   -- ReaderTypeset
                name = "b_page_margin",
                name_text = _("Bottom Margin"),
                buttonprogress = true,
                values = {
                    G_defaults:readSetting("DCREREADER_CONFIG_B_MARGIN_SIZES_SMALL"),
                    G_defaults:readSetting("DCREREADER_CONFIG_B_MARGIN_SIZES_MEDIUM"),
                    G_defaults:readSetting("DCREREADER_CONFIG_B_MARGIN_SIZES_LARGE"),
                    G_defaults:readSetting("DCREREADER_CONFIG_B_MARGIN_SIZES_X_LARGE"),
                    G_defaults:readSetting("DCREREADER_CONFIG_B_MARGIN_SIZES_XX_LARGE"),
                    G_defaults:readSetting("DCREREADER_CONFIG_B_MARGIN_SIZES_XXX_LARGE"),
                    G_defaults:readSetting("DCREREADER_CONFIG_B_MARGIN_SIZES_HUGE"),
                    G_defaults:readSetting("DCREREADER_CONFIG_B_MARGIN_SIZES_X_HUGE"),
                    G_defaults:readSetting("DCREREADER_CONFIG_B_MARGIN_SIZES_XX_HUGE"),
                },
                default_pos = 3,
                default_value = G_defaults:readSetting("DCREREADER_CONFIG_B_MARGIN_SIZES_LARGE"),
                event = "SetPageBottomMargin",
                args = {
                    G_defaults:readSetting("DCREREADER_CONFIG_B_MARGIN_SIZES_SMALL"),
                    G_defaults:readSetting("DCREREADER_CONFIG_B_MARGIN_SIZES_MEDIUM"),
                    G_defaults:readSetting("DCREREADER_CONFIG_B_MARGIN_SIZES_LARGE"),
                    G_defaults:readSetting("DCREREADER_CONFIG_B_MARGIN_SIZES_X_LARGE"),
                    G_defaults:readSetting("DCREREADER_CONFIG_B_MARGIN_SIZES_XX_LARGE"),
                    G_defaults:readSetting("DCREREADER_CONFIG_B_MARGIN_SIZES_XXX_LARGE"),
                    G_defaults:readSetting("DCREREADER_CONFIG_B_MARGIN_SIZES_HUGE"),
                    G_defaults:readSetting("DCREREADER_CONFIG_B_MARGIN_SIZES_X_HUGE"),
                    G_defaults:readSetting("DCREREADER_CONFIG_B_MARGIN_SIZES_XX_HUGE"),
                },
                hide_on_apply = true,
                name_text_hold_callback = optionsutil.showValues,
                name_text_unit = true,
                help_text = _([[In the top menu → Settings → Status bar, you can choose whether the bottom margin applies from the bottom of the screen, or from above the status bar.]]),
                more_options = true,
                more_options_param = {
                    -- Similar as for t_page_margin above
                    name_text = _("Top/Bottom Margins"),
                    names = { "t_page_margin", "b_page_margin" },
                    event = "SetPageTopAndBottomMargin",
                    widget_width_factor = 0.6,
                    left_text = _("Top"),
                    left_min = 0,
                    left_max = 140,
                    left_step = 1,
                    left_hold_step = 5,
                    right_text = _("Bottom"),
                    right_min = 0,
                    right_max = 140,
                    right_step = 1,
                    right_hold_step = 5,
                },
            },
        }
    },
    {
        icon = "appbar.pageview",
        options = {
            {   -- ReaderView
                name = "view_mode",
                name_text = _("View Mode"),
                toggle = {_("page"), _("continuous")},
                values = {0, 1},
                default_value = G_defaults:readSetting("DCREREADER_VIEW_MODE") == "page" and 0 or 1,
                args = {"page", "scroll"},
                event = "SetViewMode",
                name_text_hold_callback = optionsutil.showValues,
                help_text = _([[- 'page' mode splits the text into pages, at the most acceptable places (page numbers and the number of pages may change when you change fonts, margins, styles, etc.).
- 'continuous' mode allows you to scroll the text like you would in a web browser (the 'Page Overlap' setting is only available in this mode).]]),
            },
            {   -- ReaderTypeset
                name = "block_rendering_mode",
                name_text = _("Render Mode"),
                toggle = {_("legacy"), _("flat"), _("book"), _("web")},
                values = {0, 1, 2, 3},
                default_value = 2,
                args = {0, 1, 2, 3},
                event = "SetBlockRenderingMode",
                name_text_hold_callback = optionsutil.showValues,
                help_text = _([[
- 'legacy' uses original CR3 block rendering code.
- 'flat' ensures flat rendering with collapsing margins and accurate page breaks.
- 'book' additionally allows floats, but limits style support to avoid blank spaces and overflows.
- 'web' renders as web browsers do, allowing negative margins and possible page overflow.]]),
            },
            {   -- ReaderTypeset
                name = "render_dpi",
                name_text = _("Zoom (dpi)"),
                more_options = true,
                more_options_param = {
                    value_hold_step = 20,
                    unit = C_("Resolution", "dpi"),
                },
                toggle = {_("off"), "48", "96¹’¹", "167", "212", "300"},
                values = {0, 48, 96, 167, 212, 300},
                default_value = 96,
                args = {0, 48, 96, 167, 212, 300},
                event = "SetRenderDPI",
                help_text = _([[Sets the DPI used to scale absolute CSS units and images:
- off: ignore absolute units (old engine behavior).
- 96¹’¹: at 96 DPI, 1 CSS pixel = 1 screen pixel and images are rendered at their original dimensions.
- other values scale CSS absolute units and images by a factor (300 DPI = x3, 48 DPI = x0.5)
Using your device's actual DPI will ensure 1 cm in CSS actually translates to 1 cm on screen.
Note that your selected font size is not affected by this setting.]]),
                name_text_hold_callback = optionsutil.showValues,
                name_text_true_values = true,
                show_true_value_func = function(val) -- add "dpi"
                    if val == 96 then
                        val = "96¹’¹"
                    end
                    return val ~= 0 and string.format("%s dpi", val) or _("off")
                end,

            },
            {   -- ReaderFont
                name = "line_spacing",
                name_text = _("Line Spacing"),
                buttonprogress = true,
                values = {
                    G_defaults:readSetting("DCREREADER_CONFIG_LINE_SPACE_PERCENT_X_TINY"),
                    G_defaults:readSetting("DCREREADER_CONFIG_LINE_SPACE_PERCENT_TINY"),
                    G_defaults:readSetting("DCREREADER_CONFIG_LINE_SPACE_PERCENT_XX_SMALL"),
                    G_defaults:readSetting("DCREREADER_CONFIG_LINE_SPACE_PERCENT_X_SMALL"),
                    G_defaults:readSetting("DCREREADER_CONFIG_LINE_SPACE_PERCENT_SMALL"),
                    G_defaults:readSetting("DCREREADER_CONFIG_LINE_SPACE_PERCENT_L_SMALL"),
                    G_defaults:readSetting("DCREREADER_CONFIG_LINE_SPACE_PERCENT_MEDIUM"),
                    G_defaults:readSetting("DCREREADER_CONFIG_LINE_SPACE_PERCENT_L_MEDIUM"),
                    G_defaults:readSetting("DCREREADER_CONFIG_LINE_SPACE_PERCENT_XL_MEDIUM"),
                    G_defaults:readSetting("DCREREADER_CONFIG_LINE_SPACE_PERCENT_XXL_MEDIUM"),
                    G_defaults:readSetting("DCREREADER_CONFIG_LINE_SPACE_PERCENT_LARGE"),
                    G_defaults:readSetting("DCREREADER_CONFIG_LINE_SPACE_PERCENT_X_LARGE"),
                    G_defaults:readSetting("DCREREADER_CONFIG_LINE_SPACE_PERCENT_XX_LARGE"),
                },
                default_pos = 7,
                default_value = G_defaults:readSetting("DCREREADER_CONFIG_LINE_SPACE_PERCENT_MEDIUM"),
                more_options = true,
                more_options_param = {
                  value_min = 50,
                  value_max = 200,
                  value_step = 1,
                  value_hold_step = 5,
                  unit = "%",
                },
                event = "SetLineSpace",
                args = {
                    G_defaults:readSetting("DCREREADER_CONFIG_LINE_SPACE_PERCENT_X_TINY"),
                    G_defaults:readSetting("DCREREADER_CONFIG_LINE_SPACE_PERCENT_TINY"),
                    G_defaults:readSetting("DCREREADER_CONFIG_LINE_SPACE_PERCENT_XX_SMALL"),
                    G_defaults:readSetting("DCREREADER_CONFIG_LINE_SPACE_PERCENT_X_SMALL"),
                    G_defaults:readSetting("DCREREADER_CONFIG_LINE_SPACE_PERCENT_SMALL"),
                    G_defaults:readSetting("DCREREADER_CONFIG_LINE_SPACE_PERCENT_L_SMALL"),
                    G_defaults:readSetting("DCREREADER_CONFIG_LINE_SPACE_PERCENT_MEDIUM"),
                    G_defaults:readSetting("DCREREADER_CONFIG_LINE_SPACE_PERCENT_L_MEDIUM"),
                    G_defaults:readSetting("DCREREADER_CONFIG_LINE_SPACE_PERCENT_XL_MEDIUM"),
                    G_defaults:readSetting("DCREREADER_CONFIG_LINE_SPACE_PERCENT_XXL_MEDIUM"),
                    G_defaults:readSetting("DCREREADER_CONFIG_LINE_SPACE_PERCENT_LARGE"),
                    G_defaults:readSetting("DCREREADER_CONFIG_LINE_SPACE_PERCENT_X_LARGE"),
                    G_defaults:readSetting("DCREREADER_CONFIG_LINE_SPACE_PERCENT_XX_LARGE"),
                },
                name_text_hold_callback = optionsutil.showValues,
                show_true_value_func = function(val) -- add "%"
                    return string.format("%d\u{202F}%%", val) -- use Narrow No-Break space here
                end,
            },
        }
    },
    {
        icon = "appbar.textsize",
        options = {
            {   -- ReaderFont
                name = "font_size",
                alt_name_text = _("Font Size"),
                item_text = tableOfNumbersToTableOfStrings(G_defaults:readSetting("DCREREADER_CONFIG_FONT_SIZES")),
                item_align_center = 1.0,
                spacing = 15,
                item_font_size = G_defaults:readSetting("DCREREADER_CONFIG_FONT_SIZES"),
                values = G_defaults:readSetting("DCREREADER_CONFIG_FONT_SIZES"),
                default_value = G_defaults:readSetting("DCREREADER_CONFIG_DEFAULT_FONT_SIZE"),
                args = G_defaults:readSetting("DCREREADER_CONFIG_FONT_SIZES"),
                event = "SetFontSize",
            },
            {   -- ReaderFont
                name = "font_fine_tune",
                name_text = _("Font Size"),
                toggle = Device:isTouchDevice() and {_("decrease"), _("increase")} or nil,
                item_text = not Device:isTouchDevice() and {_("decrease"), _("increase")} or nil,
                more_options = true,
                more_options_param = {
                    value_min = 12,
                    value_max = 255,
                    value_step = 0.5,
                    precision = "%.1f",
                    value_hold_step = 4,
                    name = "font_size",
                    name_text = _("Font Size"),
                    event = "SetFontSize",
                },
                values = {},
                event = "ChangeSize",
                args = { -0.5, 0.5 },
                alternate = false,
                name_text_hold_callback = function(configurable, __, prefix)
                    local opt = {
                        name = "font_size",
                        name_text = _("Font Size"),
                        name_text_unit = "pt",
                    }
                    optionsutil.showValues(configurable, opt, prefix)
                end,
            },
            {   -- ReaderFont
                name = "word_spacing",
                name_text = _("Word Spacing"),
                more_options = true,
                more_options_param = {
                    name = "word_spacing",
                    name_text = _("Word spacing"),
                    info_text = _([[Set word spacing percentages:
- how much to scale the width of each space character from its regular width,
- by how much some of them can then be reduced to make more words fit on a line.]]),
                    left_text = _("Scaling"),
                    left_min = 10,
                    left_max = 500,
                    left_step = 1,
                    left_hold_step = 10,
                    right_text = _("Reduction"),
                    right_min = 25,
                    right_max = 100,
                    right_step = 1,
                    right_hold_step = 10,
                    unit = "%",
                    event = "SetWordSpacing",
                },
                toggle = {C_("Word spacing", "small"), C_("Word spacing", "medium"), C_("Word spacing", "large")},
                values = {
                    G_defaults:readSetting("DCREREADER_CONFIG_WORD_SPACING_SMALL"),
                    G_defaults:readSetting("DCREREADER_CONFIG_WORD_SPACING_MEDIUM"),
                    G_defaults:readSetting("DCREREADER_CONFIG_WORD_SPACING_LARGE"),
                },
                default_value = G_defaults:readSetting("DCREREADER_CONFIG_WORD_SPACING_MEDIUM"),
                args = {
                    G_defaults:readSetting("DCREREADER_CONFIG_WORD_SPACING_SMALL"),
                    G_defaults:readSetting("DCREREADER_CONFIG_WORD_SPACING_MEDIUM"),
                    G_defaults:readSetting("DCREREADER_CONFIG_WORD_SPACING_LARGE"),
                },
                event = "SetWordSpacing",
                help_text = _([[Tells the rendering engine by how much to scale the width of each 'space' character in the text from its regular width, and by how much it can additionally reduce them to make more words fit on a line (100% means no reduction).]]),
                name_text_hold_callback = optionsutil.showValues,
                name_text_true_values = true,
                show_true_value_func = function(val)
                    return string.format("%d\u{202F}%%, %d\u{202F}%%", val[1], val[2]) -- use Narrow Now-Break space here
                end,
            },
            {   -- ReaderFont
                name = "word_expansion",
                name_text = _("Word Expansion"),
                more_options = true,
                more_options_param = {
                    value_min = 0,
                    value_max = 20,
                    value_step = 1,
                    value_hold_step = 4,
                    unit = "%",
                    name = "word_expansion",
                    name_text = _("Max word expansion"),
                    info_text = _([[Set max word expansion as a percentage of the font size.]]),
                    event = "SetWordExpansion",
                    other_button = { -- allow fine tuning the hidden cjk_width_scaling option (defined below)
                        text = _("CJK scaling"),
                        other_option = "cjk_width_scaling",
                    }
                },
                toggle = {C_("Word expansion", "none"), C_("Word expansion", "some"), C_("Word expansion", "more")},
                values = {
                    G_defaults:readSetting("DCREREADER_CONFIG_WORD_EXPANSION_NONE"),
                    G_defaults:readSetting("DCREREADER_CONFIG_WORD_EXPANSION_SOME"),
                    G_defaults:readSetting("DCREREADER_CONFIG_WORD_EXPANSION_MORE"),
                },
                default_value = G_defaults:readSetting("DCREREADER_CONFIG_WORD_EXPANSION_NONE"),
                args = {
                    G_defaults:readSetting("DCREREADER_CONFIG_WORD_EXPANSION_NONE"),
                    G_defaults:readSetting("DCREREADER_CONFIG_WORD_EXPANSION_SOME"),
                    G_defaults:readSetting("DCREREADER_CONFIG_WORD_EXPANSION_MORE"),
                },
                event = "SetWordExpansion",
                help_text = _([[On justified lines having too wide spaces, allow distributing the excessive space into words by expanding them with letter spacing. This sets the max allowed letter spacing as a % of the font size.]]),
                name_text_hold_callback = optionsutil.showValues,
                name_text_true_values = true,
                show_true_value_func = function(val)
                    return string.format("%d\u{202F}%%", val) -- use Narrow No-Break space here
                end,
            },
            {   -- ReaderFont
                -- This option is not shown in the bottom menu, but its fine tuning is made
                -- available via the other_button in Word Expansion's fine tuning widget.
                -- We still need to define it as an option here for it to be known and
                -- handled as any other one - we just make it hidden.
                show = false,
                name = "cjk_width_scaling",
                default_value = 100,
                values = { 100, 105, 110 }, -- (not shown)
                event = "SetCJKWidthScaling",
                more_options = true,
                more_options_param = {
                    value_min = 100,
                    value_max = 150,
                    value_step = 1,
                    value_hold_step = 5,
                    unit = "%",
                    name = "cjk_width_scaling",
                    name_text = _("CJK width scaling"),
                    info_text = _([[Increase the width of all CJK (Chinese, Japanese, Korean) characters by this percentage. This has the effect of adding space between these glyphs, and might make them easier to distinguish to some readers.]]),
                    event = "SetCJKWidthScaling",
                    other_button = {
                        text = _("Word expansion"),
                        other_option = "word_expansion",
                    }
                },
            },
        }
    },
    {
        icon = "appbar.contrast",
        options = {
            {   -- ReaderFont
                name = "font_gamma",
                name_text = _("Contrast"),
                buttonprogress = true,
                default_value = 15, -- gamma = 1.0
                default_pos = 2,
                values = {10, 15, 25, 30, 36, 43, 49, 56},
                event = "SetFontGamma",
                args = {10, 15, 25, 30, 36, 43, 49, 56},
                -- gamma values for these indexes are:
                labels = {0.8, 1.0, 1.45, 1.90, 2.50, 4.0, 8.0, 15.0},
                name_text_hold_callback = optionsutil.showValues,
                more_options = true,
                more_options_param = {
                    -- Values table taken from crengine/crengine/Tools/GammaGen/gammagen.cpp.
                    -- crengine counts the index of the table starting from 0.
                    -- Index is stored in the settings and passed to crengine as-is.
                    -- ConfigDialog adds value_table_shift to the index to display the value from the table.
                    value_table = { 0.3, 0.35, 0.4, 0.45, 0.5, 0.55, 0.6, 0.65, 0.7, 0.75, 0.8, 0.85, 0.9,
                                    0.95, 0.98, 1, 1.02, 1.05, 1.1, 1.15, 1.2, 1.25, 1.3, 1.35, 1.4, 1.45,
                                    1.5, 1.6, 1.7, 1.8, 1.9, 2, 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8, 2.9,
                                    3, 3.5, 4, 4.5, 5, 5.5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 },
                    value_table_shift = 1,
                },
            },
            {   -- ReaderFont
                name = "font_base_weight",
                name_text = _("Font Weight"),
                toggle = { "-1", "-½", "0", "+½", "+1", "+1½", "+3" },
                values = { -1, -0.5, 0, 0.5, 1, 1.5, 3 },
                args = { -1, -0.5, 0, 0.5, 1, 1.5, 3 },
                default_value = 0,
                event = "SetFontBaseWeight",
                more_options = true,
                more_options_param = {
                    value_min = -3,
                    value_max = 5.5,
                    value_step = 0.25,
                    precision = "%+.2f",
                    value_hold_step = 1,
                },
                help_text = _([[Set the font weight delta from "regular" to apply to all fonts.

- 0 will use the "Regular (400)" variation of a font.
- +1 will use the "Medium (500)" variation of a font if available.
- +3 will use the "Bold (700)" variation of a font if available.
If a font variation is not available, as well as for fractional adjustments, it will be synthesized from the nearest available weight.]]),
                help_text_func = function(configurable, document)
                    local cre = require("document/credocument"):engineInit()
                    local font_face = document:getFontFace()
                    local available_weights = prettifyCreWeights(cre.getFontFaceAvailableWeights(font_face))
                    return T(_("The default font '%1' provides the following weight classes: %2."), font_face, table.concat(available_weights, C_("List separator", ", ")))
                end,
                name_text_hold_callback = optionsutil.showValues,
                name_text_true_values = true,
                show_true_value_func = function(val)
                    return weightClassToString(400+val*100)
                end,
            },
            {   -- ReaderFont
                name = "font_hinting",
                name_text = _("Font Hinting"),
                toggle = {C_("Font hinting", "off"), C_("Font hinting", "native"), C_("Font hinting", "auto")},
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
            {   -- ReaderFont
                name = "font_kerning",
                name_text = _("Font Kerning"),
                toggle = {_("off"), _("fast"), _("good"), _("best")},
                values = {0, 1, 2, 3},
                default_value = 3,
                args = {0, 1, 2, 3},
                event = "SetFontKerning",
                name_text_hold_callback = optionsutil.showValues,
                help_text = _([[Font kerning is the process of adjusting the spacing between individual letter forms, to achieve a visually pleasing result.

- off: no kerning.
- fast: use FreeType's kerning implementation (no ligatures).
- good: use HarfBuzz's light kerning implementation (faster than best but no ligatures and limited support for non-western scripts)
- best: use HarfBuzz's full kerning implementation (slower, but may support ligatures with some fonts; also needed to properly display joined arabic glyphs and some other scripts).

(Font Hinting may need to be adjusted for the best result with either kerning implementation.)]]),
            },
        }
    },
    {
        icon = "appbar.settings",
        options = {
            {   -- ReaderRolling
                name = "status_line",
                name_text = _("Alt Status Bar"),
                toggle = {_("off"), _("on")},
                values = {1, 0}, -- Note that 0 means crengine header status line enabled, and 1 means disabled
                default_value = 1,
                args = {1, 0},
                event = "SetStatusLine",
                name_text_hold_callback = optionsutil.showValues,
                help_text = _([[Enable or disable the rendering engine alternative status bar at the top of the screen. The items displayed can be customized via the main menu.

Whether enabled or disabled, KOReader's own status bar at the bottom of the screen can be toggled by tapping.]]),
            },
            {   -- ReaderTypeset
                name = "embedded_css",
                name_text = _("Embedded Style"),
                toggle = {_("off"), _("on")},
                values = {0, 1},
                default_value = 1,
                args = {false, true},
                event = "ToggleEmbeddedStyleSheet",
                name_text_hold_callback = optionsutil.showValues,
                help_text = _([[Enable or disable publisher stylesheets embedded in the book.
(Note that less radical changes can be achieved via Style Tweaks in the main menu.)]]),
            },
            {   -- ReaderTypeset
                name = "embedded_fonts",
                name_text = _("Embedded Fonts"),
                toggle = {_("off"), _("on")},
                values = {0, 1},
                default_value = 1,
                args = {false, true},
                event = "ToggleEmbeddedFonts",
                enabled_func = function(configurable, document)
                    return optionsutil.enableIfEquals(configurable, "embedded_css", 1)
                            and next(document:getEmbeddedFontList()) ~= nil
                end,
                name_text_hold_callback = optionsutil.showValues,
                help_text = _([[Enable or disable the use of the fonts embedded in the book.
(Disabling the fonts specified in the publisher stylesheets can also be achieved via Style Tweaks in the main menu.)]]),
                help_text_func = function(configurable, document)
                    local font_list = document:getEmbeddedFontList()
                    if next(font_list) then
                        local font_details = {}
                        table.insert(font_details, _("Embedded fonts provided by the current book:"))
                        for name in ffiUtil.orderedPairs(font_list) do
                            table.insert(font_details, name .. (font_list[name] and "" or T("  (%1)", _("not used"))))
                        end
                        return table.concat(font_details, "\n")
                    end
                end,
            },
            {   -- ReaderTypeset
                name = "smooth_scaling",
                name_text = _("Image Scaling"),
                toggle = {_("fast"), _("best")},
                values = {0, 1},
                default_value = 0,
                args = {false, true},
                event = "ToggleImageScaling",
                name_text_hold_callback = optionsutil.showValues,
                help_text = _([[- 'fast' uses a fast but inaccurate scaling algorithm when scaling images.
- 'best' switches to a more costly but vastly more pleasing and accurate algorithm.]]),
            },
            {   -- ReaderTypeset
                name = "nightmode_images",
                name_text = _("Invert Images"),
                toggle = {_("on"), _("off")},
                values = {1, 0},
                default_value = 1,
                args = {true, false},
                event = "ToggleNightmodeImages",
                show_func = function() return Screen.night_mode end,
                name_text_hold_callback = optionsutil.showValues,
                help_text = _([[Disable the automagic inversion of images when nightmode is enabled. Useful if your book contains mainly inlined mathematical content or scene break art.]]),
            },
        },
    },
}

return CreOptions
