local Blitbuffer = require("ffi/blitbuffer")
local Geom = require("ui/geometry")
local DEBUG = require("dbg")
local util = require("ffi/util")

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
    if self.device:getModel() ~= 'Kobo_phoenix' then
        function Screen:getSize()
            return Screen:getSizeBB()
        end
        function Screen:getWidth()
            return Screen:getWidthBB()
        end
        function Screen:getHeight()
            return Screen:getHeightBB()
        end
    else
        function Screen:getSize()
            return Screen:getSizePhoenix()
        end
        function Screen:getWidth()
            return Screen:getWidthPhoenix()
        end
        function Screen:getHeight()
            return Screen:getHeightPhoenix()
        end
    end
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

function Screen:getSizeBB()
    return Geom:new{w = self.bb:getWidth(), h = self.bb:getHeight()}
end

function Screen:getSizePhoenix()
    return Geom:new{w = 751, h = 1006}
end

function Screen:getWidthBB()
    return self.bb:getWidth()
end
function Screen:getWidthPhoenix()
    return 751
end

function Screen:getHeightBB()
    return self.bb:getHeight()
end

function Screen:getHeightPhoenix()
    return 1006
end

function Screen:getDPI()
    if self.dpi ~= nil then return self.dpi end
    local model = self.device:getModel()
    if model == "KindlePaperWhite" or model == "KindlePaperWhite2"
        or model == "Kobo_kraken" or model == "Kobo_phoenix" then
        self.dpi = 212
    elseif model == "Kobo_dragon" then
        self.dpi = 265
    elseif model == "Kobo_pixie" then
        self.dpi = 200
    elseif util.isAndroid() then
        local android = require("android")
        local ffi = require("ffi")
        self.dpi = ffi.C.AConfiguration_getDensity(android.app.config)
    else
        self.dpi = 167
    end
    return self.dpi
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
