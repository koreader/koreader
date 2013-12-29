local Screen = require("ui/screen")
local S = require("ui/data/strings")

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
				name_text = S.LINE_SPACING,
				item_text = {S.DECREASE, S.INCREASE},
				args = {"decrease", "increase"},
				default_arg = nil,
				event = "ChangeLineSpace",
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
				args = {
					DCREREADER_CONFIG_MARGIN_SIZES_SMALL,
					DCREREADER_CONFIG_MARGIN_SIZES_MEDIUM,
					DCREREADER_CONFIG_MARGIN_SIZES_LARGE,
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
				name_text = S.FONT_WEIGHT,
				item_text = {S.TOGGLE_BOLD},
				-- args is indeed not used, we put here just to keep the
				-- UI happy.
				args = {1},
				default_arg = nil,
				event = "ToggleFontBolder",
			},
			{
				name = "font_gamma",
				name_text = S.GAMMA,
				item_text = {S.DECREASE, S.INCREASE},
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
				name_text = S.VIEW_MODE,
				toggle = {S.VIEW_SCROLL, S.VIEW_PAGE},
				values = {1, 0},
				default_value = 0,
				args = {"scroll", "page"},
				default_arg = "page",
				event = "SetViewMode",
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
			},
		},
	},
}

return CreOptions
