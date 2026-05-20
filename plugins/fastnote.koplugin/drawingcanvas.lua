--[[--
DrawingCanvas — Stage 3 / Stage 4 implementation.

Full-screen drawing canvas backed by a BlitBuffer and a StrokeBuffer.

Input paths (selected by use_raw_input flag):
  • Gesture layer (use_raw_input = false, emulator / fallback):
      pan gesture → draw segment; pan_release → flash refresh.
      Always registered; on device the handler returns early unless
      finger_draw is true — see onDrawStroke.
  • Raw evdev (use_raw_input = true, device-only):
      _pollPen loop at ~120 Hz reads Wacom events.
      _pollTouch loop at ~60 Hz reads touch events, filtered by PalmReject.
      Supports pressure-sensitive line width and palm rejection.

Stage 4: StrokeBuffer is the source of truth.  BlitBuffer is a display cache
rebuilt by repaintTo after undo/erase/rotation.

Stage 3: PalmReject gates capacitive touch events through pen-proximity.
Pen-only mode is the default; finger_draw can be toggled in the canvas menu.

Exit zone: tap in the top-left EXIT_ZONE_SIZE × EXIT_ZONE_SIZE area closes
the canvas.

ASSUMES: InputContainer, GestureRange, UIManager, Screen, Blitbuffer are
  available from the KOReader runtime (not required for unit tests of lib/).
--]]--

local Blitbuffer        = require("ffi/blitbuffer")
local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
local Device            = require("device")
local GestureRange      = require("ui/gesturerange")
local Geom              = require("ui/geometry")
local InputContainer    = require("ui/widget/container/inputcontainer")
local PenDev            = require("input/pendev")
local Screen            = Device.screen
local StrokeBuffer      = require("lib/strokebuffer")
local UIManager         = require("ui/uimanager")
local logger            = require("logger")
local utils             = require("lib/canvas_utils")

-- Chrome strip (Stage 7)
local CHROME_HEIGHT     = 56   -- top strip height in pixels
local CHROME_EXIT_W     = 80   -- width of exit tap area (left)
local CHROME_TOOLS_W    = 80   -- width of tools tap area (right)

-- Default stroke appearance
local DEFAULT_LINE_WIDTH = 4
local STROKE_COLOR       = Blitbuffer.COLOR_BLACK
local DEFAULT_COLOR      = "#000000"

-- Eraser (Stage 10)
local ERASER_RADIUS = 24       -- stroke-erase hit radius in pixels

-- Rotation mode constants
local ROT_PORTRAIT  = 0  -- DEVICE_ROTATED_UPRIGHT
local ROT_LANDSCAPE = 3  -- DEVICE_ROTATED_COUNTER_CLOCKWISE

---@class DrawingCanvas : InputContainer
local DrawingCanvas = InputContainer:extend{
    on_close_callback  = nil,
    on_save_callback   = nil,      -- called with path after each save (Stage 5)
    load_path          = nil,      -- if set, load this SVG on init (Stage 5)

    _bb           = nil,           -- BlitBuffer (display cache)
    _stroke_buf   = nil,           -- StrokeBuffer (source of truth, Stage 4)
    _current_color = DEFAULT_COLOR,

    _page_path  = nil,             -- path of the current page SVG (Stage 5)
    _page_dirty = false,           -- true when strokes added since last save

    -- Chrome (Stage 7)
    page_index  = 1,               -- current page number (set by caller)
    page_count  = 1,               -- total pages in notebook (set by caller)

    -- Eraser (Stage 10)
    _eraser_mode = false,          -- true while eraser end of stylus is active

    use_raw_input      = false,    -- false = gesture layer; true = raw evdev
    finger_draw        = false,    -- allow capacitive touch to draw (pen-only default)

    init_rotation_mode = nil,
    _rotation_mode     = nil,

    _pendev    = nil,              -- PenDev instance
    _touchdev  = nil,              -- TouchDev instance (Stage 3)
    _palmreject = nil,             -- PalmReject instance (Stage 3)

    -- Raw pen tracking (raw input path)
    _last_pen_x = nil,
    _last_pen_y = nil,

    -- Gesture path tracking
    _stroke_x     = nil,
    _stroke_y     = nil,
    _stroke_min_x = nil,
    _stroke_min_y = nil,
    _stroke_max_x = nil,
    _stroke_max_y = nil,
}

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

