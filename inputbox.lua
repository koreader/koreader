require "font"
require "rendertext"
require "keys"
require "graphics"

----------------------------------------------------
-- General inputbox
----------------------------------------------------

InputBox = {
	-- Class vars:
	h = 100,
	input_slot_w = nil,
	input_start_x = nil,
	input_start_y = nil,
	input_cur_x = nil, -- points to the start of next input pos

	input_bg = 0,
	input_string = "",
	cursor = nil,

	-- font for displaying input content
	-- we have to use mono here for better distance controlling
	face = Font:getFace("infont", 25),
	fheight = 25,
	fwidth = 15,
	commands = nil,
	initialized = false,
	
	-- NuPogodi, 25.05.12: for full UTF8 support
	vk_bg = 3,
	charlist = {}, -- table to store input string
	charpos = 1,
	INPUT_KEYS = {}, -- table to store layouts
	-- values to control layouts: min & max
	min_layout = 2,
	max_layout = 9,
	-- default layout = 2, i.e. shiftmode = symbolmode = utf8mode = false
	layout = 2,
	-- now bits to toggle the layout mode
	shiftmode = false,	-- toggle chars <> capitals,	lowest bit in (layout-2)
	symbolmode = false,	-- toggle chars <> symbols,		middle bit in (layout-2)
	utf8mode = false,	-- toggle english <> national,	highest bit in (layout-2)
}

function InputBox:new(o)
	o = o or {}
	setmetatable(o, self)
	self.__index = self
	return o
end

function InputBox:refreshText()
	-- clear previous painted text
	fb.bb:paintRect(self.input_start_x-5, self.input_start_y-19, self.input_slot_w, self.fheight, self.input_bg)
	-- paint new text
	renderUtf8Text(fb.bb, self.input_start_x, self.input_start_y, self.face, self.input_string, true)
end

function InputBox:addChar(char)
	self.cursor:clear()
	-- draw new text
	local cur_index = (self.cursor.x_pos + 3 - self.input_start_x) / self.fwidth
	table.insert(self.charlist, self.charpos, char)
	self.charpos = self.charpos + 1
	self.input_string = self:CharlistToString()
	self:refreshText()
	self.input_cur_x = self.input_cur_x + self.fwidth
	-- draw new cursor
	self.cursor:moveHorizontal(self.fwidth)
	self.cursor:draw()
	fb:refresh(1, self.input_start_x-5, self.input_start_y-25, self.input_slot_w, self.h-25)
end

function InputBox:delChar()
	if self.input_start_x == self.input_cur_x then return end
	local cur_index = (self.cursor.x_pos + 3 - self.input_start_x) / self.fwidth
	if cur_index == 0 then return end
	self.cursor:clear()
	-- draw new text
	self.charpos = self.charpos - 1
	table.remove(self.charlist, self.charpos)
	self.input_string = self:CharlistToString()
	self:refreshText()
	self.input_cur_x = self.input_cur_x - self.fwidth
	-- fill last character with blank rectangle
	fb.bb:paintRect(self.input_cur_x, self.input_start_y-19, self.fwidth, self.fheight, self.input_bg)
	fb:refresh(1, self.input_cur_x, self.input_start_y-19, self.fwidth, self.fheight)
	-- draw new cursor
	self.cursor:moveHorizontal(-self.fwidth)
	self.cursor:draw()
	fb:refresh(1, self.input_start_x-5, self.input_start_y-25, self.input_slot_w, self.h-25)
end

function InputBox:clearText()
	self.cursor:clear()
	self.input_string = ""
	self.charlist = {}
	self.charpos = 1
	self:refreshText()
	self.cursor.x_pos = self.input_start_x - 3
	self.cursor:draw()
	fb:refresh(1, self.input_start_x-5, self.input_start_y-25, self.input_slot_w, self.h-25)
end

