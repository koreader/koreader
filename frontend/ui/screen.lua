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

	fb = einkfb.open("/dev/fb0")
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
	self.fb:setOrientation(self.cur_rotation_mode)
	self.fb:close()
	self.fb = einkfb.open("/dev/fb0")
	Input.rotation = self.cur_rotation_mode
end

function Screen:getSize()
	local w, h = self.fb:getSize()
	return Geom:new{w = w, h = h}
end

function Screen:getWidth()
	local w, _ = self.fb:getSize()
	return w
end

function Screen:getHeight()
	local _, h = self.fb:getSize()
	return h
end

function Screen:getPitch()
	return self.fb:getPitch()
end

function Screen:updateRotationMode()
	-- in EMU mode, you will always get 0 from getOrientation()
	self.cur_rotation_mode = self.fb:getOrientation()
end

function Screen:setRotationMode(mode)
	self.fb:setOrientation(Screen.native_rotation_mode)
end

function Screen:saveCurrentBB()
	local width, height = self:getWidth(), self:getHeight()

	if not self.saved_bb then
		self.saved_bb = Blitbuffer.new(width, height)
	end
	if self.saved_bb:getWidth() ~= width then
		self.saved_bb:free()
		self.saved_bb = Blitbuffer.new(width, height)
	end
	self.saved_bb:blitFullFrom(self.fb.bb)
end

function Screen:restoreFromSavedBB()
	self:restoreFromBB(self.saved_bb)
end

function Screen:getCurrentScreenBB()
	local bb = Blitbuffer.new(self:getWidth(), self:getHeight())
	bb:blitFullFrom(self.fb.bb)
	return bb
end

function Screen:restoreFromBB(bb)
	if bb then
		self.fb.bb:blitFullFrom(bb)
	else
		DEBUG("Got nil bb in restoreFromSavedBB!")
	end
end
