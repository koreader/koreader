ReaderFont = InputContainer:new{
	key_events = {
		ShowFontMenu = { {"F"}, doc = "show font menu"},
		IncreaseSize = { { "Shift", Input.group.PgFwd }, doc = "increase font size", event = "ChangeSize", args = "increase" },
		DecreaseSize = { { "Shift", Input.group.PgBack }, doc = "decrease font size", event = "ChangeSize", args = "decrease" },
	},
	dimen = Geom:new{ w = Screen:getWidth()-20, h = Screen:getHeight()-20},
}

function ReaderFont:onShowFontMenu()
	-- build menu item_table
	local face_list = cre.getFontFaces()
	for k,v in ipairs(face_list) do
		face_list[k] = {text = v}
	end

	-- NuPogodi, 18.05.12: define the number of the current font in face_list 
	--local item_no = 0
	--while face_list[item_no] ~= self.font_face and item_no < #face_list do 
		--item_no = item_no + 1 
	--end
	--local fonts_menu = Menu:new{
		--menu_title = "Fonts Menu",
		--item_array = face_list, 
		--current_entry = item_no - 1,
	--}

	local font_menu = Menu:new{
		title = "Font Menu",
		item_table = face_list,
		dimen = self.dimen,
		ui = self.ui
	}

	function font_menu:onMenuChoice(item)
		msg = InfoMessage:new{ text = "Redrawing with "..item.text}
		UIManager:show(msg)
		self.ui.document:setFont(item.text)
		-- signal readerrolling to update pos in new height
		self.ui:handleEvent(Event:new("UpdatePos"))
		UIManager:close(msg)
	end

	UIManager:show(font_menu)
end


