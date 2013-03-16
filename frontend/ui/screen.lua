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
	width = 0,
	height = 0,
	native_rotation_mode = nil,
	cur_rotation_mode = 0,

	bb = nil,
	saved_bb = nil,

	fb = einkfb.open("/dev/fb0"),
}

function Screen:init()
	-- for unknown strange reason, pitch*2 is 10 px more than screen width in KPW
	self.width, self.height = self.fb:getSize()
	-- Blitbuffer still uses inverted 4bpp bitmap, so pitch should be
	-- (self.width / 2)
	self.bb = Blitbuffer.new(self.width, self.height, self.width/2)
	if self.width > self.height then
		-- For another unknown strange reason, self.fb:getOrientation always
		-- return 0 in KPW, even though we are in landscape mode.
		-- Seems like the native framework change framebuffer on the fly when
		-- starting booklet. Starting KPV from ssh and KPVBooklet will get
		-- different framebuffer height and width.
		--
		--self.native_rotation_mode = self.fb:getOrientation()
		self.native_rotation_mode = 1
	else
		self.native_rotation_mode = 0
	end
	self.cur_rotation_mode = self.native_rotation_mode
end

function Screen:refresh(refesh_type)
	if self.native_rotation_mode ==  self.cur_rotation_mode then
		self.fb.bb:blitFrom(self.bb, 0, 0, 0, 0, self.width, self.height)
	elseif self.native_rotation_mode == 0 and self.cur_rotation_mode == 1 then
		self.fb.bb:blitFromRotate(self.bb, 270)
	elseif self.native_rotation_mode == 1 and self.cur_rotation_mode == 0 then
		self.fb.bb:blitFromRotate(self.bb, 90)
	end
	self.fb:refresh(refesh_type)
end

function Screen:getSize()
	return Geom:new{w = self.width, h = self.height}
end

function Screen:getWidth()
	return self.width
end

function Screen:getHeight()
	return self.height
end

function Screen:getDPI()
	return Device:getModel() == "KindlePaperWhite" and 212 or 167
end

function Screen:scaleByDPI(px)
	return (px * self:getDPI()/167)
end

-- make a shortcut to Screen:scaleByDPI
function scaleByDPI(px)
	return Screen:scaleByDPI(px)
end

function Screen:getPitch()
	return self.fb:getPitch()
end

function Screen:getNativeRotationMode()
	-- in EMU mode, you will always get 0 from getOrientation()
	return self.fb:getOrientation()
end

function Screen:getRotationMode()
	return self.cur_rotation_mode
end

function Screen:getScreenMode()
	if self.width > self.height then
		return "landscape"
	else
		return "portrait"
	end
end

function Screen:setRotationMode(mode)
	if mode > 3 or mode < 0 then
		return
	end

	-- mode 0 and mode 2 has the same width and height, so do mode 1 and 3
	if (self.cur_rotation_mode % 2) ~= (mode % 2) then
		self.width, self.height = self.height, self.width
	end
	self.cur_rotation_mode = mode
	self.bb:free()
	self.bb = Blitbuffer.new(self.width, self.height, self.width/2)
	-- update mode for input module
	Input.rotation = mode
end

function Screen:setScreenMode(mode)
	if mode == "portrait" then
		if self.cur_rotation_mode ~= 0 then
			self:setRotationMode(0)
		end
	elseif mode == "landscape" then
		if self.cur_rotation_mode ~= 1 then
			self:setRotationMode(1)
		end
	end
end

function Screen:saveCurrentBB()
	local width, height = self:getWidth(), self:getHeight()

	if not self.saved_bb then
		self.saved_bb = Blitbuffer.new(width, height, self.width/2)
	end
	if self.saved_bb:getWidth() ~= width then
		self.saved_bb:free()
		self.saved_bb = Blitbuffer.new(width, height, self.width/2)
	end
	self.saved_bb:blitFullFrom(self.bb)
end

function Screen:restoreFromSavedBB()
	self:restoreFromBB(self.saved_bb)
end

function Screen:getCurrentScreenBB()
	local bb = Blitbuffer.new(self:getWidth(), self:getHeight())
	bb:blitFullFrom(self.bb)
	return bb
end

function Screen:restoreFromBB(bb)
	if bb then
		self.bb:blitFullFrom(bb)
	else
		DEBUG("Got nil bb in restoreFromSavedBB!")
	end
end