function InputBox:drawBox(ypos, w, h, title)
	-- draw input border
	local r = 6 -- round corners
	fb.bb:paintRect(1, ypos+r, w, h - r, self.vk_bg)
	blitbuffer.paintBorder(fb.bb, 1, ypos, fb.bb:getWidth() - 2, r, r, self.vk_bg, r)
	-- draw input title
	self.input_start_y = ypos + 37
	-- draw the box title > estimate the start point for future text & the text slot width
	self.input_start_x = 25 + renderUtf8Text(fb.bb, 15, self.input_start_y, self.face, title, true)
	self.input_slot_w = fb.bb:getWidth() - self.input_start_x - 5
	-- draw input slot
	fb.bb:paintRect(self.input_start_x - 5, ypos + 10, self.input_slot_w, h - 20, self.input_bg)
end

----------------------------------------------------------------------
-- InputBox:input()
--
-- @title: input prompt for the box
-- @d_text: default to nil (used to set default text in input slot)
-- @is_hint: if this arg is true, default text will be used as hint
-- message for input
----------------------------------------------------------------------
function InputBox:input(ypos, height, title, d_text, is_hint)
	-- To avoid confusion with old ypos & height parameters, I'd better define
	-- my own position, at the bottom screen edge (NuPogodi, 26.05.12)
	ypos = fb.bb:getHeight() - 165
	-- at first, draw titled box and content
	local h, w = 55, fb.bb:getWidth() - 2
	self:drawBox(ypos, w, h, title)
	-- do some initilization
	self.ypos = ypos
	self.h = 100
	self.input_cur_x = self.input_start_x
	self:addAllCommands()
	self.cursor = Cursor:new {
		x_pos = self.input_start_x - 3,
		y_pos = ypos + 13,
		h = 30,
	}
	if d_text then
		if is_hint then
		-- print hint text
			fb.bb:paintRect(self.input_start_x-5, self.input_start_y-19, self.input_slot_w, self.fheight, self.input_bg)
			renderUtf8Text(fb.bb, self.input_start_x+5, self.input_start_y, self.face, d_text, 0)
			fb.bb:dimRect(self.input_start_x-5, self.input_start_y-19, self.input_slot_w, self.fheight, self.input_bg)
		else
			self.input_cur_x = self.input_cur_x + (self.fwidth * #self.charlist)
			self.cursor.x_pos = self.cursor.x_pos + (self.fwidth * #self.charlist)
			self:refreshText()
		end
	end
	self.cursor:draw()
	fb:refresh(1, 1, ypos, w, h)
	while true do
		local ev = input.saveWaitForEvent()
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
				break
			end
		end -- if
	end -- while
	local return_str = self.input_string
	self.input_string = ""
	self.charlist = {}
	self.charpos = 1
	return return_str
end

function InputBox:setLayoutsTable()
	-- trying to read the layout from the user-defined file "mykeyboard.lua"
	local ok, stored = pcall(dofile,"./mykeyboard.lua")
	if ok then
		self.INPUT_KEYS = stored
	else	-- if an error happens, we use the default layout
		self.INPUT_KEYS = {
			{ KEY_Q,	"Q",	"q",	"1",	"!",		"Я",	"я",	"1",	"!", },
			{ KEY_W,	"W",	"w",	"2",	"?",		"Ж",	"ж",	"2",	"?", },
			{ KEY_E,	"E",	"e",	"3",	"#",		"Е",	"е",	"3",	"«", },
			{ KEY_R,	"R",	"r",	"4",	"@",		"Р",	"р",	"4",	"»", },
			{ KEY_T,	"T",	"t",	"5",	"%",		"Т",	"т",	"5",	":", },
			{ KEY_Y,	"Y",	"y",	"6",	"‰",		"Ы",	"ы",	"6",	";", },
			{ KEY_U,	"U",	"u",	"7",	"\'",		"У",	"у",	"7",	"~", },
			{ KEY_I,	"I",	"i",	"8",	"`",		"И",	"и",	"8",	"(",},
			{ KEY_O,	"O",	"o",	"9",	":",		"О",	"о",	"9",	")",},
			{ KEY_P,	"P",	"p",	"0",	";",		"П",	"п",	"0",	"=", },
			-- middle raw
			{ KEY_A,	"A",	"a",	"+",	"…",		"А",	"а",	"Ш",	"ш", },
			{ KEY_S,	"S",	"s",	"-",	"_",		"С",	"с",	"Ѕ",	"ѕ", },
			{ KEY_D,	"D",	"d",	"*",	"¦",		"Д",	"д",	"Э",	"э", },
			{ KEY_F,	"F",	"f",	"/",	"|",		"Ф",	"ф",	"Ю",	"ю", },
			{ KEY_G,	"G",	"g",	"\\",	"„",		"Г",	"г",	"Ґ",	"ґ", },
			{ KEY_H,	"H",	"h",	"=",	"“",		"Ч",	"ч",	"Ј",	"ј", },
			{ KEY_J,	"J",	"j",	"<",	"”",		"Й",	"й",	"І",	"і", },
			{ KEY_K,	"K",	"k",	"ˆ",	"\"",		"К",	"к",	"Ќ",	"ќ", },
			{ KEY_L,	"L",	"l",	">",	"~",		"Л",	"л",	"Љ",	"љ", },
			-- lowest raw
			{ KEY_Z,	"Z",	"z",	"(",	"$",		"З",	"з",	"Щ",	"щ", },
			{ KEY_X,	"X",	"x",	")",	"€",		"Х",	"х",	"№",	"@", },
			{ KEY_C,	"C",	"c",	"{",	"¥",		"Ц",	"ц",	"Џ",	"џ", },
			{ KEY_V,	"V",	"v",	"}",	"£",		"В",	"в",	"Ў",	"ў", },
			{ KEY_B,	"B",	"b",	"[",	"‚",		"Б",	"б",	"Ћ",	"ћ", },
			{ KEY_N,	"N",	"n",	"]",	"‘",		"Н",	"н",	"Њ",	"њ", },
			{ KEY_M,	"M",	"m",	"&",	"’",		"М",	"м",	"Ї",	"ї", },
			{ KEY_DOT,	".",	",",	".",	",",		".",	",",	"Є",	"є", },
			-- Let us make key 'Space' the same for all layouts
			{ KEY_SPACE," ",	" ",	" ",	" ",		" ",	" ",	" ",	" ", },
			-- Simultaneous pressing Alt + Q..P should also work properly
			{ KEY_1,	"1",	" ",	" ",	" ",		"1",	" ",	" ",	" ", },
			{ KEY_2,	"2",	" ",	" ",	" ",		"2",	" ",	" ",	" ", },
			{ KEY_3,	"3",	" ",	" ",	" ",		"3",	" ",	" ",	" ", },
			{ KEY_4,	"4",	" ",	" ",	" ",		"4",	" ",	" ",	" ", },
			{ KEY_5,	"5",	" ",	" ",	" ",		"5",	" ",	" ",	" ", },
			{ KEY_6,	"6",	" ",	" ",	" ",		"6",	" ",	" ",	" ", },
			{ KEY_7,	"7",	" ",	" ",	" ",		"7",	" ",	" ",	" ", },
			{ KEY_8,	"8",	" ",	" ",	" ",		"8",	" ",	" ",	" ", },
			{ KEY_9,	"9",	" ",	" ",	" ",		"9",	" ",	" ",	" ", },
			{ KEY_0,	"0",	" ",	" ",	" ",		"0",	" ",	" ",	" ", },
			-- DXG keys
			{ KEY_SLASH,"/",	"\\",	"/",	"\\",		"/",	"\\",	"/",	"\\", },
		}
	end -- if ok
end

function InputBox:DrawVKey(key,x,y,face,rx,ry,t,c)
	blitbuffer.paintBorder(fb.bb, x-11, y-ry-8, rx, ry, t, c, ry)
	renderUtf8Text(fb.bb, x, y, face, key, true)
end

-- this function is designed for K3 keyboard, portrait mode
-- TODO: support for other Kindle models & orientations?

function InputBox:DrawVirtualKeyboard()
	local vy = fb.bb:getHeight()-15
	-- dx, dy = xy-distance between the button rows
	-- lx - position of left button column
	-- r, c, t = radius, color and thickness of circles around chars
	-- h = y-correction to adjust cicles & chars
	local dx, dy, lx, r, c, bg, t = 51, 36, 20, 17, 6, self.vk_bg, 2

	fb.bb:paintRect(1, fb.bb:getHeight()-120, fb.bb:getWidth()-2, 120, bg)
	-- font to draw characters - MUST have UTF8-support
	local vkfont = Font:getFace("infont", 22)
	for k,v in ipairs(self.INPUT_KEYS) do
		if v[1] >= KEY_Q and v[1] <= KEY_P then	-- upper raw
			self:DrawVKey(v[self.layout], lx+(v[1]-KEY_Q)*dx, vy-2*dy, vkfont, r, r, t, c)
		elseif v[1] >= KEY_A and v[1] <= KEY_L then	-- middle raw
			self:DrawVKey(v[self.layout], lx+(v[1]-KEY_A)*dx, vy-dy, vkfont, r, r, t, c)
		elseif v[1] >= KEY_Z and v[1] <= KEY_M then	-- lower raw
			self:DrawVKey(v[self.layout], lx+(v[1]-KEY_Z)*dx, vy, vkfont, r, r, t, c)
		elseif v[1] == KEY_DOT then
			self:DrawVKey(v[self.layout], lx + 7*dx, vy, vkfont, r, r, t, c)
		end
	end
	-- the rest symbols (manually)
	local smfont = Font:getFace("infont", 14)
	-- Del
	blitbuffer.paintBorder(fb.bb, lx+9*dx-10, vy-dy-r-8, r, r, t, c, r)
	renderUtf8Text(fb.bb, lx-5+9*dx, vy-dy-3, smfont, "Del", true)
	-- Sym
	blitbuffer.paintBorder(fb.bb, lx+8*dx-10, vy-r-8, r, r, t + (r-t)*number(self.symbolmode), c, r)
	renderUtf8Text(fb.bb, lx-5+8*dx, vy-3, smfont, "Sym", true)
	-- Enter
	blitbuffer.paintBorder(fb.bb, lx+9*dx-10, vy-r-8, r, r, t, c, r)
	renderUtf8Text(fb.bb, lx+9*dx, vy-2, vkfont, "«", true)
	-- Menu
	blitbuffer.paintBorder(fb.bb, lx+10*dx-8, vy-2*dy-r-8, r+50, r, t+(r-t)*number(self.utf8mode), c, r)
	renderUtf8Text(fb.bb, lx+10*dx+11, vy-2*dy-3, smfont, "Menu", true)
	-- fiveway
	local h=dy+2*r-2
	blitbuffer.paintBorder(fb.bb, lx+10*dx-8, vy-dy-r-6, h, h, 9, c, r)
	renderUtf8Text(fb.bb, lx+10*dx+22, vy-20, smfont, (self.layout-1), true)
	fb:refresh(1, 1, fb.bb:getHeight()-120, fb.bb:getWidth()-2, 120)
end

function InputBox:addCharCommands(layout)
	-- at first, let's define self.layout and extract separate bits as layout modes
	if layout then
		-- to be sure layout is selected properly
		layout = math.max(layout, self.min_layout)
		layout = math.min(layout, self.max_layout)
		self.layout = layout
		-- fill the layout modes
		layout = (layout - 2) % 4
		self.shiftmode  = (layout == 1 or layout == 3)
		self.symbolmode = (layout == 2 or layout == 3)
		self.utf8mode   = (self.layout > 5)
	else	-- or, without input parameter, restore layout from current layout modes
		self.layout = 2 + number(self.shiftmode) + 2 * number(self.symbolmode) + 4 * number(self.utf8mode)
	end
	-- adding the commands
	for k,v in ipairs(self.INPUT_KEYS) do
		-- seems to work without removing old commands,
		self.commands:del(v[1], nil, "")
		-- just redefining existing ones
		self.commands:add(v[1], nil, "", "input "..v[self.layout],
			function(self)
				self:addChar(v[self.layout])
			end
		)
	end
	self:DrawVirtualKeyboard()
end

function InputBox:CharlistToString()
	local s, i = ""
	for i=1, #self.charlist do
		s = s .. self.charlist[i]
	end
	return s
end

function number(bool)
	return bool and 1 or 0
end

function InputBox:addAllCommands()
	-- we only initialize once
	if self.commands then
		self:DrawVirtualKeyboard()
		return
	end
	self:setLayoutsTable()
	self.commands = Commands:new{}
	-- adding command to enter character commands
	self:addCharCommands()
	-- adding the rest commands (independent of the selected layout)
	self.commands:add(KEY_FW_LEFT, nil, "",
		"move cursor left",
		function(self)
			if (self.cursor.x_pos + 3) > self.input_start_x then
				self.cursor:moveHorizontalAndDraw(-self.fwidth)
				self.charpos = self.charpos - 1
				fb:refresh(1, self.input_start_x-5, self.ypos, self.input_slot_w, self.h)
			end
		end
	)
	self.commands:add(KEY_FW_RIGHT, nil, "",
		"move cursor right",
		function(self)
			if (self.cursor.x_pos + 3) < self.input_cur_x then
				self.cursor:moveHorizontalAndDraw(self.fwidth)
				self.charpos = self.charpos + 1
				fb:refresh(1, self.input_start_x-5, self.ypos, self.input_slot_w, self.h)
			end
		end
	)
	self.commands:add({KEY_ENTER, KEY_FW_PRESS}, nil, "",
		"submit input content",
		function(self)
			if self.input_string == "" then
				self.input_string = nil
			end
			return "break"
		end
	)
	self.commands:add(KEY_DEL, nil, "",
		"delete one character",
		function(self)
			self:delChar()
		end
	)
	self.commands:add(KEY_DEL, MOD_SHIFT, "",
		"empty inputbox",
		function(self)
			self:clearText()
		end
	)
	self.commands:add({KEY_BACK, KEY_HOME}, nil, "",
		"cancel inputbox",
		function(self)
			self.input_string = nil
			return "break"
		end
	)
	self.commands:add(KEY_P, MOD_SHIFT, "P",
		"make screenshot",
		function(self)
			Screen:screenshot()
		end
	)
	self.commands:add(KEY_FW_DOWN, nil, "joypad down",
		"goto next keyboard layout",
		function(self)
			if self.layout == self.max_layout then self:addCharCommands(self.min_layout)
			else self:addCharCommands(self.layout+1) end
		end
	)
	self.commands:add(KEY_FW_UP, nil, "joypad up",
		"goto previous keyboard layout",
		function(self)
			if self.layout == self.min_layout then self:addCharCommands(self.max_layout)
			else self:addCharCommands(self.layout-1) end
		end
	)
	self.commands:add(KEY_AA, nil, "Aa",
		"toggle layout: chars <> CHARS",
		function(self)
			self.shiftmode = not self.shiftmode
			self:addCharCommands()
		end
	)
	self.commands:add(KEY_SYM, nil, "Sym",
		"toggle layout: chars <> symbols",
		function(self)
			self.symbolmode = not self.symbolmode
			self:addCharCommands()
		end
	)
	self.commands:add(KEY_MENU, nil, "Menu",
		"toggle layout: english <> national",
		function(self)
			self.utf8mode = not self.utf8mode
			self:addCharCommands()
		end
	)
end

----------------------------------------------------
-- Inputbox for numbers only
-- Designed by eLiNK
----------------------------------------------------

NumInputBox = InputBox:new{
	symbolmode = true,
	layout = 4,
	charlist = {}
}
