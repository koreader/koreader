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

	vk_bg = 3,
	charlist = {}, -- table to store input string
	charpos = 1,
	INPUT_KEYS = {}, -- table to store layouts
	-- values to control layouts: min & max
	min_layout = 2,
	max_layout = 9,
	layout = 3,
	-- now bits to toggle the layout mode
	shiftmode = true,	-- toggle chars <-> capitals,	lowest bit in (layout-2)
	symbolmode = false,	-- toggle chars <-> symbols,	middle bit in (layout-2)
	utf8mode = false,	-- toggle english <-> national,	highest bit in (layout-2)
	calcmode = false,	-- toggle calculator mode
	calcfunctions = nil, -- math functions for calculator helppage
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
	-- my own position, at the bottom screen edge
	ypos = fb.bb:getHeight() - 165
	-- some corrections for calculator mode
	if self.calcmode then
		self:setCalcMode()
	end

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
			-- add text to input_string
			self:StringToCharlist(d_text)
			self.input_cur_x = self.input_cur_x + (self.fwidth * #self.charlist)
			self.cursor.x_pos = self.cursor.x_pos + (self.fwidth * #self.charlist)
			self:refreshText()
		end
	end
	self.cursor:draw()
	fb:refresh(1, 1, ypos, w, h)

	local ev, keydef, command, ret_code
	while true do
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
				break
			end
		end -- if
	end -- while

	local output = self.input_string
	self.input_string = ""
	self.charlist = {}
	self.charpos = 1
	return output
end

function InputBox:setLayoutsTable()
	-- trying to read the layout from the user-defined file
	local ok, stored = pcall(dofile, lfs.currentdir() .. "/mykeyboard.lua")
	if ok then
		self.INPUT_KEYS = stored
	else	-- if an error happens, we use the default layout
		self.INPUT_KEYS = {
			{ KEY_Q,	"Q",	"q",	"1",	"!",		"Я",	"я",	"1",	"!", },
			{ KEY_W,	"W",	"w",	"2",	"?",		"Ж",	"ж",	"2",	"?", },
			{ KEY_E,	"E",	"e",	"3",	"|",		"Е",	"е",	"3",	"«", },
			{ KEY_R,	"R",	"r",	"4",	"#",		"Р",	"р",	"4",	"»", },
			{ KEY_T,	"T",	"t",	"5",	"@",		"Т",	"т",	"5",	":", },
			{ KEY_Y,	"Y",	"y",	"6",	"‰",		"Ы",	"ы",	"6",	";", },
			{ KEY_U,	"U",	"u",	"7",	"'",		"У",	"у",	"7",	"~", },
			{ KEY_I,	"I",	"i",	"8",	"`",		"И",	"и",	"8",	"(",},
			{ KEY_O,	"O",	"o",	"9",	":",		"О",	"о",	"9",	")",},
			{ KEY_P,	"P",	"p",	"0",	";",		"П",	"п",	"0",	"=", },
			-- middle raw
			{ KEY_A,	"A",	"a",	"+",	"…",		"А",	"а",	"Ш",	"ш", },
			{ KEY_S,	"S",	"s",	"-",	"_",		"С",	"с",	"Ѕ",	"ѕ", },
			{ KEY_D,	"D",	"d",	"*",	"=",		"Д",	"д",	"Э",	"э", },
			{ KEY_F,	"F",	"f",	"/",	"\\",		"Ф",	"ф",	"Ю",	"ю", },
			{ KEY_G,	"G",	"g",	"%",	"„",		"Г",	"г",	"Ґ",	"ґ", },
			{ KEY_H,	"H",	"h",	"^",	"“",		"Ч",	"ч",	"Ј",	"ј", },
			{ KEY_J,	"J",	"j",	"<",	"”",		"Й",	"й",	"І",	"і", },
			{ KEY_K,	"K",	"k",	"=",	"\"",		"К",	"к",	"Ќ",	"ќ", },
			{ KEY_L,	"L",	"l",	">",	"~",		"Л",	"л",	"Љ",	"љ", },
			-- lowest raw
			{ KEY_Z,	"Z",	"z",	"(",	"$",		"З",	"з",	"Щ",	"щ", },
			{ KEY_X,	"X",	"x",	")",	"€",		"Х",	"х",	"№",	"@", },
			{ KEY_C,	"C",	"c",	"&",	"¥",		"Ц",	"ц",	"Џ",	"џ", },
			{ KEY_V,	"V",	"v",	":",	"£",		"В",	"в",	"Ў",	"ў", },
			{ KEY_B,	"B",	"b",	"π",	"‚",		"Б",	"б",	"Ћ",	"ћ", },
			{ KEY_N,	"N",	"n",	"е",	"‘",		"Н",	"н",	"Њ",	"њ", },
			{ KEY_M,	"M",	"m",	"~",	"’",		"М",	"м",	"Ї",	"ї", },
			{ KEY_DOT,	",",	".",	".",	",",		",",	".",	"Є",	"є", },
			-- Let us make key 'Space' the same for all layouts
			{ KEY_SPACE," ",	" ",	" ",	" ",		" ",	" ",	" ",	" ", },
			-- Simultaneous pressing Alt + Q..P should also work properly everywhere
			{ KEY_1,	"1",	"1",	"1",	"1",		"1",	"1",	"1",	"1", },
			{ KEY_2,	"2",	"2",	"2",	"2",		"2",	"2",	"2",	"2", },
			{ KEY_3,	"3",	"3",	"3",	"3",		"3",	"3",	"3",	"3", },
			{ KEY_4,	"4",	"4",	"4",	"4",		"4",	"4",	"4",	"4", },
			{ KEY_5,	"5",	"5",	"5",	"5",		"5",	"5",	"5",	"5", },
			{ KEY_6,	"6",	"6",	"6",	"6",		"6",	"6",	"6",	"6", },
			{ KEY_7,	"7",	"7",	"7",	"7",		"7",	"7",	"7",	"7", },
			{ KEY_8,	"8",	"8",	"8",	"8",		"8",	"8",	"8",	"8", },
			{ KEY_9,	"9",	"9",	"9",	"9",		"9",	"9",	"9",	"9", },
			{ KEY_0,	"0",	"0",	"0",	"0",		"0",	"0",	"0",	"0", },
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
	blitbuffer.paintBorder(fb.bb, lx+8*dx-10, vy-r-8, r, r, t + (r-t)*self:num(self.symbolmode), c, r)
	renderUtf8Text(fb.bb, lx-5+8*dx, vy-3, smfont, "Sym", true)
	-- Enter
	blitbuffer.paintBorder(fb.bb, lx+9*dx-10, vy-r-8, r, r, t, c, r)
	renderUtf8Text(fb.bb, lx+9*dx, vy-2, vkfont, "«", true)
	-- Menu
	blitbuffer.paintBorder(fb.bb, lx+10*dx-8, vy-2*dy-r-8, r+50, r, t+(r-t)*self:num(self.utf8mode), c, r)
	renderUtf8Text(fb.bb, lx+10*dx+11, vy-2*dy-3, smfont, "Menu", true)
	-- fiveway
	local h=dy+2*r-2
	blitbuffer.paintBorder(fb.bb, lx+10*dx-8, vy-dy-r-6, h, h, 9, c, r)
	renderUtf8Text(fb.bb, lx+10*dx+22, vy-20, smfont, (self.layout-1), true)
	fb:refresh(1, 1, fb.bb:getHeight()-120, fb.bb:getWidth()-2, 120)
end

function InputBox:num(bool)
	return bool and 1 or 0
end

function InputBox:VKLayout(b1, b2, b3)
	return 2 + self:num(b1) + 2 * self:num(b2) + 4 * self:num(b3)
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
		self.symbolmode = (layout == 2 or layout == 4)
		self.utf8mode   = (self.layout > 5)
	else	-- or, without input parameter, restore layout from current layout modes
		self.layout = self:VKLayout(self.shiftmode, self.symbolmode, self.utf8mode)
	end
	-- let's define layout called by Shift+Key (to type capitalized chars being in low-case layout)
	local shift_layout = self:VKLayout(not self.shiftmode, self.symbolmode, self.utf8mode)
	-- adding the commands
	for k,v in ipairs(self.INPUT_KEYS) do
		-- just redefining existing
		self.commands:add(v[1], nil, "A..Z", "enter character from virtual keyboard (VK)",
			function(self)
				self:addChar(v[self.layout])
			end
		)
		-- and commands for chars pressed with Shift
		self.commands:add(v[1], MOD_SHIFT, "A..Z", "enter capitalized VK-character",
			function(self)
				self:addChar(v[shift_layout])
			end
		)
	end
	self:DrawVirtualKeyboard()
end

function InputBox:StringToCharlist(text)
	if text == nill then return end
	-- clear
	self.charlist = {}
	self.charpos = 1
	local prevcharcode, charcode = 0
	for uchar in string.gfind(text, "([%z\1-\127\194-\244][\128-\191]*)") do
		charcode = util.utf8charcode(uchar)
		if prevcharcode then -- utf8
			self.charlist[#self.charlist+1] = uchar
		end
		prevcharcode = charcode
	end
	self.input_string = self:CharlistToString()
	self.charpos = #self.charlist+1
end

function InputBox:CharlistToString()
	local s, i = ""
	for i=1, #self.charlist do
		s = s .. self.charlist[i]
	end
	return s
end

function InputBox:addAllCommands()
	-- if already initialized, we (re)define only calcmode-dependent commands
	if self.commands then
		self:ModeDependentCommands()
		self:DrawVirtualKeyboard()
		return
	end
	self:setLayoutsTable()
	self.commands = Commands:new{}
	-- adding character commands
	self:addCharCommands(self.layout)
	-- adding the rest commands (independent of the selected layout)
	self.commands:add(KEY_H, MOD_ALT, "H",
		"show helppage",
		function(self)
			self:showHelpPage(self.commands)
		end
	)
	self.commands:add(KEY_FW_LEFT, nil, "joypad left",
		"move cursor left",
		function(self)
			if (self.cursor.x_pos + 3) > self.input_start_x then
				self.cursor:moveHorizontalAndDraw(-self.fwidth)
				self.charpos = self.charpos - 1
				fb:refresh(1, self.input_start_x-5, self.ypos, self.input_slot_w, self.h)
			end
		end
	)
	self.commands:add(KEY_FW_LEFT, MOD_SHIFT, "left",
		"move cursor to the first position",
		function(self)
			if (self.cursor.x_pos + 3) > self.input_start_x then
				self.cursor:moveHorizontalAndDraw(-self.fwidth*(self.charpos-1))
				self.charpos = 1
				fb:refresh(1, self.input_start_x-5, self.ypos, self.input_slot_w, self.h)
			end
		end
	)
	self.commands:add(KEY_FW_RIGHT, nil, "joypad right",
		"move cursor right",
		function(self)
			if (self.cursor.x_pos + 3) < self.input_cur_x then
				self.cursor:moveHorizontalAndDraw(self.fwidth)
				self.charpos = self.charpos + 1
				fb:refresh(1, self.input_start_x-5, self.ypos, self.input_slot_w, self.h)
			end
		end
	)
	self.commands:add(KEY_FW_RIGHT, MOD_SHIFT, "right",
		"move cursor to the last position",
		function(self)
			if (self.cursor.x_pos + 3) < self.input_cur_x then
				self.cursor:moveHorizontalAndDraw(self.fwidth*(#self.charlist+1-self.charpos))
				self.charpos = #self.charlist + 1
				fb:refresh(1, self.input_start_x-5, self.ypos, self.input_slot_w, self.h)
			end
		end
	)
	self.commands:add(KEY_DEL, nil, "Del",
		"delete one character",
		function(self)
			self:delChar()
		end
	)
	self.commands:add(KEY_DEL, MOD_SHIFT, "Del",
		"delete all characters (empty inputbox)",
		function(self)
			self:clearText()
		end
	)
	self.commands:addGroup("up/down", { Keydef:new(KEY_FW_DOWN, nil), Keydef:new(KEY_FW_UP, nil) },
		"goto previous/next VK-layout",
		function(self)
			if keydef.keycode == KEY_FW_DOWN then
				if self.layout == self.max_layout then self:addCharCommands(self.min_layout)
				else self:addCharCommands(self.layout+1) end
			else -- KEY_FW_UP
				if self.layout == self.min_layout then self:addCharCommands(self.max_layout)
				else self:addCharCommands(self.layout-1) end
			end
			
		end
	)
	self.commands:add(KEY_AA, nil, "Aa",
		"toggle VK-layout: chars <> CHARS",
		function(self)
			self.shiftmode = not self.shiftmode
			self:addCharCommands()
		end
	)
	self.commands:add(KEY_SYM, nil, "Sym",
		"toggle VK-layout: chars <> symbols",
		function(self)
			self.symbolmode = not self.symbolmode
			self:addCharCommands()
		end
	)
	self.commands:add(KEY_MENU, nil, "Menu",
		"toggle VK-layout: english <> national",
		function(self)
			self.utf8mode = not self.utf8mode
			self:addCharCommands()
		end
	)
	-- NuPogodi, 02.06.12: calcmode-dependent commands are collected
	self:ModeDependentCommands() -- here

	self.commands:add({KEY_BACK, KEY_HOME}, nil, "Back",
		"back",
		function(self)
			self.input_string = nil
			return "break"
		end
	)
end
-----------------------------------------------------------------
-- NuPogodi, 02.06.12: Some Help- & Calculator-related functions
-----------------------------------------------------------------
function InputBox:defineCalcFunctions() -- for the calculator documentation
	-- to initialize only once
	if self.calcfunctions then return end

	self.calcfunctions = Commands:new{}
	-- remove initially added commands
	self.calcfunctions:del(KEY_INTO_SCREEN_SAVER, nil, "Slider") 
	self.calcfunctions:del(KEY_OUTOF_SCREEN_SAVER, nil, "Slider")
	self.calcfunctions:del(KEY_CHARGING, nil, "plugin/out usb")
	self.calcfunctions:del(KEY_NOT_CHARGING, nil, "plugin/out usb")
	self.calcfunctions:del(KEY_SPACE, MOD_ALT, "Space")

	local s = " " -- space for function groups
	local a = 100 -- arithmetic functions
	self.calcfunctions:add(a-1, nil,	s:rep(1),	string.upper("Ariphmetic operators"))
	self.calcfunctions:add(a,   nil,	"+ -",		"addition: 1+2=3; substraction: 3-2=1")
	self.calcfunctions:add(a+1, nil,	"* /",		"multiplication: 2*2=4; division: 4/2=2")
	self.calcfunctions:add(a+3, nil,	"%",		"modulo (remainder): 5.2%2=1.2, π-π%0.01=3.14")
	local r = 200 -- relations
	self.calcfunctions:add(r-1, nil,	s:rep(2),	string.upper("Relational operators"))
	self.calcfunctions:add(r,   nil,	"< >",		"less: (2<3)=true; more: (2>3)=false")
	self.calcfunctions:add(r+1, nil,	"<=",		"less or equal: (3≤3)=true, (2≤1)=false")
	self.calcfunctions:add(r+2, nil,	">=",		"more or equal: (3≥3)=true, (1≥2)=false")
	self.calcfunctions:add(r+3, nil,	"==",		"equal: (3==3)=true, (1==2)=false")
	self.calcfunctions:add(r+4, nil,	"~=",		"not equal: (6~=8)=true, (3~=3)=false")
	local l = 300 -- logical
	self.calcfunctions:add(l-1, nil,	s:rep(3),	string.upper("Logical operators"))
	self.calcfunctions:add(l+0, nil,	"and, &",	"= logical 'and': (4 and 5)=5, (nil & 5)=nil")
	self.calcfunctions:add(l+1, nil,	"or, |",	"= logical 'or': (4 or 5)=4, (false | 5)=5")
	local c = 400 -- constants
	self.calcfunctions:add(c-1, nil,	s:rep(4),	string.upper("Some constants"))
	self.calcfunctions:add(c,   nil,	"pi, π",	"= 3.14159…; sin(π/2)=1, cos(π/2)=0")
	self.calcfunctions:add(c+1, nil,	"е, exp(1)",	"= 2.71828…; log(е)=1")
	local m = 500 -- mathematical
	self.calcfunctions:add(m-1, nil,	s:rep(5),	string.upper("Mathematic functions"))
	self.calcfunctions:add(m,   nil,	"abs(x)",	"absolute value of x: abs(1)=1, abs(-2)=2")
	self.calcfunctions:add(m+1, nil,	"ceil(x)",	"round to integer no less than x: ceil(0.4)=1")
	self.calcfunctions:add(m+2, nil,	"floor(x)",	"round to integer no greater than x: floor(0.4)=0")
	self.calcfunctions:add(m+3, nil,	"^, pow(x,y)","= power: 2^10=1024, pow(4,0.5)=2")
	self.calcfunctions:add(m+4, nil,	"exp(x), e^x","= exponent: exp(1)=2.71828…")
	self.calcfunctions:add(m+5, nil,	"log(x)",	"the natural logarithm: log(e)=1")
	self.calcfunctions:add(m+6, nil,	"log10(x)",	"the base 10 logarithm: log10(10)=1")
	self.calcfunctions:add(m+7, nil,	"max(x,…)",	"return maximal value: max(0,-1,2,1)=2")
	self.calcfunctions:add(m+8, nil,	"min(x,…)",	"return minimal value: min(0,-1,2,1)=-1")
	self.calcfunctions:add(m+9, nil,	"sqrt(x)",	"return square root: sqrt(4)=2")
	local t = 600 -- trigonometrical
	self.calcfunctions:add(t,   nil,	s:rep(6),	string.upper("Trigonometric functions"))
	self.calcfunctions:add(t+1, nil,	"deg(x)",	"convert radians to degrees: deg(π/2)=90")
	self.calcfunctions:add(t+2, nil,	"rad(x)",	"convert degrees to radians: rad(180)=3.14159…")
	self.calcfunctions:add(t+3, nil,	"sin(x)",	"sine for x given in radians: sin(π/2)=1")
	self.calcfunctions:add(t+4, nil,	"cos(x)",	"cosine for x given in radians: cos(π)=-1")
	self.calcfunctions:add(t+5, nil,	"tan(x)",	"tangent for x given in radians: tan(π/4)=1")
	self.calcfunctions:add(t+6, nil,	"asin(x)",	"inverse sine (in radians): asin(1)/π=0.5")
	self.calcfunctions:add(t+7, nil,	"acos(x)",	"inverse cosine (in radians): acos(0)/π=0.5")
	self.calcfunctions:add(t+8, nil,	"atan(x)",	"inverse tangent (in radians): atan(1)/π=0.25")
	self.calcfunctions:add(t+9, nil,	"atan2(x,y)",	"inverse tangent of two args: = atan(x/y)")
	local h = 700 -- hyperbolical
	self.calcfunctions:add(h,   nil,	s:rep(7),	string.upper("Hyperbolic functions"))
	self.calcfunctions:add(h+1, nil,	"sinh(x)",	"hyperbolic sine, (exp(x)-exp(-x))/2")
	self.calcfunctions:add(h+2, nil,	"cosh(x)",	"hyperbolic cosine, (exp(x)+exp(-x))/2")
	self.calcfunctions:add(h+3, nil,	"tanh(x)",	"hyperbolic tangent, sinh(x)/cosh(x)")
-- not yet documented > "fmod", "frexp", "huge", "ldexp", "modf", "randomseed", "random"
end

function InputBox:showHelpPage(list, title)
	-- make inactive input slot
	self.cursor:clear() -- hide cursor
	fb.bb:dimRect(self.input_start_x-5, self.input_start_y-19, self.input_slot_w, self.fheight, self.input_bg)
	fb:refresh(1, self.input_start_x-5, self.ypos, self.input_slot_w, self.h)
	-- now start the helppage with own list of commands and own title
	HelpPage:show(0, fb.bb:getHeight()-165, list, title)
	-- on the helppage-exit, making inactive helpage
	fb.bb:dimRect(0, 40, fb.bb:getWidth(), fb.bb:getHeight()-205, self.input_bg)
	-- and active input slot
	self:refreshText()
	self.cursor:draw() -- show cursor = ready to input
	fb:refresh(1)
end

function InputBox:setCalcMode()
	--clear previous input
	self.input_string = ""
	self.charlist = {}
	self.charpos = 1
	-- set proper layouts
	self.layout = 4 -- digits
	self.min_layout = 3
	self.max_layout = 4
end

function InputBox:PrepareStringToCalc()
	local s = string.lower(self.input_string)
	-- continue interpreting the input
	local mathe = {	"abs", "acos", "asin", "atan2", "atan", "ceil", "cosh", "cos",
				"deg", "exp", "floor", "fmod", "frexp", "huge", "ldexp", "log10", "log",
				"max", "min", "modf", "pi", "pow", "rad", "randomseed", "random",
				"sinh", "sin", "sqrt", "tanh", "tan", }
	-- to avoid any ambiguities (like sin & sinh), one has to replace by capitals
	for i=1, #mathe do
		s = string.gsub(s, mathe[i], string.upper("math."..mathe[i]))
	end
	-- some acronyms for constants & functions
	s = string.gsub(s, "π", " math.pi ")
	s = string.gsub(s, "е", " math.exp(1) ")
	s = string.gsub(s, "&", " and ")
	s = string.gsub(s, "|", " or ")
	-- return the whole string in lowercase and eventually replace double "math."
	return string.gsub(string.lower(s), "math.math.", "math.")
end

-- define whether we need to calculate the result or to return 'self.input_string'
function InputBox:ModeDependentCommands()
	if self.calcmode then
		-- define what to do with the input_string
		self.commands:add({KEY_FW_PRESS, KEY_ENTER}, nil, "joypad center",
			"calculate the result",
			function(self)
				if #self.input_string == 0 then
					showInfoMsgWithDelay("No input ", 1000, 1)
				else
					local s = self:PrepareStringToCalc()
					if pcall(function () f = assert(loadstring("r = tostring("..s..")")) end) then
						f()
						self:clearText()
						self.cursor:clear()
						for i=1, string.len(r) do
							table.insert(self.charlist, string.sub(r,i,i))
						end
						self.charpos = #self.charlist + 1
						self.input_string = r
						self:refreshText()
						self.cursor:moveHorizontal(#self.charlist*self.fwidth)
						self.cursor:draw()
						fb:refresh(1, self.input_start_x-5, self.input_start_y-25, self.input_slot_w, self.h-25)
					else
						showInfoMsgWithDelay("Invalid input ", 1000, 1)
					end -- if pcall
				end
			end -- function
			)
		-- add the calculator help (short list of available functions)
		-- or, might be better, to make some help document and open it in reader ??
		self.commands:add(KEY_M, MOD_ALT, "M",
			"math functions available in calculator",
			function(self)
				self:defineCalcFunctions()
				self:showHelpPage(self.calcfunctions, "Math Functions for Calculator")
			end
			)
	else 	-- return input_string & close input box
		self.commands:add({KEY_FW_PRESS, KEY_ENTER}, nil, "joypad center",
			"submit input content",
			function(self)
				if self.input_string == "" then
					self.input_string = nil
				end
				return "break"
			end
			)
		-- delete calculator-specific help
		self.commands:del(KEY_M, MOD_ALT, "M")
	end -- if self.calcmode
end

----------------------------------------------------
-- Inputbox for numbers only
-- Designed by eLiNK
----------------------------------------------------

NumInputBox = InputBox:new{
	layout = 4,
	charlist = {},
}