function DrawingCanvas:init()
    self.dimen = Geom:new{x=0, y=0,
                          w=Screen:getWidth(), h=Screen:getHeight()}

    -- Always use 8-bit buffer: paintLine is only implemented for BB8 in
    -- KOReader's blitbuffer library. blitFrom handles the BB8→screen conversion
    -- (including BBRGB32 on color e-ink). Stage 12 will revisit for color ink.
    self._bb = Blitbuffer.new(self.dimen.w, self.dimen.h, Blitbuffer.TYPE_BB8)
    self._bb:fill(Blitbuffer.COLOR_WHITE)

    self._stroke_buf = StrokeBuffer.new()

    logger.dbg("FastNote canvas: init", self.dimen.w, "x", self.dimen.h,
               "color=", Screen:isColorEnabled())

    self.use_raw_input = Device:isKobo()

    -- Digitizer → portrait-screen transform offset.
    -- Kobo always swaps X/Y in its touch adjustment hook (touch_switch_xy=true).
    -- KoboMonza (Libra Colour) additionally mirrors Y after the swap.
    -- The combined effect is a 90° CCW rotation of the digitizer coordinate system
    -- relative to KOReader's canonical portrait, equivalent to _dig_rot_base = 3
    -- (i.e., use the rot-3 formula when screen rotation is 0, etc.).
    -- mirror_x only (e.g. some older Kobos) = +1 offset.
    if Device:isKobo() then
        if Device.touch_mirrored_y then
            self._dig_rot_base = 3
        elseif Device.touch_mirrored_x then
            self._dig_rot_base = 1
        else
            self._dig_rot_base = 3  -- switch_xy alone; treat as mirror_y case
        end
    else
        self._dig_rot_base = 0  -- emulator / Wacom: identity
    end

    -- Disable gyroscope auto-rotation while canvas is open.
    -- The gsensor fires via devicelistener → self.ui:handleEvent, bypassing
    -- our onSetRotationMode handler (which only sees broadcastEvent paths).
    -- toggleGSensor(false) stops MSC_GYRO events from reaching the gesture layer.
    self._gsensor_disabled = false
    if Device:hasGSensor() then
        Device:toggleGSensor(false)
        self._gsensor_disabled = true
        logger.dbg("FastNote canvas: gyroscope auto-rotation disabled")
    end

    -- Orientation lock
    if type(self.init_rotation_mode) == "number" then
        Screen:setRotationMode(self.init_rotation_mode)
    end
    self._rotation_mode = Screen:getRotationMode()
    logger.dbg("FastNote canvas: orientation locked to mode", self._rotation_mode)

    -- ── Gesture zones ──────────────────────────────────────────────────────

    -- Exit zone: left portion of chrome strip
    self.ges_events.ExitTap = {
        GestureRange:new{
            ges   = "tap",
            range = Geom:new{x=0, y=0, w=CHROME_EXIT_W, h=CHROME_HEIGHT},
        },
    }

    -- Tools / menu: right portion of chrome strip
    self.ges_events.MenuTap = {
        GestureRange:new{
            ges   = "tap",
            range = Geom:new{
                x = self.dimen.w - CHROME_TOOLS_W,
                y = 0,
                w = CHROME_TOOLS_W,
                h = CHROME_HEIGHT,
            },
        },
    }

    -- Drawing gesture zones: always registered.
    -- On device (use_raw_input=true), onDrawStroke returns early unless
    -- finger_draw is enabled, keeping the emulator path always working.
    self.ges_events.DrawStroke = {
        GestureRange:new{ges="pan", range=self.dimen},
    }
    self.ges_events.DrawStrokeEnd = {
        GestureRange:new{ges="pan_release", range=self.dimen},
    }

    -- ── Stage 5: load existing page ───────────────────────────────────────

    if self.load_path then
        self:loadPage(self.load_path)
    end

    -- ── Raw input setup ────────────────────────────────────────────────────

    if self.use_raw_input then
        -- Pen device
        local pen_path = PenDev.find()
        if pen_path then
            local pd, err = PenDev.open(pen_path)
            if pd then
                self._pendev = pd
                UIManager:scheduleIn(0.008, function() self:_pollPen() end)
                logger.dbg("FastNote canvas: raw pen enabled:", pen_path)
            else
                logger.warn("FastNote canvas: pendev open failed:", err,
                            "— falling back to gesture layer")
                self.use_raw_input = false
            end
        else
            logger.warn("FastNote canvas: pen digitizer not found — falling back to gesture layer")
            self.use_raw_input = false
        end

        -- Touch device (Stage 3 palm rejection)
        local ok_touch, TouchDev = pcall(require, "input/touchdev")
        if ok_touch then
            local touch_path = TouchDev.find()
            if touch_path then
                local td, err = TouchDev.open(touch_path)
                if td then
                    self._touchdev = td
                    local PalmReject = require("lib/palmreject")
                    self._palmreject = PalmReject.new()
                    UIManager:scheduleIn(0.016, function() self:_pollTouch() end)
                    logger.dbg("FastNote canvas: touch + palm rejection enabled:", touch_path)
                else
                    logger.warn("FastNote canvas: touchdev open failed:", err)
                end
            end
        end
    end
