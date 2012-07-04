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
	--local start = os.clock()
	showInfoMsgWithDelay("making screenshot... ", 1000, 1)
	self:BMP(lfs.currentdir().."/screenshots/"..os.date("%Y%m%d%H%M%S")..".bmp", "bzip2 ")	-- fastest for 4bpp devices
	--self:PGM(lfs.currentdir().."/screenshots/"..os.date("%Y%m%d%H%M%S")..".pgm", "bzip2 ",8)	-- fastest for 8bpp devices
	--showInfoMsgWithDelay(string.format("Screenshot is ready in %.2f(s) ", os.clock()-start), 1000, 1)
end

-- NuPogodi (02.07.2012): added the functions to save the fb-content in common graphic files - bmp & pgm.
-- todo: to look for the arm-compiled bmp2png converter & to use it instead of the current bzip2-packer.

function Screen:LE(i) -- returns value in the little-endian binary sequence (4chars)
	local j=i%256 -- lowest byte
	return string.char(0,0,j,(i-j)/256)
end

--[[ This function saves the 4bpp framebuffer as 4bpp BMP and, if necessary, packes the output by command os.execute(pack..fn).
Since framebuffer enumerates the lines from top to bottom and the bmp-file does it in the inversed order, the process includes
a vertical flip that makes it a bit slower - ~0.15(s) @ Kindle3 & Kindle2.
NB: needs free memory of G_width*G_height/2 bytes to manupulate the fb-content! ]]

function Screen:BMP(fn, pack) -- for 4bpp framebuffers only
	local inputf = assert(io.open("/dev/fb0","rb"))
	if inputf then
		local outputf, size = assert(io.open(fn,"wb"))
		if math.max(G_width,G_height)>1000 then	-- KDX(G) 
			size=string.char(0x98,0x8D,7,0)	-- 0x00,0x72,0x06,0x00 > raw bytes in image 825*1200/2 = 0x00078D98 @ KDX(G)
		else	-- 600x800
			size=string.char(0x80,0xA9,3,0)	-- 0x80,0xA9,0x03,0x00 > raw bytes in image  600*800/2 = 0x0003A980 @ K2&3
		end
		-- writing bmp-header
		outputf:write(string.char(0x42,0x4D,0xF6,0xA9,3,0,0,0,0,0,0x76,0,0,0,40,0),
				self:LE(G_width), self:LE(G_height),	-- width & height: 4 chars each
				string.char(0,0,1,0,4,0,0,0,0,0), size,
				string.char(0x87,0x19,0,0,0x87,0x19,0,0),	-- 0x87,0x19,0x00,0x00 = 6536 pix/m = 166 dpi - resolution_x, res_y
				string.char(16,0,0,0,0,0,0,0))		-- 16 colors
		local line, i = G_width/2, 15
		-- add palette to bmp-header
		while i>=0 do
			outputf:write(string.char(i*16+i):rep(3), string.char(0))
			i=i-1
		end
		-- read the fb-content line-by-line & fill the content-table in the inversed order
		local content = {}
		for i=1, G_height do
			table.insert(content, 1, inputf:read(line))
		end
		-- write the v-flipped bmp-data
		for i=1, G_height do
			outputf:write(content[i])
		end
		inputf:close()
		outputf:close()
		if pack then os.execute(pack..fn) end
	end
end

--[[ This function saves the fb-content (both 4bpp and 8bpp) as 8bpp PGM and pack it. It's relatively slow for 4bpp devices 
(~2.5s on Kindle3, 600x800, 4bpp), but should be extremely fast (<0.1s) when no 4bbp to 8bpp is needed. ]]

function Screen:PGM(fn, pack, bpp)
	local inputf = assert(io.open("/dev/fb0","rb"))
	if inputf then
		local outputf = assert(io.open(fn,"wb"))
		outputf:write("P5\n\# Created by kindlepdfviewer\n"..G_width.." "..G_height.."\n255\n")
		if bpp == 8 then -- needs free memory of G_width*G_height bytes!
			outputf:write(inputf:read("*all"))
		else	-- convert 4bpp to 8bpp; needs free memory to store a block = G_width/2 bytes (could be changed)
			local bpp8, block, i, j, line = {}, G_width/2
			-- to accelerate a process, let us first create the convertion table: char (0..255) > 2 chars
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
		end
		inputf:close()
		outputf:close()
		if pack then os.execute(pack..fn) end
	end
end
