CreOptions = {
	prefix = 'copt',
	default_options = {
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
}