end

function DrawingCanvas:onCloseWidget()
    logger.dbg("FastNote canvas: onCloseWidget, freeing resources")
    if self._pendev then
        self._pendev:close()
        self._pendev = nil
    end
    if self._touchdev then
        self._touchdev:close()
        self._touchdev = nil
    end
    if self._bb then
        self._bb:free()
        self._bb = nil
    end
    -- Re-enable gyroscope that was disabled on init
    if self._gsensor_disabled then
        Device:toggleGSensor(true)
        logger.dbg("FastNote canvas: gyroscope auto-rotation restored")
    end
end

-- ---------------------------------------------------------------------------
-- Rendering
-- ---------------------------------------------------------------------------

function DrawingCanvas:paintTo(bb, x, y)
    self.dimen.x = x
    self.dimen.y = y
    if not self._bb then return end
    bb:blitFrom(self._bb, x, y, 0, 0, self.dimen.w, self.dimen.h)
    self:_paintChrome(bb, x, y)
end

--- Draw the chrome strip directly into the screen buffer (always on top of strokes).
function DrawingCanvas:_paintChrome(bb, x, y)
    local W = self.dimen.w

    -- White background
    bb:paintRect(x, y, W, CHROME_HEIGHT, Blitbuffer.COLOR_WHITE)
    -- 2 px bottom border
    bb:paintRect(x, y + CHROME_HEIGHT - 2, W, 2, Blitbuffer.COLOR_BLACK)

    -- Exit "×": two diagonal lines in the left zone
    local pad = 16
    local sz  = CHROME_HEIGHT - pad * 2
    local ex, ey = x + pad, y + pad
    utils.drawLine(bb, ex, ey, ex + sz, ey + sz, 3, Blitbuffer.COLOR_BLACK)
    utils.drawLine(bb, ex + sz, ey, ex, ey + sz, 3, Blitbuffer.COLOR_BLACK)

    -- Page indicator: "n / N" centered (attempt RenderText; skip silently if unavailable)
    local ok_f, Font = pcall(require, "ui/font")
    local ok_r, RT   = pcall(require, "ui/rendertext")
    if ok_f and ok_r then
        local face = Font:getFace("cfont", 22)
        if face then
            local page_str = tostring(self.page_index) .. " / " .. tostring(self.page_count)
            -- Estimate text width (≈ 13 px per char at size 22)
            local tw  = #page_str * 13
            local tx  = x + math.floor((W - tw) / 2)
            local ty  = y + CHROME_HEIGHT - 16  -- baseline
            RT:renderUtf8Text(bb, tx, ty, face, page_str)
        end
    end

    -- Tools hamburger (right zone): three horizontal bars
    local bar_w = 36
    local bar_h = 4
    local bx    = x + W - CHROME_TOOLS_W + math.floor((CHROME_TOOLS_W - bar_w) / 2)
    local by0   = y + 12
    bb:paintRect(bx, by0,      bar_w, bar_h, Blitbuffer.COLOR_BLACK)
    bb:paintRect(bx, by0 + 14, bar_w, bar_h, Blitbuffer.COLOR_BLACK)
    bb:paintRect(bx, by0 + 28, bar_w, bar_h, Blitbuffer.COLOR_BLACK)
end

-- ---------------------------------------------------------------------------
-- Gesture handlers
-- ---------------------------------------------------------------------------

function DrawingCanvas:onExitTap(_, ges)
    if utils.point_in_zone(ges.pos.x, ges.pos.y,
                           0, 0, CHROME_EXIT_W, CHROME_HEIGHT) then
        logger.dbg("FastNote canvas: exit tap")
        self:_doClose()
        return true
    end
