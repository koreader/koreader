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

function Screen:refresh(refresh_type, waveform_mode, wait_for_marker, x, y, w, h)
    if self.viewport and x and y then
        --[[
            we need to adapt the coordinates when we have a viewport.
            this adaptation depends on the rotation:

          0,0               fb.w
            +---+---------------------------+---+
            |   |v.y                     v.y|   |
            |v.x|                           |vx2|
            +---+---------------------------+---+
            |   |           v.w             |   |
            |   |                           |   |
            |   |                           |   |
            |   |v.h     (viewport)         |   |
            |   |                           |   | fb.h
            |   |                           |   |
            |   |                           |   |
            |   |                           |   |
            +---+---------------------------+---+
            |v.x|                           |vx2|
            |   |vy2                     vy2|   |
            +---+---------------------------+---+

            The viewport offset v.y/v.x only applies when rotation is 0 degrees.
            For other rotations (0,0 is in one of the other edges), we need to
            recalculate the offsets.
        --]]

        local vx2 = self.screen_size.w - (self.viewport.x + self.viewport.w)
        local vy2 = self.screen_size.h - (self.viewport.y + self.viewport.h)

        if self.cur_rotation_mode == 0 then
            -- (0,0) is at top left of screen
            x = x + self.viewport.x
            y = y + self.viewport.y
        elseif self.cur_rotation_mode == 1 then
            -- (0,0) is at bottom left of screen
            x = x + vy2
            y = y + self.viewport.x
        elseif self.cur_rotation_mode == 2 then
            -- (0,0) is at bottom right of screen
            x = x + vx2
            y = y + vy2
        else
            -- (0,0) is at top right of screen
            x = x + self.viewport.y
            y = y + vx2
        end
    end
    self.fb:refresh(refresh_type, waveform_mode, wait_for_marker, x, y, w, h)
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
    self.bb:rotateAbsolute(-90 * (mode - self.native_rotation_mode - self.blitbuffer_rotation_mode))
    if self.viewport then
        self.fb.bb:setRotation(self.bb:getRotation())
    end
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

function Screen:toggleNightMode()
    self.bb:invert()
    if self.viewport then
        -- invert and blank out the full framebuffer when we are working on a viewport
        self.fb.bb:invert()
        self.fb.bb:fill(Blitbuffer.COLOR_WHITE)
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
