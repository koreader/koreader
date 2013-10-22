local Geom = require("ui/geometry")
local DEBUG = require("dbg")

-- Blitbuffer
-- einkfb

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


local Screen = {
	width = 0,
	height = 0,
	native_rotation_mode = nil,
	cur_rotation_mode = 0,

	bb = nil,
	saved_bb = nil,

	fb = einkfb.open("/dev/fb0"),
	-- will be set upon loading by Device class:
	device = nil,
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

function Screen:refresh(refesh_type, waveform_mode, x, y, w, h)
	if x then x = x < 0 and 0 or math.floor(x) end
    if y then y = y < 0 and 0 or math.floor(y) end
    if w then w = w + x > self.width and self.width - x or math.ceil(w) end
    if h then h = h + y > self.height and self.height - y or math.ceil(h) end
	if self.native_rotation_mode == self.cur_rotation_mode then
        self.fb.bb:blitFrom(self.bb, 0, 0, 0, 0, self.width, self.height)
    elseif self.native_rotation_mode == 0 and self.cur_rotation_mode == 1 then
        self.fb.bb:blitFromRotate(self.bb, 270)
        if x and y and w and h then
        	x, y = y, self.width - w - x
        	w, h = h, w
        end
    elseif self.native_rotation_mode == 0 and self.cur_rotation_mode == 3 then
        self.fb.bb:blitFromRotate(self.bb, 90)
        if x and y and w and h then
        	x, y = self.height - h - y, x
        	w, h = h, w
        end
    elseif self.native_rotation_mode == 1 and self.cur_rotation_mode == 0 then
        self.fb.bb:blitFromRotate(self.bb, 90)
        if x and y and w and h then
        	x, y = self.height - h - y, x
        	w, h = h, w
        end
    elseif self.native_rotation_mode == 1 and self.cur_rotation_mode == 3 then
        self.fb.bb:blitFromRotate(self.bb, 180)
        if x and y and w and h then
        	x, y = self.width - w - x, self.height - h - y
        end
    end
	self.fb:refresh(refesh_type, waveform_mode, x, y, w, h)
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
	if(self.device:getModel() == "KindlePaperWhite") or (self.device:getModel() == "Kobo_kraken") then
		return 212
	elseif self.device:getModel() == "Kobo_dragon" then
		return 265
	elseif self.device:getModel() == "Kobo_pixie" then
		return 200
	else
		return 167
	end
end

function Screen:scaleByDPI(px)
	return math.floor(px * self:getDPI()/167)
end

function Screen:rescaleByDPI(px)
	return math.ceil(px * 167/self:getDPI())
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
end

function Screen:setScreenMode(mode)
	if mode == "portrait" then
		if self.cur_rotation_mode ~= 0 then
			self:setRotationMode(0)
		end
	elseif mode == "landscape" then
		if self.cur_rotation_mode == 0 or self.cur_rotation_mode == 2 then
			self:setRotationMode(1)
		elseif self.cur_rotation_mode == 1 or self.cur_rotation_mode == 3 then
			self:setRotationMode((self.cur_rotation_mode + 2) % 4)
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

return Screen
