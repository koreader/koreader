require "font"
require "keys"
require "settings"

KOPTOptions =  {
	{
	name="font_size",
	option_text="",
	items_text={"Aa","Aa","Aa","Aa","Aa","Aa","Aa","Aa","Aa"},
	text_font_size={16,18,22,26,30,34,38,42,46},
	default_item=6,
	current_item=6,
	text_dirty=true,
	marker_dirty={true, true, true, true, true, true, true, true, true},
	value={0.2, 0.3, 0.4, 0.6, 1.0, 1.2, 1.6, 2.0, 2.6}},
	{
	name="page_margin",
	option_text="Page Margin",
	items_text={"small","medium","large"},
	default_item=2,
	current_item=2,
	text_dirty=true,
	marker_dirty={true, true, true},
	value={0.02, 0.06, 0.10}},
	{
	name="line_spacing",
	option_text="Line Spacing",
	items_text={"small","medium","large"},
	default_item=2,
	current_item=2,
	text_dirty=true,
	marker_dirty={true, true, true},
	value={1.0, 1.2, 1.4}},
	{
	name="word_spacing",
	option_text="Word Spacing",
	items_text={"smallest","smaller","small","medium","large"},
	default_item=4,
	current_item=4,
	text_dirty=true,
	marker_dirty={true, true, true, true, true},
	value={0.005, 0.01, 0.02, 0.375, 0.5}},
	{
	name="text_wrap",
	option_text="Text Wrap",
	items_text={"page fit","page reflow"},
	default_item=2,
	current_item=2,
	text_dirty=true,
	marker_dirty={true, true},
	value={0, 1}},
	{
	name="auto_straighten",
	option_text="Auto Straighten",
	items_text={"default","0","5","10"},
	default_item=1,
	current_item=1,
	text_dirty=true,
	marker_dirty={true, true, true, true},
	value={0, 0, 5, 10}},
	{
	name="justification",
	option_text="Justification",
	items_text={"default","left","center","right","full"},
	default_item=1,
	current_item=1,
	text_dirty=true,
	marker_dirty={true, true, true, true, true},
	value={-1,0,1,2,3}},
	{
	name="max_columns",
	option_text="Columns",
	items_text={"auto","1","2","3","4"},
	default_item=1,
	current_item=1,
	text_dirty=true,
	marker_dirty={true, true, true, true, true},
	value={2,1,2,3,4}},
	{
	name="contrast",
	option_text="Contrast",
	items_text={"lightest","lighter","default","darker","darkest"},
	default_item=3,
	current_item=3,
	text_dirty=true,
	marker_dirty={true, true, true, true, true},
	value={0.2, 0.4, 1.0, 1.8, 2.6}},
	{
	name="screen_rotation",
	option_text="Screen Rotation",
	items_text={"0","90","180","270"},
	default_item=1,
	current_item=1,
	text_dirty=true,
	marker_dirty={true, true, true, true},
	value={0, 90, 180, 270}},
}

KOPTConfig = {
	-- UI constants
	WIDTH = 550,   -- width
	HEIGHT = 400,  -- height
	MARGIN_BOTTOM = 25,  -- window bottom margin
	OPTION_PADDING_T = 70, -- option top padding
	OPTION_PADDING_H = 50, -- option horizontal padding
	OPTION_SPACING_V = 35,	-- options vertical spacing
	NAME_ALIGN_RIGHT = 0.28, -- align name right to the window width
	ITEM_ALIGN_LEFT = 0.30,	-- align item left to the window width
	ITEM_SPACING_H = 10,   -- items horisontal spacing
	OPT_NAME_FONT_SIZE = 20,  -- option name font size
	OPT_ITEM_FONT_SIZE = 16, -- option item font size
	
	-- last pos text is drawn
	text_pos = 0,
	-- current selected option
	current_option = 1,
	-- page dirty
	page_dirty = false,
}

function KOPTConfig:drawBox(xpos, ypos, width, hight, bgcolor, bdcolor)
	-- draw dialog border
	local r = 6  -- round corners
	fb.bb:paintRect(xpos, ypos+r, width, hight - 2*r, bgcolor)
	blitbuffer.paintBorder(fb.bb, xpos, ypos, width, r, r, bgcolor, r)
	blitbuffer.paintBorder(fb.bb, xpos, ypos+hight-2*r, width, r, r, bgcolor, r)
end

