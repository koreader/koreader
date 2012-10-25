require "font"
require "keys"
require "settings"

KOPTOptions =  {
	{
	name="line_spacing",
	option_text="Line Spacing",
	items_text={"small","medium","large"},
	current_item=2,
	text_dirty=true,
	marker_dirty={true, true, true},
	space={1.0, 1.2, 1.4}},
	{
	name="word_spacing",
	option_text="Word Spacing",
	items_text={"small","medium","large"},
	current_item=2,
	text_dirty=true,
	marker_dirty={true, true, true},
	space={0.2, 0.375, 0.5}},
}

KOPTConfig = {
	-- UI constants
	HEIGHT = 200,  -- height
	MARGIN_BOTTOM = 20,  -- window bottom margin
	MARGIN_HORISONTAL = 75, -- window horisontal margin
	OPTION_PADDING_T = 50, -- options top padding
	OPTION_PADDING_H = 50,  -- options horisontal padding
	OPTION_SPACING_V = 35,	-- options vertical spacing
	VALUE_PADDING_H = 150,  -- values horisontal padding
	VALUE_SPACING_H = 10,   -- values horisontal spacing
	OPT_NAME_FONT_SIZE = 20,  -- option name font size
	OPT_VALUE_FONT_SIZE = 16, -- option value font size
	
	-- last pos text is drawn
	text_pos = 0,
	-- current selected option
	current_option = 1,
	-- page dirty
	page_dirty = false,
}

configurable = {
	font_size = 1.0,
	page_margin = 0.06,
	line_spacing = 1.2,
	word_spacing = 0.375,
}

function KOPTConfig:drawBox(xpos, ypos, width, hight, bgcolor, bdcolor)
	-- draw dialog border
	local r = 6  -- round corners
	fb.bb:paintRect(xpos, ypos+r, width, hight - 2*r, bgcolor)
	blitbuffer.paintBorder(fb.bb, xpos, ypos, width, r, r, bgcolor, r)
	blitbuffer.paintBorder(fb.bb, xpos, ypos+hight-2*r, width, r, r, bgcolor, r)
end

function KOPTConfig:drawOptionName(xpos, ypos, option_index, text, font_face, refresh)
	local xpos, ypos = xpos+self.OPTION_PADDING_H, ypos+self.OPTION_PADDING_T
	if KOPTOptions[option_index].text_dirty or refresh then
		--Debug("drawing option name:", KOPTOptions[option_index].option_text)
		renderUtf8Text(fb.bb, xpos, ypos+self.OPTION_SPACING_V*(option_index-1), font_face, text, true)
	end
end

function KOPTConfig:drawOptionItem(xpos, ypos, option_index, item_index, text, font_face, refresh)
	if item_index == 1 then
		self.text_pos = 0
	end
	
	local xpos = xpos+self.OPTION_PADDING_H+self.VALUE_PADDING_H+self.VALUE_SPACING_H*(item_index-1)+self.text_pos
	local ypos = ypos+self.OPTION_PADDING_T+self.OPTION_SPACING_V*(option_index-1)
	
	if KOPTOptions[option_index].text_dirty or refresh then
		--Debug("drawing option:", KOPTOptions[option_index].option_text, "item:", text)
		renderUtf8Text(fb.bb, xpos, ypos, font_face, text, true)
	end
	
	local text_len = sizeUtf8Text(0, G_width, font_face, text, true).x
	self.text_pos = self.text_pos + text_len
	
	if KOPTOptions[option_index].marker_dirty[item_index] then
		--Debug("drawing option:", KOPTOptions[option_index].option_text, "marker:", text)
		if item_index == KOPTOptions[option_index].current_item then
			fb.bb:paintRect(xpos, ypos+5, text_len, 3,(option_index == self.current_option) and 15 or 5)
			fb:refresh(1, xpos, ypos+5, text_len, 3)
		else
			fb.bb:paintRect(xpos, ypos+5, text_len, 3, 3)
			fb:refresh(1, xpos, ypos+5, text_len, 3)
		end
		KOPTOptions[option_index].marker_dirty[item_index] = false
	end
end

function KOPTConfig:drawOptions(xpos, ypos, name_font, value_font, refresh)
	local width, height = fb.bb:getWidth()-2*self.MARGIN_HORISONTAL, self.HEIGHT
	for i=1,#KOPTOptions do
		self:drawOptionName(xpos, ypos, i, KOPTOptions[i].option_text, name_font, refresh)
		for j=1,#KOPTOptions[i].items_text do
			self:drawOptionItem(xpos, ypos, i, j, KOPTOptions[i].items_text[j], value_font, refresh)
		end
		KOPTOptions[i].text_dirty = false
	end
end

function KOPTConfig:config(callback, reader)
	local kopt_callback = callback
	local koptreader = reader
	self:addAllCommands()
	
	local name_font = Font:getFace("tfont", self.OPT_NAME_FONT_SIZE)
	local value_font = Font:getFace("cfont", self.OPT_VALUE_FONT_SIZE)
	
	-- base window coordinates 
	local width, height = fb.bb:getWidth()-2*self.MARGIN_HORISONTAL, self.HEIGHT
	local topleft_x, topleft_y = self.MARGIN_HORISONTAL, fb.bb:getHeight()-self.MARGIN_BOTTOM-height
	local botleft_x, botleft_y = self.MARGIN_HORISONTAL, topleft_y+height
	
	self:drawBox(topleft_x, topleft_y, width, height, 3, 15)
	self:drawOptions(topleft_x, topleft_y, name_font, value_font)
	fb:refresh(1, topleft_x, topleft_y, width, height)
	
	local ev, keydef, command, ret_code
	while true do
		configurable.line_spacing = KOPTOptions[1].space[KOPTOptions[1].current_item]
		configurable.word_spacing = KOPTOptions[2].space[KOPTOptions[2].current_item]
		--Debug("Line spacing:", configurable.line_spacing, "Word spacing:", configurable.word_spacing)
		if self.page_dirty then
			kopt_callback(koptreader, configurable)
			self:drawBox(topleft_x, topleft_y, width, height, 3, 15)
			self:drawOptions(topleft_x, topleft_y, name_font, value_font, true)
			fb:refresh(1, topleft_x, topleft_y, width, height)
			self.page_dirty = false
		end
		self:drawOptions(topleft_x, topleft_y, name_font, value_font)
		
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
				if self.final_choice then
					return self.readers[self.final_choice]
				else
					return nil
				end
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