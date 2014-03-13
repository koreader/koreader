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
    cur_rotation_mode = 0,
    native_rotation_mode = nil,
    blitbuffer_rotation_mode = 0,

    bb = nil,
    saved_bb = nil,

    fb = einkfb.open("/dev/fb0"),
    -- will be set upon loading by Device class:
    device = nil,
}

function Screen:init()
    self.bb = self.fb.bb
    self.blitbuffer_rotation_mode = self.bb:getRotation()
    -- asking the framebuffer for orientation is error prone,
    -- so we do this simple heuristic (for now)
    if self:getWidth() > self:getHeight() then
        self.native_rotation_mode = 1
    else
        self.native_rotation_mode = 0
    end
    self.cur_rotation_mode = self.native_rotation_mode
end

function Screen:refresh(refresh_type, waveform_mode, x, y, w, h)
    self.fb:refresh(refresh_type, waveform_mode, x, y, w, h)
end

function Screen:getSize()
    return Geom:new{w = self.bb:getWidth(), h = self.bb:getHeight()}
end

function Screen:getWidth()
    return self.bb:getWidth()
end

function Screen:getHeight()
    return self.bb:getHeight()
end

function Screen:getDPI()
    if(self.device:getModel() == "KindlePaperWhite")
    or (self.device:getModel() == "Kobo_kraken")
    or (self.device:getModel() == "Kobo_phoenix") then
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

function Screen:getRotationMode()
    return self.cur_rotation_mode
end

function Screen:getScreenMode()
    if self:getWidth() > self:getHeight() then
        return "landscape"
    else
        return "portrait"
    end
end

function Screen:setRotationMode(mode)
    self.fb.bb:rotateAbsolute(-90 * (mode - self.native_rotation_mode - self.blitbuffer_rotation_mode))
    self.cur_rotation_mode = mode
end

function Screen:setScreenMode(mode)
    if mode == "portrait" then
        if self.cur_rotation_mode ~= 0 then
            self:setRotationMode(0)
        end
    elseif mode == "landscape" then
        if self.cur_rotation_mode == 0 or self.cur_rotation_mode == 2 then
            self:setRotationMode(DLANDSCAPE_CLOCKWISE_ROTATION and 1 or 3)
        elseif self.cur_rotation_mode == 1 or self.cur_rotation_mode == 3 then
            self:setRotationMode((self.cur_rotation_mode + 2) % 4)
        end
    end
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
    self.saved_bb:blitFullFrom(self.bb)
end

function Screen:restoreFromSavedBB()
    self:restoreFromBB(self.saved_bb)
    -- free data
    self.saved_bb = nil
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