end

function DrawingCanvas:onMenuTap()
    logger.dbg("FastNote canvas: menu tap")
    local cur           = self._rotation_mode
    local portrait_lbl  = (cur == ROT_PORTRAIT)  and "Portrait \xE2\x9C\x93"  or "Portrait"
    local landscape_lbl = (cur == ROT_LANDSCAPE) and "Landscape \xE2\x9C\x93" or "Landscape"
    local finger_lbl    = self.finger_draw and "Finger draw: on" or "Finger draw: off"
    local menu

    menu = ButtonDialogTitle:new{
        title = "Fast Note",
        buttons = {
            -- Row 1: orientation
            {
                {text = portrait_lbl,
                 callback = function()
                     UIManager:close(menu)
                     self:_reinitAtRotation(ROT_PORTRAIT)
                 end},
                {text = landscape_lbl,
                 callback = function()
                     UIManager:close(menu)
                     self:_reinitAtRotation(ROT_LANDSCAPE)
                 end},
            },
            -- Row 2: undo / redo (Stage 11)
            {
                {text = "Undo",
                 callback = function()
                     UIManager:close(menu)
                     if self._stroke_buf:undo() then
                         self._page_dirty = true
                         self:_repaintAll()
                     end
                 end},
                {text = "Redo",
                 callback = function()
                     UIManager:close(menu)
                     if self._stroke_buf:redo() then
                         self._page_dirty = true
                         self:_repaintAll()
                     end
                 end},
            },
            -- Row 3: finger draw / save
            {
                {text = finger_lbl,
                 callback = function()
                     UIManager:close(menu)
                     self.finger_draw = not self.finger_draw
                     logger.dbg("FastNote canvas: finger_draw =", self.finger_draw)
                 end},
                {text = "Save",
                 callback = function()
                     UIManager:close(menu)
                     self:_saveDrawing()
                 end},
            },
            -- Row 4: keep / close
            {
                {text = "Keep drawing",
                 callback = function() UIManager:close(menu) end},
                {text = "Close canvas",
                 callback = function()
                     UIManager:close(menu)
                     self:_doClose()
                 end},
            },
        },
    }
    UIManager:show(menu)
    return true
end

--- Block accelerometer auto-rotation while the canvas is open.
function DrawingCanvas:onSetRotationMode(event)
    local new_mode = type(event) == "number" and event
                     or (type(event) == "table" and event[1] or nil)
    if new_mode ~= nil and new_mode ~= self._rotation_mode then
        logger.dbg("FastNote canvas: blocking auto-rotation to", new_mode)
        Screen:setRotationMode(self._rotation_mode)
        UIManager:setDirty(self, "full")
    end
    return true
end

function DrawingCanvas:onDrawStroke(_, ges)
    -- On device, gesture path is only active when finger_draw is enabled.
    if self.use_raw_input and not self.finger_draw then return end
    if not self._bb then return end

    local x = math.floor(ges.pos.x)
    local y = math.floor(ges.pos.y)

    -- Ignore strokes in the chrome strip
    if y < CHROME_HEIGHT then return end
    local prev_x = self._stroke_x or x
    local prev_y = self._stroke_y or y

    -- StrokeBuffer: start or extend current stroke
    if not self._stroke_buf.current then
        self._stroke_buf:penDown(prev_x, prev_y, DEFAULT_LINE_WIDTH, self._current_color)
    end
    self._stroke_buf:penMove(x, y, DEFAULT_LINE_WIDTH)

    utils.drawLine(self._bb, prev_x, prev_y, x, y, DEFAULT_LINE_WIDTH, STROKE_COLOR)

    self._stroke_min_x = math.min(self._stroke_min_x or x, prev_x, x)
    self._stroke_min_y = math.min(self._stroke_min_y or y, prev_y, y)
    self._stroke_max_x = math.max(self._stroke_max_x or x, prev_x, x)
    self._stroke_max_y = math.max(self._stroke_max_y or y, prev_y, y)
    self._stroke_x     = x
    self._stroke_y     = y

    local dirty = utils.compute_dirty_rect(prev_x, prev_y, x, y, DEFAULT_LINE_WIDTH)
    UIManager:setDirty(self, function() return "fast", Geom:new(dirty) end)
    return true
end