function KOPTConfig:drawOptionName(xpos, ypos, option_index, text, font_face, redraw)
	local width = self.WIDTH
	local xpos, ypos = xpos+self.OPTION_PADDING_H+self.NAME_ALIGN_RIGHT*(width-2*self.OPTION_PADDING_H), ypos+self.OPTION_PADDING_T
	if KOPTOptions[option_index].text_dirty or redraw then
		--Debug("drawing option name:", KOPTOptions[option_index].option_text)
		local text_len = sizeUtf8Text(0, G_width, font_face, text, true).x
		renderUtf8Text(fb.bb, xpos-text_len, ypos+self.OPTION_SPACING_V*(option_index-1), font_face, text, true)
	end
end

function KOPTConfig:drawOptionItem(xpos, ypos, option_index, item_index, text, font_face, redraw, refresh)
	self.text_pos = (item_index == 1) and 0 or self.text_pos
	local width = self.WIDTH
	local offset = self.OPTION_PADDING_H+self.ITEM_ALIGN_LEFT*(width-2*self.OPTION_PADDING_H)
	local item_x_offset = (KOPTOptions[option_index].option_text == "") and self.OPTION_PADDING_H or offset
	local xpos = xpos+item_x_offset+self.ITEM_SPACING_H*(item_index-1)+self.text_pos
	local ypos = ypos+self.OPTION_PADDING_T+self.OPTION_SPACING_V*(option_index-1)
	
	if KOPTOptions[option_index].text_font_size then
		font_face = Font:getFace("cfont", KOPTOptions[option_index].text_font_size[item_index])
	end
	if KOPTOptions[option_index].text_dirty or redraw then
		--Debug("drawing option:", KOPTOptions[option_index].option_text, "item:", text)
		renderUtf8Text(fb.bb, xpos, ypos, font_face, text, true)
	end
	
	local text_len = sizeUtf8Text(0, G_width, font_face, text, true).x
	self.text_pos = self.text_pos + text_len
	
	if KOPTOptions[option_index].marker_dirty[item_index] or redraw then
		--Debug("drawing option:", KOPTOptions[option_index].option_text, "marker:", text)
		if item_index == KOPTOptions[option_index].current_item then
			fb.bb:paintRect(xpos, ypos+5, text_len, 3,(option_index == self.current_option) and 15 or 5)
			if refresh then 
				fb:refresh(1, xpos, ypos+5, text_len, 3)
			end
		else
			fb.bb:paintRect(xpos, ypos+5, text_len, 3, 3)
			if refresh then
				fb:refresh(1, xpos, ypos+5, text_len, 3)
			end
		end
		KOPTOptions[option_index].marker_dirty[item_index] = false
	end
end

function KOPTConfig:drawOptions(xpos, ypos, name_font, item_font, redraw, refresh)
	local width, height = self.WIDTH, self.HEIGHT
	for i=1,#KOPTOptions do
		self:drawOptionName(xpos, ypos, i, KOPTOptions[i].option_text, name_font, redraw)
		for j=1,#KOPTOptions[i].items_text do
			self:drawOptionItem(xpos, ypos, i, j, KOPTOptions[i].items_text[j], item_font, redraw, refresh)
		end
		KOPTOptions[i].text_dirty = false
	end
end

function KOPTConfig:makeDefault(configurable)
	for i=1,#KOPTOptions do
		KOPTOptions[i].text_dirty = true
		for j=1,#KOPTOptions[i].items_text do
			KOPTOptions[i].marker_dirty[j] = true
		end
		local option = KOPTOptions[i].name
		local value = configurable[option]
		KOPTOptions[i].current_item = KOPTOptions[i].default_item
		for index, val in pairs(KOPTOptions[i].value) do
			if val == value then
				KOPTOptions[i].current_item = index
				break
			end
		end
	end
end

function KOPTConfig:reconfigure(configurable)
	for i=1,#KOPTOptions do
		option = KOPTOptions[i].name
		configurable[option] = KOPTOptions[i].value[KOPTOptions[i].current_item]
	end
end

