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
		DEBUG("Got nil bb in restoreFromSavedBB!")
	end
end