function DrawingCanvas:onDrawStrokeEnd(_, ges)
    if self.use_raw_input and not self.finger_draw then return end
    if not self._bb then return end

    if ges and ges.pos then
        local x = math.floor(ges.pos.x)
        local y = math.floor(ges.pos.y)
        if self._stroke_x and self._stroke_y then
            self._stroke_buf:penMove(x, y, DEFAULT_LINE_WIDTH)
            utils.drawLine(self._bb, self._stroke_x, self._stroke_y,
                           x, y, DEFAULT_LINE_WIDTH, STROKE_COLOR)
        end
        self._stroke_max_x = math.max(self._stroke_max_x or x, x)
        self._stroke_max_y = math.max(self._stroke_max_y or y, y)
        self._stroke_min_x = math.min(self._stroke_min_x or x, x)
        self._stroke_min_y = math.min(self._stroke_min_y or y, y)
    end

    self._stroke_buf:penUp()
    self._page_dirty = true

    if self._stroke_min_x then
        local stroke_rect = utils.compute_dirty_rect(
            self._stroke_min_x, self._stroke_min_y,
            self._stroke_max_x, self._stroke_max_y,
            DEFAULT_LINE_WIDTH)
        UIManager:setDirty(self, function() return "ui", Geom:new(stroke_rect) end)
    end

    self._stroke_x     = nil
    self._stroke_y     = nil
    self._stroke_min_x = nil
    self._stroke_min_y = nil
    self._stroke_max_x = nil
    self._stroke_max_y = nil
    return true
end

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

--- Translate raw Wacom digitizer coordinates to screen pixels.
-- Handles all four rotation modes.  Uses the canvas-locked rotation
-- (self._rotation_mode) rather than Screen:getRotationMode() to avoid
-- any race with auto-rotation blocking.
-- @number rx  raw digitizer x (from pendev)
-- @number ry  raw digitizer y
-- @return sx, sy  integer screen coordinates
function DrawingCanvas:_digToScreen(rx, ry)
    local pd  = self._pendev
    local W   = Screen:getWidth()
    local H   = Screen:getHeight()
    local nx  = (rx - pd.x_min) / (pd.x_max - pd.x_min)
    local ny  = (ry - pd.y_min) / (pd.y_max - pd.y_min)
    -- Clamp to [0,1] in case of out-of-range values during fast movement
    nx = math.max(0, math.min(1, nx))
    ny = math.max(0, math.min(1, ny))

    -- _dig_rot_base accounts for the device's axis-swap/mirror hook so that
    -- (nx, ny) are interpreted in the digitizer's native space, not portrait space.
    -- For KoboMonza (switch_xy + mirror_y): base = 3.
    -- Composing with _rotation_mode gives the effective transform to apply.
    local rot = (self._rotation_mode + self._dig_rot_base) % 4
    if     rot == 0 then
        return math.floor(nx * (W-1)), math.floor(ny * (H-1))
    elseif rot == 1 then
        return math.floor((1-ny) * (W-1)), math.floor(nx  * (H-1))
    elseif rot == 2 then
        return math.floor((1-nx) * (W-1)), math.floor((1-ny) * (H-1))
    elseif rot == 3 then
        return math.floor(ny     * (W-1)), math.floor((1-nx) * (H-1))
    end
    return math.floor(nx * (W-1)), math.floor(ny * (H-1))
end

function DrawingCanvas:_updateGestureZones()
    -- After rotation dimen.w changes; MenuTap x must track the right edge.
    -- ExitTap is always at x=0 so it never needs updating.
    if not (self.ges_events.MenuTap and self.ges_events.MenuTap[1]) then return end
    local r = self.ges_events.MenuTap[1].range
    r.x = self.dimen.w - CHROME_TOOLS_W
    r.y = 0
    r.w = CHROME_TOOLS_W
    r.h = CHROME_HEIGHT
end

--- Repaint all strokes into the BlitBuffer and request a UI refresh.
-- Use after undo, redo, or erase to rebuild the display cache.
function DrawingCanvas:_repaintAll()
    if not self._bb then return end
    self._bb:fill(Blitbuffer.COLOR_WHITE)
    if self._stroke_buf then self._stroke_buf:repaintTo(self._bb) end
    UIManager:setDirty(self, "ui")
end

