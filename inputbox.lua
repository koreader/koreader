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
	self.input_string = self.input_string:sub(0,cur_index)..char..
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

	self.cursor:clear()

	-- draw new text
	local cur_index = (self.cursor.x_pos + 3 - self.input_start_x)
						/ self.fwidth
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
			--local secs, usecs = util.gettime()
			if ev.code == KEY_FW_UP then
			elseif ev.code == KEY_FW_DOWN then
			elseif ev.code == KEY_A then
				self:addChar("a")
			elseif ev.code == KEY_B then
				self:addChar("b")
			elseif ev.code == KEY_C then
				self:addChar("c")
			elseif ev.code == KEY_D then
				self:addChar("d")
			elseif ev.code == KEY_E then
				self:addChar("e")
			elseif ev.code == KEY_F then
				self:addChar("f")
			elseif ev.code == KEY_G then
				self:addChar("g")
			elseif ev.code == KEY_H then
				self:addChar("h")
			elseif ev.code == KEY_I then
				self:addChar("i")
			elseif ev.code == KEY_J then
				self:addChar("j")
			elseif ev.code == KEY_K then
				self:addChar("k")
			elseif ev.code == KEY_L then
				self:addChar("l")
			elseif ev.code == KEY_M then
				self:addChar("m")
			elseif ev.code == KEY_N then
				self:addChar("n")
			elseif ev.code == KEY_O then
				self:addChar("o")
			elseif ev.code == KEY_P then
				self:addChar("p")
			elseif ev.code == KEY_Q then
				self:addChar("q")
			elseif ev.code == KEY_R then
				self:addChar("r")
			elseif ev.code == KEY_S then
				self:addChar("s")
			elseif ev.code == KEY_T then
				self:addChar("t")
			elseif ev.code == KEY_U then
				self:addChar("u")
			elseif ev.code == KEY_V then
				self:addChar("v")
			elseif ev.code == KEY_W then
				self:addChar("w")
			elseif ev.code == KEY_X then
				self:addChar("x")
			elseif ev.code == KEY_Y then
				self:addChar("y")
			elseif ev.code == KEY_Z then
				self:addChar("z")
			elseif ev.code == KEY_1 then
				self:addChar("1")
			elseif ev.code == KEY_2 then
				self:addChar("2")
			elseif ev.code == KEY_3 then
				self:addChar("3")
			elseif ev.code == KEY_4 then
				self:addChar("4")
			elseif ev.code == KEY_5 then
				self:addChar("5")
			elseif ev.code == KEY_6 then
				self:addChar("6")
			elseif ev.code == KEY_7 then
				self:addChar("7")
			elseif ev.code == KEY_8 then
				self:addChar("8")
			elseif ev.code == KEY_9 then
				self:addChar("9")
			elseif ev.code == KEY_0 then
				self:addChar("0")
			elseif ev.code == KEY_SPACE then
				self:addChar(" ")
			elseif ev.code == KEY_PGFWD then
			elseif ev.code == KEY_PGBCK then
			elseif ev.code == KEY_FW_LEFT then
				if (self.cursor.x_pos + 3) > self.input_start_x then
					self.cursor:moveHorizontalAndDraw(-self.fwidth)
					fb:refresh(1, self.input_start_x-5, ypos,
								self.input_slot_w, h)
				end
			elseif ev.code == KEY_FW_RIGHT then
				if (self.cursor.x_pos + 3) < self.input_cur_x then
					self.cursor:moveHorizontalAndDraw(self.fwidth)
					fb:refresh(1,self.input_start_x-5, ypos,
								self.input_slot_w, h)
				end
			elseif ev.code == KEY_ENTER or ev.code == KEY_FW_PRESS then
				if self.input_string == "" then
					self.input_string = nil
				end
				break
			elseif ev.code == KEY_DEL then
				if Keys.shiftmode then
					self:clearText()
				else
					self:delChar()
				end
			elseif ev.code == KEY_BACK or ev.code == KEY_HOME then
				self.input_string = nil
				break
			end

			--local nsecs, nusecs = util.gettime()
			--local dur = (nsecs - secs) * 1000000 + nusecs - usecs
			--print("E: T="..ev.type.." V="..ev.value.." C="..ev.code.." DUR="..dur)
		end -- if
	end -- while

	local return_str = self.input_string
	self.input_string = ""
	return return_str
end
