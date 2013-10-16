require "ui/screen"
require "ui/data/strings"

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
			{
				name = "page_margins",
				name_text = PAGE_MARGIN_STR,
				toggle = {SMALL_STR, MEDIUM_STR, LARGE_STR},
				values = {
					{6, 5, 2, 5},
					{15, 10, 10, 10},
					{25, 10, 20, 10},
				},
				default_value = {15, 10, 10, 10},
				args = {
					{6, 5, 2, 5},
					{15, 10, 10, 10},
					{25, 10, 20, 10},
				},
				event = "SetPageMargins",
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
				default_value = 22,
				args = DCREREADER_CONFIG_FONT_SIZES,
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
				default_value = 1,
				args = {true, false},
				default_arg = nil,
				event = "ToggleEmbeddedStyleSheet",
			},
		},
	},
}
