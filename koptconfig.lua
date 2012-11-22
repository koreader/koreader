require "font"
require "keys"
require "settings"
require "defaults"

KOPTOptions =  {
	{
	name="font_size",
	option_text="",
	items_text={"Aa","Aa","Aa","Aa","Aa","Aa","Aa","Aa","Aa","Aa"},
	text_font_size={14,16,20,23,26,30,34,38,42,46},
	current_item=nil,
	text_dirty=true,
	marker_dirty={true, true, true, true, true, true, true, true, true, true},
	values={0.2, 0.3, 0.4, 0.6, 0.8, 1.0, 1.2, 1.6, 2.2, 2.8},
	default_value=DKOPTREADER_CONFIG_FONT_SIZE,
	show = true,
	draw_index = nil,},
	{
	name="text_wrap",
	option_text="Reflow",
	items_text={"on","off"},
	current_item=nil,
	text_dirty=true,
	marker_dirty={true, true},
	values={1, 0},
	default_value=DKOPTREADER_CONFIG_TEXT_WRAP,
	show = true,
	draw_index = nil,},
	{
	name="trim_page",
	option_text="Trim Page",
	items_text={"auto","manual"},
	current_item=nil,
	text_dirty=true,
	marker_dirty={true, true},
	values={1, 0},
	default_value=DKOPTREADER_CONFIG_TRIM_PAGE,
	show = true,
	draw_index = nil,},
	{
	name="detect_indent",
	option_text="Indentation",
	items_text={"enable","disable"},
	current_item=nil,
	text_dirty=true,
	marker_dirty={true, true},
	values={1, 0},
	default_value=DKOPTREADER_CONFIG_DETECT_INDENT,
	show = false,
	draw_index = nil,},
	{
	name="defect_size",
	option_text="Defect Size",
	items_text={"small","medium","large"},
	current_item=nil,
	text_dirty=true,
	marker_dirty={true, true, true},
	values={0.5, 1.0, 2.0},
	default_value=DKOPTREADER_CONFIG_DEFECT_SIZE,
	show = true,
	draw_index = nil,},
	{
	name="page_margin",
	option_text="Page Margin",
	items_text={"small","medium","large"},
	current_item=nil,
	text_dirty=true,
	marker_dirty={true, true, true},
	values={0.02, 0.06, 0.10},
	default_value=DKOPTREADER_CONFIG_PAGE_MARGIN,
	show = true,
	draw_index = nil,},
	{
	name="line_spacing",
	option_text="Line Spacing",
	items_text={"small","medium","large"},
	current_item=nil,
	text_dirty=true,
	marker_dirty={true, true, true},
	values={1.0, 1.2, 1.4},
	default_value=DKOPTREADER_CONFIG_LINE_SPACING,
	show = true,
	draw_index = nil,},
	{
	name="word_spacing",
	option_text="Word Spacing",
	items_text={"small","medium","large"},
	current_item=nil,
	text_dirty=true,
	marker_dirty={true, true, true},
	values={0.05, 0.15, 0.375},
	default_value=DKOPTREADER_CONFIG_WORD_SAPCING,
	show = true,
	draw_index = nil,},
	{
	name="multi_threads",
	option_text="Multi Threads",
	items_text={"on","off"},
	current_item=nil,
	text_dirty=true,
	marker_dirty={true, true},
	values={1, 0},
	default_value=DKOPTREADER_CONFIG_MULTI_THREADS,
	show = true,
	draw_index = nil,},
	{
	name="quality",
	option_text="Render Quality",
	items_text={"low","medium","high"},
	current_item=nil,
	text_dirty=true,
	marker_dirty={true, true, true},
	values={0.5, 0.8, 1.0},
	default_value=DKOPTREADER_CONFIG_RENDER_QUALITY,
	show = true,
	draw_index = nil,},
	{
	name="auto_straighten",
	option_text="Auto Straighten",
	items_text={"0","5","10"},
	current_item=nil,
	text_dirty=true,
	marker_dirty={true, true, true},
	values={0, 5, 10},
	default_value=DKOPTREADER_CONFIG_AUTO_STRAIGHTEN,
	show = true,
	draw_index = nil,},
	{
	name="justification",
	option_text="Justification",
	items_text={"auto","left","center","right","full"},
	current_item=nil,
	text_dirty=true,
	marker_dirty={true, true, true, true, true},
	values={-1,0,1,2,3},
	default_value=DKOPTREADER_CONFIG_JUSTIFICATION,
	show = true,
	draw_index = nil,},
	{
	name="max_columns",
	option_text="Columns",
	items_text={"1","2","3","4"},
	current_item=nil,
	text_dirty=true,
	marker_dirty={true, true, true, true},
	values={1,2,3,4},
	default_value=DKOPTREADER_CONFIG_MAX_COLUMNS,
	show = true,
	draw_index = nil,},
	{
	name="contrast",
	option_text="Contrast",
	items_text={"lightest","lighter","default","darker","darkest"},
	current_item=nil,
	text_dirty=true,
	marker_dirty={true, true, true, true, true},
	values={2.0, 1.5, 1.0, 0.5, 0.2},
	default_value=DKOPTREADER_CONFIG_CONTRAST,
	show = true,
	draw_index = nil,},
	{
	name="screen_rotation",
	option_text="Screen Rotation",
	items_text={"0","90","180","270"},
	current_item=nil,
	text_dirty=true,
	marker_dirty={true, true, true, true},
	values={0, 90, 180, 270},
	default_value=DKOPTREADER_CONFIG_SCREEN_ROTATION,
	show = true,
	draw_index = nil,},
}

