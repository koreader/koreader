ReaderMenu = InputContainer:new{
	key_events = {
		ShowMenu = { { "Menu" }, doc = "show menu" },
	},
}

function ReaderMenu:onShowMenu()
	local item_table = {}

	table.insert(item_table, {
		text = "Switch zoom mode",
		sub_item_table = {
			{
				text = "Zoom to fit content width",
			},
			{
				text = "Zoom to fit content height",
			},
		}
	})

	table.insert(item_table, {
		text = "Return to file browser"
	})

	local main_menu = Menu:new{
		title = "Document menu",
		item_table = item_table,
		width = 300,
		height = #item_table + 3 * 28
	}

	UIManager:show(main_menu)

	return true
end
