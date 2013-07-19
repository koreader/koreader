require "ui/screen"
require "ui/data/strings"

KoptOptions = {
	prefix = 'kopt',
	{
		icon = "resources/icons/appbar.transform.rotate.right.large.png",
		options = {
			{
				name = "screen_mode",
				name_text = SCREEN_MODE_STR,
				toggle = {PORTRAIT_STR, LANDSCAPE_STR},
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
				name_text = PAGE_CROP_STR,
				toggle = {MANUAL_STR, AUTO_STR, SEMIAUTO_STR},
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
				name = "full_screen",
				name_text = FULL_SCREEN_STR,
				toggle = {ON_STR, OFF_STR},
				values = {1, 0},
				default_value = DFULL_SCREEN,
				event = "SetFullScreen",
				args = {true, false},
			},
			{
				name = "page_scroll",
				name_text = SCROLL_MODE_STR,
				toggle = {ON_STR, OFF_STR},
				values = {1, 0},
				default_value = DSCROLL_MODE,
				event = "ToggleScrollMode",
				args = {true, false},
			},
			{
				name = "page_margin",
				name_text = PAGE_MARGIN_STR,
				toggle = {SMALL_STR, MEDIUM_STR, LARGE_STR},
				values = {0.05, 0.10, 0.15},
				default_value = DKOPTREADER_CONFIG_PAGE_MARGIN,
				event = "MarginUpdate",
			},
			{
				name = "line_spacing",
				name_text = LINE_SPACING_STR,
				toggle = {SMALL_STR, MEDIUM_STR, LARGE_STR},
				values = {1.0, 1.2, 1.4},
				default_value = DKOPTREADER_CONFIG_LINE_SPACING,
			},
			{
				name = "max_columns",
				name_text = COLUMNS_STR,
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
				name_text = TEXT_ALIGN_STR,
				item_icons = {
					"resources/icons/appbar.align.auto.png",
					"resources/icons/appbar.align.left.png",
					"resources/icons/appbar.align.center.png",
					"resources/icons/appbar.align.right.png",
					"resources/icons/appbar.align.justify.png",
				},
				values = {-1,0,1,2,3},
				default_value = DKOPTREADER_CONFIG_JUSTIFICATION,
			},
		}
	},
	{
		icon = "resources/icons/appbar.text.size.large.png",
		options = {
			{
				name = "font_size",
				item_text = {"Aa","Aa","Aa","Aa","Aa","Aa","Aa","Aa","Aa","Aa"},
				item_align_center = 1.0,
				spacing = 15,
				height = 60,
				item_font_size = {22,24,28,32,34,36,38,42,46,50},
				values = {0.1, 0.2, 0.4, 0.6, 0.8, 1.0, 1.2, 1.6, 2.0, 4.0},
				default_value = DKOPTREADER_CONFIG_FONT_SIZE,
				event = "FontSizeUpdate",
			},
			{
				name = "font_fine_tune",
				name_text = FONTSIZE_FINE_TUNING_STR,
				toggle = {DECREASE_STR, INCREASE_STR},
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
				name_text = CONTRAST_STR,
				name_align_right = 0.2,
				item_text = {LIGHTEST_STR , LIGHTER_STR, DEFAULT_STR, DARKER_STR, DARKEST_STR},
				item_font_size = 18,
				item_align_center = 0.8,
				values = {2.0, 1.5, 1.0, 0.5, 0.2},
				default_value = DKOPTREADER_CONFIG_CONTRAST,
				event = "GammaUpdate",
				args = {0.5, 0.8, 1.0, 2.0, 4.0},
			}
		}
	},
	{
		icon = "resources/icons/appbar.settings.large.png",
		options = {
			{
				name = "text_wrap",
				name_text = _("Reflow"),
				toggle = {ON_STR, OFF_STR},
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
				name="doc_language",
				name_text = DOC_LANG_STR,
				toggle = DKOPTREADER_CONFIG_DOC_LANGS_TEXT,
				values = DKOPTREADER_CONFIG_DOC_LANGS_CODE,
				default_value = DKOPTREADER_CONFIG_DOC_DEFAULT_LANG_CODE,
				event = "DocLangUpdate",
				args = DKOPTREADER_CONFIG_DOC_LANGS_CODE,
			},
			{
				name="screen_rotation",
				name_text = VERTICAL_TEXT_STR,
				toggle = {ON_STR, OFF_STR},
				values = {90, 0},
				default_value = 0,
			},
			{
				name = "word_spacing",
				name_text = WORD_GAP_STR,
				toggle = {SMALL_STR, MEDIUM_STR, LARGE_STR},
				values = DKOPTREADER_CONFIG_WORD_SAPCINGS,
				default_value = DKOPTREADER_CONFIG_DEFAULT_WORD_SAPCING,
			},
			{
				name = "defect_size",
				name_text = DEFECT_SIZE_STR,
				toggle = {SMALL_STR, MEDIUM_STR, LARGE_STR},
				values = {1.0, 8.0, 15.0},
				default_value = DKOPTREADER_CONFIG_DEFECT_SIZE,
				event = "DefectSizeUpdate",
			},
			{
				name = "quality",
				name_text = RENDER_QUALITY_STR,
				toggle = {LOW_STR, DEFAULT_STR, HIGH_STR},
				values={0.5, 1.0, 1.5},
				default_value = DKOPTREADER_CONFIG_RENDER_QUALITY,
			},
			{
				name = "auto_straighten",
				name_text = AUTO_STRAIGHTEN_STR,
				toggle = {ZERO_DEG_STR, FIVE_DEG_STR, TEN_DEG_STR},
				values = {0, 5, 10},
				default_value = DKOPTREADER_CONFIG_AUTO_STRAIGHTEN,
				show = false,
			},
			{
				name = "detect_indent",
				name_text = INDENTATION_STR,
				toggle = {ON_STR, OFF_STR},
				values = {1, 0},
				default_value = DKOPTREADER_CONFIG_DETECT_INDENT,
				show = false,
			},
		}
	},
}
