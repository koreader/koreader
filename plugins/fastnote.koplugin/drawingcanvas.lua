--[[--
DrawingCanvas — Stage 2 implementation.

Full-screen drawing canvas backed by a BlitBuffer.

Input paths (selected by use_raw_input flag):
  • Gesture layer (use_raw_input = false, emulator / fallback):
      pan gesture → draw segment; pan_release → flash refresh.
  • Raw evdev (use_raw_input = true, device-only):
      UIManager:scheduleIn loop polls pendev at ~120 Hz.
      Supports pressure-sensitive line width.

Exit zone: tap in the top-left EXIT_ZONE_SIZE × EXIT_ZONE_SIZE area closes
the canvas.

Not yet implemented:
  - StrokeBuffer / undo model (Stage 4)
  - SVG persistence (Stage 5)
  - Palm rejection (Stage 3)

ASSUMES: InputContainer, GestureRange, UIManager, Screen, Blitbuffer are
  available from the KOReader runtime (not required for unit tests of lib/).
--]]--

local Blitbuffer     = require("ffi/blitbuffer")
local Device         = require("device")
local GestureRange   = require("ui/gesturerange")
local Geom           = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")
local PenDev         = require("input/pendev")
local Screen         = Device.screen
local UIManager      = require("ui/uimanager")
local logger         = require("logger")
local utils          = require("lib/canvas_utils")

-- Exit-zone tap area (top-left square, in pixels)
local EXIT_ZONE_SIZE = 60

-- Default stroke appearance
local DEFAULT_LINE_WIDTH = 3
local STROKE_COLOR = Blitbuffer.COLOR_BLACK

---@class DrawingCanvas : InputContainer
local DrawingCanvas = InputContainer:extend{
    -- Injected by parent (main.lua)
    on_close_callback = nil,

    -- BlitBuffer backing the drawing surface
    _bb = nil,

    -- Input mode: false = gesture layer (emulator), true = raw evdev (device)
    use_raw_input = false,

    -- When use_raw_input is true: allow capacitive touch to draw as well as pen.
    -- Injected from main.lua via Config.load().  Default false = pen-only.
    finger_draw = false,

    -- Raw pen device (PenDev instance, only when use_raw_input = true)
    _pendev = nil,

    -- Last drawn pen position for line segment continuity (raw input path)
    _last_pen_x = nil,
    _last_pen_y = nil,

    -- Stroke state: last point seen in a pan gesture (gesture path)
    _stroke_x = nil,
    _stroke_y = nil,

    -- Bounding box of the current stroke (for flash refresh on pan_release)
    _stroke_min_x = nil,
    _stroke_min_y = nil,
    _stroke_max_x = nil,
    _stroke_max_y = nil,
}

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

function DrawingCanvas:init()
    self.dimen = Geom:new{
        x = 0,
        y = 0,
        w = Screen:getWidth(),
        h = Screen:getHeight(),
    }

    -- Allocate the backing BlitBuffer (colour or grayscale depending on device)
    local bbtype = Screen:isColorEnabled()
        and Blitbuffer.TYPE_BBRGB32
        or  Blitbuffer.TYPE_BB8

    self._bb = Blitbuffer.new(self.dimen.w, self.dimen.h, bbtype)
    self._bb:fill(Blitbuffer.COLOR_WHITE)

    logger.dbg("FastNote canvas: init", self.dimen.w, "x", self.dimen.h,
               "color=", Screen:isColorEnabled())

    -- Input mode: raw evdev on Kobo device, gesture fallback in emulator
    self.use_raw_input = Device:isKobo()

    -- Register touch zones ------------------------------------------------

    -- Exit zone: tap in the top-left corner
    self.ges_events.ExitTap = {
        GestureRange:new{
            ges   = "tap",
            range = Geom:new{
                x = 0,
                y = 0,
                w = EXIT_ZONE_SIZE,
                h = EXIT_ZONE_SIZE,
            },
        },
    }

    -- Drawing zone: pan anywhere on screen.
    -- Registered when: emulator (gesture is the only input), OR finger_draw is
    -- explicitly enabled on device (touch events draw alongside pen).
    if not self.use_raw_input or self.finger_draw then
        self.ges_events.DrawStroke = {
            GestureRange:new{
                ges   = "pan",
                range = self.dimen,
            },
        }
        self.ges_events.DrawStrokeEnd = {
            GestureRange:new{
                ges   = "pan_release",
                range = self.dimen,
            },
        }
    end

    -- Raw evdev pen polling (device only) ----------------------------------
    if self.use_raw_input then
        local dev_path = PenDev.find()
        if dev_path then
            local pd, err = PenDev.open(dev_path)
            if pd then
                self._pendev = pd
                UIManager:scheduleIn(0.008, function() self:_pollPen() end)
                logger.dbg("FastNote canvas: raw pen input enabled:", dev_path)
            else
                logger.warn("FastNote canvas: pendev open failed:", err)
            end
        else
            logger.warn("FastNote canvas: Wacom not found; using gesture fallback")
        end
    end
end

function DrawingCanvas:onCloseWidget()
    logger.dbg("FastNote canvas: onCloseWidget, freeing bb")
    -- Stop raw pen polling and close fd before freeing the buffer
    if self._pendev then
        self._pendev:close()
        self._pendev = nil
    end
    if self._bb then
        self._bb:free()
        self._bb = nil
    end
end

-- ---------------------------------------------------------------------------
-- Rendering
-- ---------------------------------------------------------------------------