KOPTConfig = {
	-- UI constants
	WIDTH = 550,   -- width
	HEIGHT = nil,  -- height, updated in run time
	MARGIN_BOTTOM = 25,  -- window bottom margin
	OPTION_PADDING_T = 60, -- option top padding
	OPTION_PADDING_H = 70, -- option horizontal padding
	OPTION_SPACING_V = 30,	-- options vertical spacing
	NAME_ALIGN_RIGHT = 0.28, -- align name right to the window width
	ITEM_ALIGN_LEFT = 0.30,	-- align item left to the window width
	ITEM_SPACING_H = 10,   -- items horisontal spacing
	OPT_NAME_FONT_SIZE = 20,  -- option name font size
	OPT_ITEM_FONT_SIZE = 16, -- option item font size
	
	-- last pos text is drawn
	text_pos = 0,
	-- current selected option
	current_option = 1,
	-- config change
	config_change = false,
	confirm_change = false,
	
	-- reader object
	koptreader = nil
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
		local draw_index = KOPTOptions[option_index].draw_index
		renderUtf8Text(fb.bb, xpos-text_len, ypos+self.OPTION_SPACING_V*(draw_index-1), font_face, text, true)
	end
end

function KOPTConfig:drawOptionItem(xpos, ypos, option_index, item_index, text, font_face, redraw, refresh)
	self.text_pos = (item_index == 1) and 0 or self.text_pos
	local width = self.WIDTH
	local offset = self.OPTION_PADDING_H+self.ITEM_ALIGN_LEFT*(width-2*self.OPTION_PADDING_H)
	local item_x_offset = (KOPTOptions[option_index].option_text == "") and self.OPTION_PADDING_H or offset
	local draw_index = KOPTOptions[option_index].draw_index
	local xpos = xpos+item_x_offset+self.ITEM_SPACING_H*(item_index-1)+self.text_pos
	local ypos = ypos+self.OPTION_PADDING_T+self.OPTION_SPACING_V*(draw_index-1)
	
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
			fb.bb:paintRect(xpos, ypos+5, text_len, 3,(option_index == self.current_option) and 15 or 6)
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
		if KOPTOptions[i].show then
			self:drawOptionName(xpos, ypos, i, KOPTOptions[i].option_text, name_font, redraw)
			for j=1,#KOPTOptions[i].items_text do
				self:drawOptionItem(xpos, ypos, i, j, KOPTOptions[i].items_text[j], item_font, redraw, refresh)
			end
			KOPTOptions[i].text_dirty = false
		end
	end
end

function KOPTConfig:makeDefault(configurable)
	local draw_index = 1
	self.HEIGHT = self.OPTION_PADDING_T
	self.current_option = 1
	for i=1,#KOPTOptions do
		-- update draw index of each option in run time
		if KOPTOptions[i].show then
			KOPTOptions[i].draw_index = draw_index
			draw_index = draw_index + 1
		end
		-- update window height
		if KOPTOptions[i].show then
			self.HEIGHT = self.HEIGHT + self.OPTION_SPACING_V
		end
		-- make each option and marker dirty
		KOPTOptions[i].text_dirty = true
		for j=1,#KOPTOptions[i].items_text do
			KOPTOptions[i].marker_dirty[j] = true
		end
		-- make current index according to configurable table
		local option = KOPTOptions[i].name
		local val = configurable[option]
		local min_diff = math.abs(val - KOPTOptions[i].values[1])
		KOPTOptions[i].current_item = 1
		for index, val_ in pairs(KOPTOptions[i].values) do
			if val == val_ then
				KOPTOptions[i].current_item = index
				break
			else
				diff = math.abs(val - val_)
				if diff <= min_diff then
					min_diff = diff
					KOPTOptions[i].current_item = index
				end
			end
		end -- for index
	end -- for i
end

function KOPTConfig:reconfigure(configurable)
	for i=1,#KOPTOptions do
		option = KOPTOptions[i].name
		configurable[option] = KOPTOptions[i].values[KOPTOptions[i].current_item]
	end
end

function KOPTConfig:config(reader)
	self.koptreader = reader
	
	self:makeDefault(self.koptreader.configurable)
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
		self:reconfigure(self.koptreader.configurable)
		
		if self.config_change and self.confirm_change then
			self.koptreader:redrawWithoutPrecache()
			self:drawBox(topleft_x, topleft_y, width, height, 3, 15)
			self:drawOptions(topleft_x, topleft_y, name_font, item_font, true, false)
			fb:refresh(1, topleft_x, topleft_y, width, height)
			self.config_change = false
			self.confirm_change = false
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
			repeat
				self.current_option = (self.current_option + #KOPTOptions + 1)%#KOPTOptions
				self.current_option = (self.current_option == 0) and #KOPTOptions or self.current_option
			until KOPTOptions[self.current_option].show
			
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
			repeat
				self.current_option = (self.current_option + #KOPTOptions - 1)%#KOPTOptions
				self.current_option = (self.current_option == 0) and #KOPTOptions or self.current_option
			until KOPTOptions[self.current_option].show
			
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
			self.config_change = true
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
			self.config_change = true
		end
	)
	self.commands:add({KEY_F,KEY_AA,KEY_BACK}, nil, "Back",
		"back",
		function(self)
			return "break"
		end
	)
	self.commands:add(KEY_FW_PRESS, nil, "joypad press",
		"preview",
		function(self)
			self.confirm_change = true
			if KOPTOptions[self.current_option].name == "trim_page" then
				local option = KOPTOptions[self.current_option]
				local trim_mode = option.current_item
				if option.items_text[trim_mode] == 'manual' then
					self:modBBox(self.koptreader)
					self.config_change = true
				end
			end
		end
	)
end

function KOPTConfig:modBBox(koptreader)
	-- save variables that will be changed in modBBox
	local orig_globalzoom = koptreader.globalzoom
	local orig_dest_x = koptreader.dest_x
	local orig_dest_y = koptreader.dest_y
	local orig_offset_x = koptreader.offset_x
	local orig_offset_y = koptreader.offset_y
	
	koptreader:showOrigPage()
	
	koptreader:modBBox()
	
	-- restore variables changed in modBBox
	koptreader.globalzoom = orig_globalzoom
	koptreader.dest_x = orig_dest_x
	koptreader.dest_y = orig_dest_y
	koptreader.offset_x = orig_offset_x
	koptreader.offset_y = orig_offset_y
	
end
