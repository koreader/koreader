require "font"
require "keys"
require "settings"

KOPTOptions =  {
	{
	name="font_size",
	option_text="",
	items_text={"Aa","Aa","Aa","Aa","Aa","Aa","Aa","Aa","Aa","Aa"},
	text_font_size={14,16,20,23,26,30,34,38,42,46},
	default_item=6,
	current_item=6,
	text_dirty=true,
	marker_dirty={true, true, true, true, true, true, true, true, true, true},
	value={0.2, 0.3, 0.4, 0.6, 0.8, 1.0, 1.2, 1.6, 2.2, 2.8},
	show = true,
	draw_index = nil,},
	{
	name="text_wrap",
	option_text="Reflow",
	items_text={"on","off"},
	default_item=1,
	current_item=1,
	text_dirty=true,
	marker_dirty={true, true},
	value={1, 0},
	show = true,
	draw_index = nil,},
	{
	name="trim_page",
	option_text="Trim Page",
	items_text={"auto","manual"},
	default_item=1,
	current_item=1,
	text_dirty=true,
	marker_dirty={true, true},
	value={1, 0},
	show = true,
	draw_index = nil,},
	{
	name="detect_indent",
	option_text="Indentation",
	items_text={"enable","disable"},
	default_item=1,
	current_item=1,
	text_dirty=true,
	marker_dirty={true, true},
	value={1, 0},
	show = false,
	draw_index = nil,},
	{
	name="defect_size",
	option_text="Defect Size",
	items_text={"small","medium","large"},
	default_item=2,
	current_item=2,
	text_dirty=true,
	marker_dirty={true, true, true},
	value={0.5, 1.0, 2.0},
	show = true,
	draw_index = nil,},
	{
	name="page_margin",
	option_text="Page Margin",
	items_text={"small","medium","large"},
	default_item=2,
	current_item=2,
	text_dirty=true,
	marker_dirty={true, true, true},
	value={0.02, 0.06, 0.10},
	show = true,
	draw_index = nil,},
	{
	name="line_spacing",
	option_text="Line Spacing",
	items_text={"small","medium","large"},
	default_item=2,
	current_item=2,
	text_dirty=true,
	marker_dirty={true, true, true},
	value={1.0, 1.2, 1.4},
	show = true,
	draw_index = nil,},
	{
	name="word_spacing",
	option_text="Word Spacing",
	items_text={"small","medium","large"},
	default_item=2,
	current_item=2,
	text_dirty=true,
	marker_dirty={true, true, true, true},
	value={0.1, 0.375, 0.5},
	show = true,
	draw_index = nil,},
	{
	name="multi_threads",
	option_text="Multi Threads",
	items_text={"on","off"},
	default_item=2,
	current_item=2,
	text_dirty=true,
	marker_dirty={true, true},
	value={1, 0},
	show = true,
	draw_index = nil,},
	{
	name="quality",
	option_text="Render Quality",
	items_text={"low","medium","high"},
	default_item=3,
	current_item=3,
	text_dirty=true,
	marker_dirty={true, true, true},
	value={0.5, 0.8, 1.0},
	show = true,
	draw_index = nil,},
	{
	name="auto_straighten",
	option_text="Auto Straighten",
	items_text={"0","5","10"},
	default_item=1,
	current_item=1,
	text_dirty=true,
	marker_dirty={true, true, true},
	value={0, 5, 10},
	show = true,
	draw_index = nil,},
	{
	name="justification",
	option_text="Justification",
	items_text={"auto","left","center","right","full"},
	default_item=1,
	current_item=1,
	text_dirty=true,
	marker_dirty={true, true, true, true, true},
	value={-1,0,1,2,3},
	show = true,
	draw_index = nil,},
	{
	name="max_columns",
	option_text="Columns",
	items_text={"1","2","3","4"},
	default_item=2,
	current_item=2,
	text_dirty=true,
	marker_dirty={true, true, true, true},
	value={1,2,3,4},
	show = true,
	draw_index = nil,},
	{
	name="contrast",
	option_text="Contrast",
	items_text={"lightest","lighter","default","darker","darkest"},
	default_item=3,
	current_item=3,
	text_dirty=true,
	marker_dirty={true, true, true, true, true},
	value={2.0, 1.5, 1.0, 0.5, 0.2},
	show = true,
	draw_index = nil,},
	{
	name="screen_rotation",
	option_text="Screen Rotation",
	items_text={"0","90","180","270"},
	default_item=1,
	current_item=1,
	text_dirty=true,
	marker_dirty={true, true, true, true},
	value={0, 90, 180, 270},
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
		local value = configurable[option]
		local min_diff = math.abs(value - KOPTOptions[i].value[1])
		KOPTOptions[i].current_item = KOPTOptions[i].default_item
		for index, val in pairs(KOPTOptions[i].value) do
			if val == value then
				KOPTOptions[i].current_item = index
				break
			else
				diff = math.abs(value - val)
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
		configurable[option] = KOPTOptions[i].value[KOPTOptions[i].current_item]
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
	
	local bbox = koptreader.cur_bbox
	Debug("bbox", bbox)
	x,y,w,h = koptreader:getRectInScreen( bbox["x0"], bbox["y0"], bbox["x1"], bbox["y1"] )
	Debug("getRectInScreen",x,y,w,h)

	local new_bbox = bbox
	local x_s, y_s = x,y
	local running_corner = "top-left"

	Screen:saveCurrentBB()

	fb.bb:invertRect( 0,y_s, G_width,1 )
	fb.bb:invertRect( x_s,0, 1,G_height )
	InfoMessage:inform(running_corner.." bbox ", DINFO_TIMEOUT_FAST, 1, MSG_WARN,
		running_corner.." bounding box")
	fb:refresh(1)

	local last_direction = { x = 0, y = 0 }

	while running_corner do
		local ev = input.saveWaitForEvent()
		Debug("ev",ev)
		ev.code = adjustKeyEvents(ev)

		if ev.type == EV_KEY and ev.value ~= EVENT_VALUE_KEY_RELEASE then

			fb.bb:invertRect( 0,y_s, G_width,1 )
			fb.bb:invertRect( x_s,0, 1,G_height )

			local step   = 10
			local factor = 1

			local x_direction, y_direction = 0,0
			if ev.code == KEY_FW_LEFT then
				x_direction = -1
			elseif ev.code == KEY_FW_RIGHT then
				x_direction =  1
			elseif ev.code == KEY_FW_UP then
				y_direction = -1
			elseif ev.code == KEY_FW_DOWN then
				y_direction =  1
			elseif ev.code == KEY_FW_PRESS then
				local p_x,p_y = koptreader:screenToPageTransform(x_s,y_s)
				if running_corner == "top-left" then
					new_bbox["x0"] = p_x
					new_bbox["y0"] = p_y
					Debug("change top-left", bbox, "to", new_bbox)
					running_corner = "bottom-right"
					Screen:restoreFromSavedBB()
					InfoMessage:inform(running_corner.." bbox ", DINFO_TIMEOUT_FAST, 1, MSG_WARN,
						running_corner.." bounding box")
					fb:refresh(1)
					x_s = x+w
					y_s = y+h
				else
					new_bbox["x1"] = p_x
					new_bbox["y1"] = p_y
					running_corner = false
				end
			elseif ev.code >= KEY_Q and ev.code <= KEY_P then
				factor = ev.code - KEY_Q + 1
				x_direction = last_direction["x"]
				y_direction = last_direction["y"]
				Debug("factor",factor,"deltas",x_direction,y_direction)
			elseif ev.code >= KEY_A and ev.code <= KEY_L then
				factor = ev.code - KEY_A + 11
				x_direction = last_direction["x"]
				y_direction = last_direction["y"]
			elseif ev.code >= KEY_Z and ev.code <= KEY_M then
				factor = ev.code - KEY_Z + 20
				x_direction = last_direction["x"]
				y_direction = last_direction["y"]
			elseif ev.code == KEY_BACK then
				running_corner = false
			end

			Debug("factor",factor,"deltas",x_direction,y_direction)

			if running_corner then
				local x_o = x_direction * step * factor
				local y_o = y_direction * step * factor
				Debug("move slider",x_o,y_o)
				if x_s+x_o >= 0 and x_s+x_o <= G_width  then x_s = x_s + x_o end
				if y_s+y_o >= 0 and y_s+y_o <= G_height then y_s = y_s + y_o end

				if x_direction ~= 0 or y_direction ~= 0 then
					Screen:restoreFromSavedBB()
				end

				fb.bb:invertRect( 0,y_s, G_width,1 )
				fb.bb:invertRect( x_s,0, 1,G_height )

				if x_direction or y_direction then
					last_direction = { x = x_direction, y = y_direction }
					Debug("last_direction",last_direction)

					-- FIXME partial duplicate of SelectMenu.item_shortcuts
					local keys = {
						"Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P",
						"A", "S", "D", "F", "G", "H", "J", "K", "L",
						"Z", "X", "C", "V", "B", "N", "M",
					}

					local max = 0
					if x_direction == 1 then
						max = G_width - x_s
					elseif x_direction == -1 then
						max = x_s
					elseif y_direction == 1 then
						max = G_height - y_s
					elseif y_direction == -1 then
						max = y_s
					else
						Debug("ERROR: unknown direction!")
					end

					max = max / step
					if max > #keys then max = #keys end

					local face = Font:getFace("hpkfont", 11)

					for i = 1, max, 1 do
						local key = keys[i]
						local tick = i * step * x_direction
						if x_direction ~= 0 then
							local tick = i * step * x_direction
							Debug("x tick",i,tick,key)
							if running_corner == "top-left" then -- ticks must be inside page
								fb.bb:invertRect(     x_s+tick, y_s, 1, math.abs(tick))
							else
								fb.bb:invertRect(     x_s+tick, y_s-math.abs(tick), 1, math.abs(tick))
							end
							if x_direction < 0 then tick = tick - step end
							tick = tick - step * x_direction / 2
							renderUtf8Text(fb.bb, x_s+tick+2, y_s+4, face, key)
						else
							local tick = i * step * y_direction
							Debug("y tick",i,tick,key)
							if running_corner == "top-left" then -- ticks must be inside page
								fb.bb:invertRect(     x_s, y_s+tick, math.abs(tick),1)
							else
								fb.bb:invertRect(     x_s-math.abs(tick), y_s+tick, math.abs(tick),1)
							end
							if y_direction > 0 then tick = tick + step end
							tick = tick - step * y_direction / 2
							renderUtf8Text(fb.bb, x_s-3, y_s+tick-1, face, key)
						end
					end
				end
				fb:refresh(1)
			end
		end

	end

	koptreader.bbox[koptreader.pageno] = new_bbox
	koptreader.bbox[koptreader:oddEven(koptreader.pageno)] = new_bbox
	koptreader.bbox.enabled = true
	Debug("crop bbox", bbox, "to", new_bbox)

	Screen:restoreFromSavedBB()
	x,y,w,h = koptreader:getRectInScreen( new_bbox["x0"], new_bbox["y0"], new_bbox["x1"], new_bbox["y1"] )
	fb.bb:invertRect( x,y, w,h )
	--fb.bb:invertRect( x+1,y+1, w-2,h-2 ) -- just border?
	InfoMessage:inform("New page bbox ", DINFO_TIMEOUT_SLOW, 1, MSG_WARN, "New page bounding box")
	
	-- restore variables changed in modBBox
	koptreader.globalzoom = orig_globalzoom
	koptreader.dest_x = orig_dest_x
	koptreader.dest_y = orig_dest_y
	koptreader.offset_x = orig_offset_x
	koptreader.offset_y = orig_offset_y
	
end