--- Apply a rotation change from the canvas menu.
-- After Stage 4: strokes are preserved via repaintTo.
function DrawingCanvas:_reinitAtRotation(new_mode)
    if new_mode == self._rotation_mode then return end
    logger.dbg("FastNote canvas: rotating to mode", new_mode)

    Screen:setRotationMode(new_mode)
    self._rotation_mode = new_mode

    self.dimen.w = Screen:getWidth()
    self.dimen.h = Screen:getHeight()

    if self._bb then self._bb:free() end
    self._bb = Blitbuffer.new(self.dimen.w, self.dimen.h, Blitbuffer.TYPE_BB8)
    self._bb:fill(Blitbuffer.COLOR_WHITE)

    -- Replay strokes into the new buffer (Stage 4: preserve on rotate)
    self:_repaintAll()

    -- Reset per-stroke state (old screen coords are invalid after rotation)
    self._last_pen_x   = nil
    self._last_pen_y   = nil
    self._stroke_x     = nil
    self._stroke_y     = nil
    self._stroke_min_x = nil
    self._stroke_min_y = nil
    self._stroke_max_x = nil
    self._stroke_max_y = nil

    self:_updateGestureZones()
    UIManager:setDirty(self, "full")
end

--- Raw pen poll loop at ~120 Hz.
function DrawingCanvas:_pollPen()
    if not self._pendev then return end

    self._pendev:poll(function(ev)
        -- Feed pen event to palm rejection state machine (Stage 3)
        if self._palmreject then
            self._palmreject:onPenEvent(ev)
        end

        if ev.type == "down" or ev.type == "move" then
            local sx, sy = self:_digToScreen(ev.x, ev.y)

            -- Chrome strip: abort any open stroke and ignore the event
            if sy < CHROME_HEIGHT then
                if self._last_pen_x then
                    self._stroke_buf:penUp()
                    self._last_pen_x = nil
                    self._last_pen_y = nil
                end
                return
            end

            -- ── Eraser mode (Stage 10) ────────────────────────────────────
            if ev.type == "down" and ev.tool == "eraser" then
                self._eraser_mode = true
                self._stroke_buf:penUp()   -- commit any open pen stroke
                self._last_pen_x = nil
                self._last_pen_y = nil
            end

            if self._eraser_mode then
                local removed = self._stroke_buf:eraseAt(sx, sy, ERASER_RADIUS)
                if #removed > 0 then
                    self._page_dirty = true
                    self:_repaintAll()
                end
                return
            end

            -- ── Pen drawing ───────────────────────────────────────────────
            local lw = utils.pressure_to_width(ev.pressure, self._pendev.p_max, 1, 8)

            if ev.type == "down" then
                self._stroke_buf:penDown(sx, sy, lw, self._current_color)
            else
                self._stroke_buf:penMove(sx, sy, lw)
            end

            if self._last_pen_x then
                utils.drawLine(self._bb,
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
            self._eraser_mode = false
            self._stroke_buf:penUp()
            self._page_dirty = true
            self._last_pen_x = nil
            self._last_pen_y = nil
            UIManager:setDirty(self, "ui")
        end
    end)

    if self._pendev then
        UIManager:scheduleIn(0.008, function() self:_pollPen() end)
    end
end

--- Raw touch poll loop at ~60 Hz (Stage 3).
-- Events are filtered through PalmReject before acting on them.
function DrawingCanvas:_pollTouch()
    if not self._touchdev then return end

    self._touchdev:poll(function(slot_ev)
        -- Filter through palm rejection
        local filtered = self._palmreject
            and self._palmreject:onTouchEvent(slot_ev)
            or  slot_ev

        if filtered and self.finger_draw then
            -- Touch drawing path (finger_draw is on):
            -- treat touch events like pen events using DEFAULT_LINE_WIDTH.
            if filtered.type == "down" then
                self._stroke_buf:penDown(filtered.x, filtered.y,
                                         DEFAULT_LINE_WIDTH, self._current_color)
                self._last_pen_x = filtered.x
                self._last_pen_y = filtered.y
            elseif filtered.type == "move" then
                self._stroke_buf:penMove(filtered.x, filtered.y, DEFAULT_LINE_WIDTH)
                if self._last_pen_x then
                    utils.drawLine(self._bb, self._last_pen_x, self._last_pen_y,
                                   filtered.x, filtered.y,
                                   DEFAULT_LINE_WIDTH, STROKE_COLOR)
                    local dirty = utils.compute_dirty_rect(
                        self._last_pen_x, self._last_pen_y,
                        filtered.x, filtered.y, DEFAULT_LINE_WIDTH)
                    UIManager:setDirty(self, function()
                        return "fast", Geom:new(dirty)
                    end)
                end
                self._last_pen_x = filtered.x
                self._last_pen_y = filtered.y
            elseif filtered.type == "up" then
                self._stroke_buf:penUp()
                self._page_dirty = true
                self._last_pen_x = nil
                self._last_pen_y = nil
                UIManager:setDirty(self, "ui")
            end
        end
    end)

    if self._touchdev then
        UIManager:scheduleIn(0.016, function() self:_pollTouch() end)
    end
end

--- Load an SVG page into this canvas, replacing the current StrokeBuffer.
-- Safe to call during init (before the widget is on the UIManager stack).
-- @string path  Absolute path to the SVG file.
-- @return boolean  true on success
function DrawingCanvas:loadPage(path)
    -- Always claim this path for saves, even if the file doesn't exist yet
    -- (new notebook pages are created on first save, not on open).
    self._page_path  = path
    self._page_dirty = false

    local f = io.open(path, "r")
    if not f then
        logger.dbg("FastNote canvas: loadPage: new page at", path)
        return false
    end
    local text = f:read("*a")
    f:close()

    local ok_svg, svg_module = pcall(require, "lib/svg")
    if not ok_svg then
        logger.warn("FastNote canvas: loadPage: svg unavailable:", svg_module)
        return false
    end

    local ok, sb = pcall(svg_module.read, text)
    if not ok or not sb then
        logger.warn("FastNote canvas: loadPage: svg.read failed")
        return false
    end

    self._stroke_buf = sb
    self._page_path  = path
    self._page_dirty = false

    if self._bb then
        self._bb:fill(Blitbuffer.COLOR_WHITE)
        self._stroke_buf:repaintTo(self._bb)
        UIManager:setDirty(self, "full")
    end

    logger.dbg("FastNote canvas: loadPage", path,
               "(" .. #sb.strokes .. " strokes)")
    return true
end

--- Save current drawing.
-- If _page_path is set, saves back to that file (round-trip).
-- Otherwise creates a timestamped file and sets _page_path to it.
function DrawingCanvas:_saveDrawing()
    if self._stroke_buf:isEmpty() then
        logger.dbg("FastNote canvas: nothing to save")
        return
    end

    local ok_svg, svg_module = pcall(require, "lib/svg")
    if not ok_svg then
        logger.warn("FastNote canvas: svg module unavailable:", svg_module)
        return
    end

    local DataStorage = require("datastorage")
    local save_dir    = DataStorage:getDataDir() .. "/fastnote/"
    os.execute("mkdir -p " .. save_dir)

    local path = self._page_path
    if not path then
        local filename = os.date("fastnote_%Y-%m-%d_%H-%M-%S.svg")
        path = save_dir .. filename
    end

    local f = io.open(path, "w")
    if not f then
        logger.warn("FastNote canvas: cannot write to", path)
        return
    end
    f:write(svg_module.write(self._stroke_buf, self.dimen.w, self.dimen.h))
    f:close()

    self._page_path  = path
    self._page_dirty = false
    if self.on_save_callback then self.on_save_callback(path) end

    local name = path:match("[^/]+$") or path
    local InfoMessage = require("ui/widget/infomessage")
    UIManager:show(InfoMessage:new{text = "Saved: " .. name, timeout = 2})
    logger.dbg("FastNote canvas: saved to", path)
end

function DrawingCanvas:_doClose()
    -- Auto-save back to _page_path if there are new strokes since last save.
    if self._page_path and self._page_dirty and not self._stroke_buf:isEmpty() then
        local ok_svg, svg_module = pcall(require, "lib/svg")
        if ok_svg then
            local f = io.open(self._page_path, "w")
            if f then
                f:write(svg_module.write(self._stroke_buf, self.dimen.w, self.dimen.h))
                f:close()
                self._page_dirty = false
                if self.on_save_callback then
                    self.on_save_callback(self._page_path)
                end
                logger.dbg("FastNote canvas: auto-saved to", self._page_path)
            end
        end
    end
    -- Full refresh after close so the underlying UI redraws cleanly.
    UIManager:close(self)
    UIManager:setDirty(nil, "full")
    if self.on_close_callback then
        self.on_close_callback()
    end
end

return DrawingCanvas
