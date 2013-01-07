CreOptions = {
	prefix = 'copt',
	default_options = {
	},
	{
		icon = "resources/icons/appbar.column.two.large.png",
		options = {
			{
				name = "line_spacing",
				name_text = "Line Spacing",
				item_text = {"decrease", "increase"},
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
				spacing = Screen:getWidth()*0.03,
				item_font_size = {18, 20, 22, 24, 29, 33, 39, 44},
				values = {18, 20, 22, 24, 29, 33, 39, 44},
				default_value = 1,
				event = "SetFontSize",
			},
		}
	},
	{
		icon = "resources/icons/appbar.grade.b.large.png",
		options = {
			{
				name = "font_weight",
				name_text = "Font weight",
				item_text = {"toggle bolder"},
				-- args is indeed not used, we put here just to keep the
				-- UI happy.
				args = {1},
				default_arg = nil,
				event = "ToggleFontBolder",
			}
		}
	},
	{
		icon = "resources/icons/appbar.settings.large.png",
		options = {
			{
				name = "view_mode",
				name_text = "View mode",
				item_text = {"scroll", "page"},
				args = {"scroll", "page"},
				default_arg = "page",
				event = "SetViewMode",
			},
		}
	},
}

