--[[
    Copyright (C) 2011 Hans-Werner Hilse <hilse@web.de>

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
]]--

--[[
Codes for rotation modes:

1 for no rotation, 
2 for landscape with bottom on the right side of screen, etc.

           2
   +--------------+
   | +----------+ |
   | |          | |
   | | Freedom! | |
   | |          | |  
   | |          | |  
 3 | |          | | 1
   | |          | |
   | |          | |
   | +----------+ |
   |              |
   |              |
   +--------------+
          0
--]]


Screen = {
	cur_rotation_mode = 0,
	-- these two variabls are used to help switching from framework to reader
	native_rotation_mode = nil,
	kpv_rotation_mode = nil,

	saved_bb = nil,
}

-- @orien: 1 for clockwise rotate, -1 for anti-clockwise
-- Remember to reread screen resolution after this function call
function Screen:screenRotate(orien)
	if orien == "clockwise" then
		orien = -1
	elseif orien == "anticlockwise" then
		orien = 1
	else
		return
	end

	self.cur_rotation_mode = (self.cur_rotation_mode + orien) % 4
	-- you have to reopen framebuffer after rotate
	fb:setOrientation(self.cur_rotation_mode)
	fb:close()
	fb = einkfb.open("/dev/fb0")
end

function Screen:updateRotationMode()
	if KEY_FW_DOWN == 116 then -- in EMU mode always set to 0
		self.cur_rotation_mode = 0
	else
		orie_fd = assert(io.open("/sys/module/eink_fb_hal_broads/parameters/bs_orientation", "r"))
		updown_fd = assert(io.open("/sys/module/eink_fb_hal_broads/parameters/bs_upside_down", "r"))
		self.cur_rotation_mode = orie_fd:read() + (updown_fd:read() * 2)
	end
end

function Screen:saveCurrentBB()
	local width, height = G_width, G_height

	if not self.saved_bb then
		self.saved_bb = Blitbuffer.new(width, height)
	end
	if self.saved_bb:getWidth() ~= width then
		self.saved_bb:free()
		self.saved_bb = Blitbuffer.new(width, height)
	end
	self.saved_bb:blitFullFrom(fb.bb)
end

function Screen:restoreFromSavedBB()
	self:restoreFromBB(self.saved_bb)
end

function Screen:getCurrentScreenBB()
	local bb = Blitbuffer.new(G_width, G_height)
	bb:blitFullFrom(fb.bb)
	return bb
end

function Screen:restoreFromBB(bb)
	if bb then
		fb.bb:blitFullFrom(bb)
	else
		Debug("Got nil bb in restoreFromSavedBB!")
	end
end

function Screen:screenshot()
	lfs.mkdir("./screenshots")
	local start = os.clock()
	--showInfoMsgWithDelay("making screenshot... ", 2500, 1)
	self:BMP(lfs.currentdir().."/screenshots/"..os.date("%Y%m%d%H%M%S")..".bmp", "bzip2 ")
	showInfoMsgWithDelay(string.format("BMP-shot ready in %.2f(s)", os.clock()-start), 1000, 1)
end

function Screen:BMP(fn, pack) -- ~1.6-1.8(s), @ Kindle3, 600x800, remains 4bpp
	local inputf = assert(io.open("/dev/fb0","rb"))
	if inputf then
		local outputf = assert(io.open(fn,"wb"))
		-- writing header
		outputf:write("BM", string.char(246), string.char(169), string.char(3), string.rep(string.char(0),5),
			string.char(118), string.rep(string.char(0),3), string.char(40), string.char(0),
			string.rep(string.char(0),2), string.char(G_width%256), string.char((G_width-G_width%256)/256),	-- width
			string.rep(string.char(0),2), string.char(G_height%256), string.char((G_height-G_height%256)/256),	-- height
			string.rep(string.char(0),2), string.char(1), string.char(0), string.char(4), string.rep(string.char(0),5),
			string.char(128), string.char(169), string.char(3), string.char(0), 
			string.char(135), string.char(25), string.rep(string.char(0),2), string.char(135), string.char(25),
			string.rep(string.char(0), 2), string.char(16), string.rep(string.char(0),7))
		local block, i = G_width/2, 15
		-- add palette to header
		while i>=0 do
			outputf:write(string.rep(string.char(i*16+i),3), string.char(0))
			i=i-1
		end
		-- now read fb0-content & invert the line order (i.e. make a vertical flip)
		local content = ""
		for i=1, G_height do
			content = inputf:read(block)..content
		end
		-- write v-flipped bmp-data to the output file
		outputf:write(content)
		inputf:close()
		outputf:close()
		if pack then os.execute(pack..fn) end
	end
end

function Screen:PGM(fn, pack) -- ~2.5(s) @ Kindle3, 600x800 slow because of 4bpp to 8bpp conversion
	local inputf = assert(io.open("/dev/fb0","rb"))
	if inputf then
		local outputf = assert(io.open(fn,"wb"))
		outputf:write("P5\n\# Created by kindlepdfviewer\n"..G_width.." "..G_height.."\n255\n")
		local bpp8, block, i, j, line = {}, G_width/2
		-- create convertion table: char > 2 chars
		for j=0, 255 do 
			i = j%16
			bpp8[#bpp8+1] = string.char(255-j+i)..string.char(255-i*16)
		end
		-- now read, convert & write the fb0-content by blocks
		for i=1, G_height do
			line = inputf:read(block)
			for j=1, block do
				outputf:write(bpp8[1+string.byte(line,j)])
			end
		end
		inputf:close()
		outputf:close()
		if pack then os.execute(pack..fn) end
	end
end
