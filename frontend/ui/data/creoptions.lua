require "ui/screen"
require "ui/data/strings"

CreOptions = {
	prefix = 'copt',
	{
		icon = "resources/icons/appbar.transform.rotate.right.large.png",
		options = {
			{
				name = "screen_mode",
				name_text = SCREEN_MODE_STR,
				toggle = {PORTRAIT_STR, LANDSCAPE_STR},
				args = {"portrait", "landscape"},
				default_arg = "portrait",
				current_func = function() return Screen:getScreenMode() end,
				event = "SetScreenMode",
			}
		}
	},
	{
		icon = "resources/icons/appbar.column.two.large.png",
		options = {
			{
				name = "line_spacing",
				name_text = LINE_SPACING_STR,
				item_text = {DECREASE_STR, INCREASE_STR},
				args = {"decrease", "increase"},
				default_arg = nil,
				event = "ChangeLineSpace",
			},
		}
	},
	{
		icon = "resources/icons/appbar.text.size.large.png",
		options = {
			{
				name = "font_size",
				item_text = {"Aa", "Aa", "Aa", "Aa", "Aa", "Aa", "Aa", "Aa"},
				item_align_center = 1.0,
				spacing = 15,
				item_font_size = {18, 20, 22, 24, 29, 33, 39, 44},
				values = {18, 20, 22, 24, 29, 33, 39, 44},
				default_value = 22,
				args = {18, 20, 22, 24, 29, 33, 39, 44},
				event = "SetFontSize",
			},
		}
	},
	{
		icon = "resources/icons/appbar.grade.b.large.png",
		options = {
			{
				name = "font_weight",
				name_text = FONT_WEIGHT_STR,
				item_text = {TOGGLE_BOLD_STR},
				-- args is indeed not used, we put here just to keep the
				-- UI happy.
				args = {1},
				default_arg = nil,
				event = "ToggleFontBolder",
			},
			{
				name = "font_gamma",
				name_text = GAMMA_STR,
				item_text = {DECREASE_STR, INCREASE_STR},
				args = {"decrease", "increase"},
				default_arg = nil,
				event = "ChangeFontGamma",
			}
		}
	},
	{
		icon = "resources/icons/appbar.settings.large.png",
		options = {
			{
				name = "view_mode",
				name_text = VIEW_MODE_STR,
				toggle = {VIEW_SCROLL_STR, VIEW_PAGE_STR},
				values = {1, 0},
				default_value = 0,
				args = {"scroll", "page"},
				default_arg = "page",
				event = "SetViewMode",
			},
			{
				name = "embedded_css",
				name_text = EMBEDDED_STYLE_STR,
				toggle = {ON_STR, OFF_STR},
				values = {1, 0},
				default_value = 0,
				args = {1, 0},
				default_arg = nil,
				event = "ToggleEmbeddedStyleSheet",
			},
		},
	},
}
