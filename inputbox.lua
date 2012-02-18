require "rendertext"
require "keys"
require "graphics"

InputBox = {
	-- Class vars:
	
	-- font for displaying input content
	face = freetype.newBuiltinFace("mono", 25),
	fhash = "m25",
	fheight = 25,
	-- font for input title display
	tface = freetype.newBuiltinFace("sans", 28),
	tfhash = "s28",
	-- spacing between lines
	spacing = 40,

	input_start_x = 145,
	input_start_y = nil,
	input_cur_x = nil,

	input_bg = 1,

	input_string = "",
	-- state buffer
	dirs = nil,
	files = nil,
	items = 0,
	path = "",
	page = 1,
	current = 1,
	oldcurrent = 0,
}

function InputBox:setPath(newPath)
	self.path = newPath
	self:readdir()
	self.items = #self.dirs + #self.files
	if self.items == 0 then
		return nil
	end
	self.page = 1
	self.current = 1
	return true
end

function InputBox:addChar(text)
	renderUtf8Text(fb.bb, self.input_cur_x, self.input_start_y,
								self.face, self.fhash, text, true)
	fb:refresh(1, self.input_cur_x, self.input_start_y-19, 16, self.fheight)
	self.input_cur_x = self.input_cur_x + 16
	self.input_string = self.input_string .. text
end

function InputBox:delChar()
	if self.input_start_x == self.input_cur_x then
		return
	end
	self.input_cur_x = self.input_cur_x - 16
	--fill last character with blank rectangle
	fb.bb:paintRect(self.input_cur_x, self.input_start_y-19, 16, self.fheight, self.input_bg)
	fb:refresh(1, self.input_cur_x, self.input_start_y-19, 16, self.fheight)
	self.input_string = self.input_string:sub(0,-2)
end

function InputBox:input(ypos, height, title)
	local pagedirty = true
	self.input_start_y = ypos + 35
	self.input_cur_x = self.input_start_x

	while true do
		if pagedirty then
			w = fb.bb:getWidth() - 40
			h = height - 45
			-- draw input border
			fb.bb:paintRect(20, ypos, w, h, 5)
			-- draw input slot
			fb.bb:paintRect(140, ypos + 10, w - 130, h - 20, self.input_bg)
			renderUtf8Text(fb.bb, 35, self.input_start_y, self.face, self.fhash,
				title, true)
			markerdirty = true
		end

		if pagedirty then
			fb:refresh(1, 20, ypos, w, h)
			pagedirty = false
		end

		local ev = input.waitForEvent()
		if ev.type == EV_KEY and ev.value == EVENT_VALUE_KEY_PRESS then
			print("key code:"..ev.code)
			--ev.code = adjustFWKey(ev.code)
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
			elseif ev.code == KEY_SPACE then
				self:addChar(" ")
			elseif ev.code == KEY_PGFWD then
			elseif ev.code == KEY_PGBCK then
			elseif ev.code == KEY_ENTER or ev.code == KEY_FW_PRESS then
				if self.input_string == "" then
					return nil
				else
					return self.input_string
				end
			elseif ev.code == KEY_DEL then
				self:delChar()
			elseif ev.code == KEY_BACK then
				return nil
			end
		end
	end
end
