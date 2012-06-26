ReaderFont = InputContainer:new{
	key_events = {
		ShowFontMenu = { {"F"}, doc = "show font menu"},
		IncreaseSize = { 
			{ "Shift", Input.group.PgFwd }, 
			doc = "increase font size", 
			event = "ChangeSize", args = "increase" },
		DecreaseSize = { 
			{ "Shift", Input.group.PgBack },
			doc = "decrease font size",
			event = "ChangeSize", args = "decrease" },
		IncreaseLineSpace = {
			{ "Alt", Input.group.PgFwd },
			doc = "increase line space",
			event = "ChangeLineSpace", args = "increase" },
		DecreaseLineSpace = {
			{ "Alt", Input.group.PgBack },
			doc = "decrease line space",
			event = "ChangeLineSpace", args = "decrease" },
	},
	dimen = Geom:new{ w = Screen:getWidth()-20, h = Screen:getHeight()-20},

	font_face = nil,
	font_size = nil,
	line_space_percent = 100,
}

function ReaderFont:init()
end

function ReaderFont:onSetDimensions(dimen)
	self.dimen = dimen
end

function ReaderFont:onReadSettings(config)
	self.font_face = config:readSetting("font_face")
	if not self.font_face then 
		self.font_face = self.ui.document:getFontFace()
	end

	self.font_size = config:readSetting("font_size")
	if not self.font_size then 
		self.font_size = self.ui.document:getFontSize()
	end
end

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
		caller = self,
		ui = self.ui
	}

	function font_menu:onMenuChoice(item)
		if item.text and self.font_face ~= item.text then
			self.caller.font_face = item.text
			msg = InfoMessage:new{ text = "Redrawing with "..item.text}
			UIManager:show(msg)
			self.ui.document:setFontFace(item.text)
			-- signal readerrolling to update pos in new height
			self.ui:handleEvent(Event:new("UpdatePos"))
			UIManager:close(msg)
		end
	end

	UIManager:show(font_menu)
	return true
end

function ReaderFont:onChangeSize(direction)
	local delta = 1
	if direction == "decrease" then
	   delta = -1
	end
	self.font_size = self.font_size + delta
	msg = InfoMessage:new{text = direction.." font size to "..self.font_size}
	UIManager:show(msg)
	self.ui.document:zoomFont(delta)
	self.ui:handleEvent(Event:new("UpdatePos"))
	UIManager:close(msg)

	return true
end

function ReaderFont:onChangeLineSpace(direction)
	if direction == "decrease" then
		self.line_space_percent = self.line_space_percent - 10
		-- NuPogodi, 15.05.12: reduce lowest space_percent to 80
		self.line_space_percent = math.max(self.line_space_percent, 80)
	else
		self.line_space_percent = self.line_space_percent + 10
		self.line_space_percent = math.min(self.line_space_percent, 200)
	end
	msg = InfoMessage:new{"line spacing "..self.line_space_percent.."%"}
	self.ui.document:setInterlineSpacePercent(self.line_space_percent)
	self.ui:handleEvent(Event:new("UpdatePos"))

	return true
end

function ReaderFont:onCloseDocument()
	self.ui.doc_settings:saveSetting("font_face", self.font_face)
	self.ui.doc_settings:saveSetting("font_size", self.font_size)
end