function KOPTConfig:config(callback, reader, configurable)
	local kopt_callback = callback
	local koptreader = reader
	--local configurable = configurable
	
	self:makeDefault(configurable)
	self:addAllCommands()
	
	local name_font = Font:getFace("tfont", self.OPT_NAME_FONT_SIZE)
	local item_font = Font:getFace("cfont", self.OPT_ITEM_FONT_SIZE)
	
	-- base window coordinates 
	local width, height = self.WIDTH, self.HEIGHT
	local topleft_x, topleft_y = (fb.bb:getWidth()-width)/2, fb.bb:getHeight()-self.MARGIN_BOTTOM-height
	local botleft_x, botleft_y = topleft_x, topleft_y+height
	
	self:drawBox(topleft_x, topleft_y, width, height, 3, 15)
	self:drawOptions(topleft_x, topleft_y, name_font, item_font, true, false)
	fb:refresh(1, topleft_x, topleft_y, width, height)
	
	local ev, keydef, command, ret_code
	while true do
	
		self:reconfigure(configurable)
		
		if self.page_dirty then
			kopt_callback(koptreader)
			self:drawBox(topleft_x, topleft_y, width, height, 3, 15)
			self:drawOptions(topleft_x, topleft_y, name_font, item_font, true, false)
			fb:refresh(1, topleft_x, topleft_y, width, height)
			self.page_dirty = false
		end
		self:drawOptions(topleft_x, topleft_y, name_font, item_font, false, true)
		
		ev = input.saveWaitForEvent()
		ev.code = adjustKeyEvents(ev)
		if ev.type == EV_KEY and ev.value ~= EVENT_VALUE_KEY_RELEASE then
			keydef = Keydef:new(ev.code, getKeyModifier())
			Debug("key pressed: "..tostring(keydef))
			command = self.commands:getByKeydef(keydef)
			if command ~= nil then
				Debug("command to execute: "..tostring(command))
				ret_code = command.func(self, keydef)
			else
				Debug("command not found: "..tostring(command))
			end
			if ret_code == "break" then
				ret_code = nil
				return nil
			end
		end -- if
	end -- while
end

-- add available commands
function KOPTConfig:addAllCommands()
	self.commands = Commands:new{}
	self.commands:add(KEY_FW_DOWN, nil, "joypad down",
		"next item",
		function(self)
			local last_option = self.current_option
			self.current_option = (self.current_option + #KOPTOptions + 1)%#KOPTOptions
			self.current_option = (self.current_option == 0) and #KOPTOptions or self.current_option
			
			last_option_item = KOPTOptions[last_option].current_item
			KOPTOptions[last_option].marker_dirty[last_option_item] = true
			current_option_item = KOPTOptions[self.current_option].current_item
			KOPTOptions[self.current_option].marker_dirty[current_option_item] = true
		end
	)
	self.commands:add(KEY_FW_UP, nil, "joypad up",
		"previous item",
		function(self)
			local last_option = self.current_option
			self.current_option = (self.current_option + #KOPTOptions - 1)%#KOPTOptions
			self.current_option = (self.current_option == 0) and #KOPTOptions or self.current_option
			
			last_option_item = KOPTOptions[last_option].current_item
			KOPTOptions[last_option].marker_dirty[last_option_item] = true
			current_option_item = KOPTOptions[self.current_option].current_item
			KOPTOptions[self.current_option].marker_dirty[current_option_item] = true
		end
	)
	self.commands:add(KEY_FW_LEFT, nil, "joypad left",
		"last item",
		function(self)
			local last_item = KOPTOptions[self.current_option].current_item
			local item_count = #KOPTOptions[self.current_option].items_text
			local current_item = (KOPTOptions[self.current_option].current_item + item_count - 1)%item_count
			current_item = (current_item == 0) and item_count or current_item
			KOPTOptions[self.current_option].current_item = current_item
			
			KOPTOptions[self.current_option].marker_dirty[last_item] = true
			KOPTOptions[self.current_option].marker_dirty[current_item] = true
			self.page_dirty = true
		end
	)
	self.commands:add(KEY_FW_RIGHT, nil, "joypad right",
		"next item",
		function(self)
			local last_item = KOPTOptions[self.current_option].current_item
			local item_count = #KOPTOptions[self.current_option].items_text
			local current_item = (KOPTOptions[self.current_option].current_item + item_count + 1)%item_count
			current_item = (current_item == 0) and item_count or current_item
			KOPTOptions[self.current_option].current_item = current_item
			
			KOPTOptions[self.current_option].marker_dirty[last_item] = true
			KOPTOptions[self.current_option].marker_dirty[current_item] = true
			self.page_dirty = true
		end
	)
	self.commands:add({KEY_F,KEY_AA,KEY_BACK}, nil, "Back",
		"back",
		function(self)
			return "break"
		end
	)
end