local Blitbuffer = require("ffi/blitbuffer")
local einkfb = require("ffi/framebuffer")
local Geom = require("ui/geometry")
local util = require("ffi/util")
local DEBUG = require("dbg")

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

    screen_size = Geom:new(),
    viewport = nil,

    fb = einkfb.open("/dev/fb0"),
    -- will be set upon loading by Device class:
    device = nil,
}

function Screen:new(o)
    local o = o or {}
    setmetatable(o, self)
    self.__index = self
    if o.init then o:init() end
    return o
end

function Screen:init()
    self.bb = self.fb.bb
    self.blitbuffer_rotation_mode = self.bb:getRotation()
    -- asking the framebuffer for orientation is error prone,
    -- so we do this simple heuristic (for now)
    self.screen_size.w = self.bb:getWidth()
    self.screen_size.h = self.bb:getHeight()
    if self.screen_size.w > self.screen_size.h then
        self.native_rotation_mode = 1
        self.screen_size.w, self.screen_size.h = self.screen_size.h, self.screen_size.w
    else
        self.native_rotation_mode = 0
    end
    self.cur_rotation_mode = self.native_rotation_mode
end

--[[
set a rectangle that represents the area of the screen we are working on
--]]
function Screen:setViewport(viewport)
    self.viewport = self.screen_size:intersect(viewport)
    self.bb = self.fb.bb:viewport(
        self.viewport.x, self.viewport.y,
        self.viewport.w, self.viewport.h)
end

function Screen:refresh(refresh_type, waveform_mode, x, y, w, h)
    if self.viewport and x and y then
        -- adapt to viewport
        x = x + self.viewport.x
        y = y + self.viewport.y
    end
    self.fb:refresh(refresh_type, waveform_mode, x, y, w, h)
end

function Screen:getSize()
    return Geom:new{w = self.bb:getWidth(), h = self.bb:getHeight()}
end

function Screen:getWidth()
    return self.bb:getWidth()
end

function Screen:getScreenWidth()
    return self.screen_size.w
end

function Screen:getScreenHeight()
    return self.screen_size.h
end

function Screen:getHeight()
    return self.bb:getHeight()
end

function Screen:getDPI()
    if self.dpi == nil then
        self.dpi = G_reader_settings:readSetting("screen_dpi")
    end
    if self.dpi == nil then
        self.dpi = self.device.display_dpi
    end
    if self.dpi == nil then
        self.dpi = 160
    end
    return self.dpi
end

function Screen:setDPI(dpi)
    G_reader_settings:saveSetting("screen_dpi", dpi)
end

function Screen:scaleByDPI(px)
    -- scaled positive px should also be positive
    return math.ceil(px * self:getDPI()/167)
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
    if self.saved_bb then self.saved_bb:free() end
    self.saved_bb = self.bb:copy()
end

function Screen:restoreFromSavedBB()
    if self.saved_bb then
        self.bb:blitFullFrom(self.saved_bb)
        -- free data
        self.saved_bb:free()
        self.saved_bb = nil
    end
end

function Screen:shot(filename)
    DEBUG("write PNG file", filename)
    self.bb:writePNG(filename)
end

function Screen:close()
    DEBUG("close screen framebuffer")
    self.fb:close()
end

return Screen
