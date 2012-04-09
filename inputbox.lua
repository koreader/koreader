require "rendertext"
require "keys"
require "graphics"

InputBox = {
	-- Class vars:
	h = 100,
	input_slot_w = nil,
	input_start_x = 145,
	input_start_y = nil,
	input_cur_x = nil, -- points to the start of next input pos

	input_bg = 0,

	input_string = "",

	shiftmode = false,
	altmode = false,

	cursor = nil,

	-- font for displaying input content
	-- we have to use mono here for better distance controlling
	face = freetype.newBuiltinFace("mono", 25),
	fhash = "m25",
	fheight = 25,
	fwidth = 15,
	commands = nil,
}

function InputBox:refreshText()
	-- clear previous painted text
	fb.bb:paintRect(140, self.input_start_y-19, 
					self.input_slot_w, self.fheight, self.input_bg)
	-- paint new text
	renderUtf8Text(fb.bb, self.input_start_x, self.input_start_y,
					self.face, self.fhash,
					self.input_string, 0)
end

function InputBox:addChar(char)
	self.cursor:clear()

	-- draw new text
	local cur_index = (self.cursor.x_pos + 3 - self.input_start_x)
						/ self.fwidth
	self.input_string = self.input_string:sub(1,cur_index)..char..
						self.input_string:sub(cur_index+1)
	self:refreshText()
	self.input_cur_x = self.input_cur_x + self.fwidth
	-- draw new cursor
	self.cursor:moveHorizontal(self.fwidth)
	self.cursor:draw()

	fb:refresh(1, self.input_start_x-5, self.input_start_y-25, 
				self.input_slot_w, self.h-25)
end

function InputBox:delChar()
	if self.input_start_x == self.input_cur_x then
		return
	end

	local cur_index = (self.cursor.x_pos + 3 - self.input_start_x)
						/ self.fwidth
	if cur_index == 0 then return end

	self.cursor:clear()

	-- draw new text
	self.input_string = self.input_string:sub(0,cur_index-1)..
						self.input_string:sub(cur_index+1, -1)
	self:refreshText()
	self.input_cur_x = self.input_cur_x - self.fwidth
	-- draw new cursor
	self.cursor:moveHorizontal(-self.fwidth)
	self.cursor:draw()

	fb:refresh(1, self.input_start_x-5, self.input_start_y-25, 
				self.input_slot_w, self.h-25)
end

function InputBox:clearText()
	self.cursor:clear()
	self.input_string = ""
	self:refreshText()
	self.cursor.x_pos = self.input_start_x - 3
	self.cursor:draw()

	fb:refresh(1, self.input_start_x-5, self.input_start_y-25, 
				self.input_slot_w, self.h-25)
end

function InputBox:drawBox(ypos, w, h, title)
	-- draw input border
	fb.bb:paintRect(20, ypos, w, h, 5)
	-- draw input slot
	fb.bb:paintRect(140, ypos + 10, w - 130, h - 20, self.input_bg)
	-- draw input title
	renderUtf8Text(fb.bb, 35, self.input_start_y, self.face, self.fhash,
		title, true)
end


----------------------------------------------------------------------
-- InputBox:input()
--
-- @title: input prompt for the box
-- @d_text: default to nil (used to set default text in input slot)
----------------------------------------------------------------------
function InputBox:input(ypos, height, title, d_text)
	-- do some initilization
	self:addAllCommands()
	self.ypos = ypos
	self.h = height
	self.input_start_y = ypos + 35
	self.input_cur_x = self.input_start_x
	self.input_slot_w = fb.bb:getWidth() - 170

	self.cursor = Cursor:new {
		x_pos = self.input_start_x - 3,
		y_pos = ypos + 13,
		h = 30,
	}


	-- draw box and content
	w = fb.bb:getWidth() - 40
	h = height - 45
	self:drawBox(ypos, w, h, title)
	if d_text then
		self.input_string = d_text
		self.input_cur_x = self.input_cur_x + (self.fwidth * d_text:len())
		self.cursor.x_pos = self.cursor.x_pos + (self.fwidth * d_text:len())
		self:refreshText()
	end
	self.cursor:draw()
	fb:refresh(1, 20, ypos, w, h)

	while true do
		local ev = input.waitForEvent()
		ev.code = adjustKeyEvents(ev)
		if ev.type == EV_KEY and ev.value == EVENT_VALUE_KEY_PRESS then
			keydef = Keydef:new(ev.code, getKeyModifier())
			print("key pressed: "..tostring(keydef))

			command = self.commands:getByKeydef(keydef)
			if command ~= nil then
				print("command to execute: "..tostring(command))
				ret_code = command.func(self, keydef)
			else
				print("command not found: "..tostring(command))
			end

			if ret_code == "break" then
				break
			end
		end -- if
	end -- while

	local return_str = self.input_string
	self.input_string = ""
	return return_str
end

function InputBox:addAllCommands()
	if self.commands then
		-- we only initialize once
		return
	end
	self.commands = Commands:new{}
	
	INPUT_KEYS = {
		{KEY_Q, "q"}, {KEY_W, "w"}, {KEY_E, "e"}, {KEY_R, "r"}, {KEY_T, "t"}, 
		{KEY_Y, "y"}, {KEY_U, "u"}, {KEY_I, "i"}, {KEY_O, "o"}, {KEY_P, "p"},

		{KEY_A, "a"}, {KEY_S, "s"}, {KEY_D, "d"}, {KEY_F, "f"}, {KEY_G, "g"},
		{KEY_H, "h"}, {KEY_J, "j"}, {KEY_K, "k"}, {KEY_L, "l"},

		{KEY_Z, "z"}, {KEY_X, "x"}, {KEY_C, "c"}, {KEY_V, "v"}, {KEY_B, "b"},
		{KEY_N, "n"}, {KEY_M, "m"},

		{KEY_1, "1"}, {KEY_2, "2"}, {KEY_3, "3"}, {KEY_4, "4"}, {KEY_5, "5"},
		{KEY_6, "6"}, {KEY_7, "7"}, {KEY_8, "8"}, {KEY_9, "9"}, {KEY_0, "0"},
	}
	for k,v in ipairs(INPUT_KEYS) do
		self.commands:add(v[1], nil, "",
			"input "..v[2],
			function(self)
				self:addChar(v[2])
			end
		)
	end

	self.commands:add(KEY_FW_LEFT, nil, "",
		"move cursor left",
		function(self)
			if (self.cursor.x_pos + 3) > self.input_start_x then
				self.cursor:moveHorizontalAndDraw(-self.fwidth)
				fb:refresh(1, self.input_start_x-5, self.ypos,
							self.input_slot_w, self.h)
			end
		end
	)
	self.commands:add(KEY_FW_RIGHT, nil, "",
		"move cursor right",
		function(self)
			if (self.cursor.x_pos + 3) < self.input_cur_x then
				self.cursor:moveHorizontalAndDraw(self.fwidth)
				fb:refresh(1,self.input_start_x-5, self.ypos,
							self.input_slot_w, self.h)
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
end