---@param bb BlitBuffer  UIManager's display buffer
---@param x  number
---@param y  number
function DrawingCanvas:paintTo(bb, x, y)
    self.dimen.x = x
    self.dimen.y = y
    if not self._bb then return end
    bb:blitFrom(self._bb, x, y, 0, 0, self.dimen.w, self.dimen.h)
end

-- ---------------------------------------------------------------------------
-- Gesture handlers
-- ---------------------------------------------------------------------------

function DrawingCanvas:onExitTap(_, ges)
    -- Verify the tap lands in the exit zone (belt-and-suspenders)
    if utils.point_in_zone(ges.pos.x, ges.pos.y, 0, 0, EXIT_ZONE_SIZE, EXIT_ZONE_SIZE) then
        logger.dbg("FastNote canvas: exit tap")
        self:_doClose()
        return true
    end
end

function DrawingCanvas:onDrawStroke(_, ges)
    if not self._bb then return end

    local x = math.floor(ges.pos.x)
    local y = math.floor(ges.pos.y)
    local prev_x = self._stroke_x or x
    local prev_y = self._stroke_y or y

    -- Draw the segment onto the backing buffer
    self._bb:paintLine(prev_x, prev_y, x, y, DEFAULT_LINE_WIDTH, STROKE_COLOR)

    -- Update stroke bounding box
    self._stroke_min_x = math.min(self._stroke_min_x or x, prev_x, x)
    self._stroke_min_y = math.min(self._stroke_min_y or y, prev_y, y)
    self._stroke_max_x = math.max(self._stroke_max_x or x, prev_x, x)
    self._stroke_max_y = math.max(self._stroke_max_y or y, prev_y, y)

    self._stroke_x = x
    self._stroke_y = y

    -- Fast partial refresh for the dirty segment
    local dirty = utils.compute_dirty_rect(prev_x, prev_y, x, y, DEFAULT_LINE_WIDTH)
    UIManager:setDirty(self, function()
        return "fast", Geom:new(dirty)
    end)

    logger.dbg("FastNote canvas: draw", prev_x, prev_y, "->", x, y)
    return true
end

function DrawingCanvas:onDrawStrokeEnd(_, ges)
    if not self._bb then return end

    -- Final point of the stroke
    if ges and ges.pos then
        local x = math.floor(ges.pos.x)
        local y = math.floor(ges.pos.y)
        if self._stroke_x and self._stroke_y then
            self._bb:paintLine(self._stroke_x, self._stroke_y,
                               x, y, DEFAULT_LINE_WIDTH, STROKE_COLOR)
        end
        self._stroke_max_x = math.max(self._stroke_max_x or x, x)
        self._stroke_max_y = math.max(self._stroke_max_y or y, y)
        self._stroke_min_x = math.min(self._stroke_min_x or x, x)
        self._stroke_min_y = math.min(self._stroke_min_y or y, y)
    end

    -- Flash refresh for the full stroke bounding box (makes last point crisp)
    if self._stroke_min_x then
        local stroke_rect = utils.compute_dirty_rect(
            self._stroke_min_x, self._stroke_min_y,
            self._stroke_max_x, self._stroke_max_y,
            DEFAULT_LINE_WIDTH
        )
        UIManager:setDirty(self, function()
            return "flash", Geom:new(stroke_rect)
        end)
        logger.dbg("FastNote canvas: stroke end, flash rect",
                   stroke_rect.x, stroke_rect.y, stroke_rect.w, stroke_rect.h)
    end

    -- Reset stroke state
    self._stroke_x    = nil
    self._stroke_y    = nil
    self._stroke_min_x = nil
    self._stroke_min_y = nil
    self._stroke_max_x = nil
    self._stroke_max_y = nil

    return true
end

-- ---------------------------------------------------------------------------
-- Internal
-- ---------------------------------------------------------------------------

--- Raw pen poll loop, scheduled at ~120 Hz when use_raw_input = true.
-- Translates raw Wacom coordinates to screen space, draws pressure-sensitive
-- line segments, and reschedules itself until the canvas is closed.
function DrawingCanvas:_pollPen()
    if not self._pendev then return end

    self._pendev:poll(function(ev)
        if ev.type == "down" or ev.type == "move" then
            -- Translate raw digitizer coords to screen pixels.
            -- Wacom range from PenDev._query_abs (default 0..4095).
            local W  = Screen:getWidth()
            local H  = Screen:getHeight()
            local sx = math.floor(ev.x / self._pendev.x_max * (W - 1))
            local sy = math.floor(ev.y / self._pendev.y_max * (H - 1))
            local lw = utils.pressure_to_width(ev.pressure, self._pendev.p_max, 1, 8)

            if self._last_pen_x then
                self._bb:paintLine(
                    self._last_pen_x, self._last_pen_y, sx, sy, lw, STROKE_COLOR)
                local dirty = utils.compute_dirty_rect(
                    self._last_pen_x, self._last_pen_y, sx, sy, lw)
                UIManager:setDirty(self, function()
                    return "fast", Geom:new(dirty)
                end)
            end
            self._last_pen_x = sx
            self._last_pen_y = sy

        elseif ev.type == "up" then
            self._last_pen_x = nil
            self._last_pen_y = nil
            UIManager:setDirty(self, "flash")
        end
        -- "hover" events are currently ignored (future: cursor preview)
    end)

    -- Reschedule as long as the device is still open
    if self._pendev then
        UIManager:scheduleIn(0.008, function() self:_pollPen() end)
    end
end

function DrawingCanvas:_doClose()
    UIManager:close(self)
    if self.on_close_callback then
        self.on_close_callback()
    end
end

return DrawingCanvas
