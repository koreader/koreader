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

local Blitbuffer        = require("ffi/blitbuffer")
local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
local Device            = require("device")
local GestureRange      = require("ui/gesturerange")
local Geom              = require("ui/geometry")
local InputContainer    = require("ui/widget/container/inputcontainer")
local PenDev            = require("input/pendev")
local Screen            = Device.screen
local UIManager         = require("ui/uimanager")
local logger            = require("logger")
local utils             = require("lib/canvas_utils")

-- Exit-zone tap area (top-left square, in pixels)
local EXIT_ZONE_SIZE = 60

-- Menu button (bottom-right corner)
-- Visual square drawn in paintTo(); tap zone extends MENU_BTN_HIT_PAD beyond.
local MENU_BTN_SIZE    = 80   -- visible button size (px)
local MENU_BTN_MARGIN  = 24   -- gap from screen edge to button edge (px)
local MENU_BTN_HIT_PAD =  8   -- extra tap-zone padding beyond visual bounds (px)

-- Default stroke appearance
local DEFAULT_LINE_WIDTH = 3
local STROKE_COLOR = Blitbuffer.COLOR_BLACK

-- Rotation mode constants used for menu-driven orientation change.
-- Mirror KOReader's Screen.DEVICE_ROTATED_* values without requiring a
-- Screen reference at module load time.
local ROT_PORTRAIT  = 0  -- DEVICE_ROTATED_UPRIGHT
local ROT_LANDSCAPE = 3  -- DEVICE_ROTATED_COUNTER_CLOCKWISE (buttons at bottom on Kobo Libra)

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

    -- Orientation lock.
    -- init_rotation_mode is injected from main.lua (from Config):
    --   "auto" or nil  — lock to whatever rotation is active when canvas opens
    --   0/1/2/3        — force a specific rotation on open
    -- _rotation_mode holds the active locked mode (set in init, updated by menu).
    init_rotation_mode = nil,
    _rotation_mode = nil,

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

    -- Orientation lock: apply config-specified rotation (if any), then record
    -- the active mode.  From this point on, onSetRotationMode() re-asserts
    -- this mode whenever KOReader tries to auto-rotate the device.
    if type(self.init_rotation_mode) == "number" then
        Screen:setRotationMode(self.init_rotation_mode)
    end
    self._rotation_mode = Screen:getRotationMode()
    logger.dbg("FastNote canvas: orientation locked to mode", self._rotation_mode)

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

    -- Menu button: tap in the bottom-right corner.
    -- Always registered (never gated by finger_draw) so the user can always
    -- reach the menu regardless of input mode.
    -- Hit zone is MENU_BTN_HIT_PAD larger than the visual on each side.
    local btn_vis_x = self.dimen.w - MENU_BTN_MARGIN - MENU_BTN_SIZE
    local btn_vis_y = self.dimen.h - MENU_BTN_MARGIN - MENU_BTN_SIZE
    self.ges_events.MenuTap = {
        GestureRange:new{
            ges   = "tap",
            range = Geom:new{
                x = btn_vis_x - MENU_BTN_HIT_PAD,
                y = btn_vis_y - MENU_BTN_HIT_PAD,
                w = MENU_BTN_SIZE + MENU_BTN_HIT_PAD * 2,
                h = MENU_BTN_SIZE + MENU_BTN_HIT_PAD * 2,
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

    -- Draw menu button overlay directly onto the screen buffer.
    -- This is drawn AFTER blitting the drawing surface so it always appears
    -- on top and is never overwritten by strokes.
    local bx = x + self.dimen.w - MENU_BTN_MARGIN - MENU_BTN_SIZE
    local by = y + self.dimen.h - MENU_BTN_MARGIN - MENU_BTN_SIZE

    -- Dark background square
    bb:paintRect(bx, by, MENU_BTN_SIZE, MENU_BTN_SIZE, Blitbuffer.COLOR_BLACK)

    -- Hamburger icon: three white horizontal bars
    -- Bar width = 60 % of button width, centred horizontally.
    -- Bar heights and Y positions are hand-tuned for an 80 px square.
    local bar_w = math.floor(MENU_BTN_SIZE * 0.60)  -- 48 px
    local bar_h = 4
    local bar_x = bx + math.floor((MENU_BTN_SIZE - bar_w) / 2)
    bb:paintRect(bar_x, by + 22, bar_w, bar_h, Blitbuffer.COLOR_WHITE)
    bb:paintRect(bar_x, by + 36, bar_w, bar_h, Blitbuffer.COLOR_WHITE)
    bb:paintRect(bar_x, by + 50, bar_w, bar_h, Blitbuffer.COLOR_WHITE)
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

function DrawingCanvas:onMenuTap()
    logger.dbg("FastNote canvas: menu tap")
    local cur = self._rotation_mode
    local portrait_label  = (cur == ROT_PORTRAIT)  and "Portrait \xE2\x9C\x93"  or "Portrait"
    local landscape_label = (cur == ROT_LANDSCAPE) and "Landscape \xE2\x9C\x93" or "Landscape"
    local menu
    menu = ButtonDialogTitle:new{
        title = "Fast Note",
        buttons = {
            {
                {
                    text = portrait_label,
                    callback = function()
                        UIManager:close(menu)
                        self:_reinitAtRotation(ROT_PORTRAIT)
                    end,
                },
                {
                    text = landscape_label,
                    callback = function()
                        UIManager:close(menu)
                        self:_reinitAtRotation(ROT_LANDSCAPE)
                    end,
                },
            },
            {
                {
                    text = "Keep drawing",
                    callback = function()
                        UIManager:close(menu)
                    end,
                },
                {
                    text = "Close canvas",
                    callback = function()
                        UIManager:close(menu)
                        self:_doClose()
                    end,
                },
            },
        },
    }
    UIManager:show(menu)
    return true
end

--- Block accelerometer-driven auto-rotation while the canvas is open.
-- When KOReader detects a device rotation it calls Screen:setRotationMode()
-- and then broadcasts a SetRotationMode event.  We intercept that event and
-- immediately re-lock to self._rotation_mode, keeping the canvas stable.
-- The user can still change orientation deliberately via the canvas menu
-- (which calls _reinitAtRotation directly, not through this path).
function DrawingCanvas:onSetRotationMode(event)
    local new_mode = type(event) == "number" and event
                     or (type(event) == "table" and event[1] or nil)
    if new_mode ~= nil and new_mode ~= self._rotation_mode then
        logger.dbg("FastNote canvas: blocking auto-rotation to mode", new_mode,
                   "(locked to", self._rotation_mode, ")")
        Screen:setRotationMode(self._rotation_mode)
        UIManager:setDirty(self, "full")
    end
    return true  -- consume: we are the active full-screen widget
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

--- Update the MenuTap gesture zone to match current screen dimensions.
-- Must be called after self.dimen is updated in-place by _reinitAtRotation.
-- ExitTap is always at (0,0) so it needs no update; DrawStroke/DrawStrokeEnd
-- reference self.dimen directly and pick up changes automatically.
function DrawingCanvas:_updateGestureZones()
    if not (self.ges_events.MenuTap and self.ges_events.MenuTap[1]) then return end
    local btn_vis_x = self.dimen.w - MENU_BTN_MARGIN - MENU_BTN_SIZE
    local btn_vis_y = self.dimen.h - MENU_BTN_MARGIN - MENU_BTN_SIZE
    local r = self.ges_events.MenuTap[1].range
    r.x = btn_vis_x - MENU_BTN_HIT_PAD
    r.y = btn_vis_y - MENU_BTN_HIT_PAD
    r.w = MENU_BTN_SIZE + MENU_BTN_HIT_PAD * 2
    r.h = MENU_BTN_SIZE + MENU_BTN_HIT_PAD * 2
end

--- Apply a rotation change requested from the canvas menu.
-- Sets the new rotation, reallocates the BlitBuffer at the updated screen
-- dimensions (clearing the current drawing — stroke persistence comes in
-- Stage 4), and triggers a full repaint.
-- @param  new_mode  integer  rotation constant (e.g. ROT_PORTRAIT = 0)
function DrawingCanvas:_reinitAtRotation(new_mode)
    if new_mode == self._rotation_mode then return end
    logger.dbg("FastNote canvas: rotating to mode", new_mode)

    Screen:setRotationMode(new_mode)
    self._rotation_mode = new_mode

    -- Update self.dimen IN-PLACE so that GestureRange objects holding a
    -- reference to self.dimen (DrawStroke, DrawStrokeEnd) pick up new dims.
    self.dimen.w = Screen:getWidth()
    self.dimen.h = Screen:getHeight()

    -- Reallocate the backing BlitBuffer at the new screen dimensions.
    -- This clears the current drawing (Stage 4 will preserve strokes on rotate).
    if self._bb then self._bb:free() end
    local bbtype = Screen:isColorEnabled()
        and Blitbuffer.TYPE_BBRGB32
        or  Blitbuffer.TYPE_BB8
    self._bb = Blitbuffer.new(self.dimen.w, self.dimen.h, bbtype)
    self._bb:fill(Blitbuffer.COLOR_WHITE)

    -- Reset per-stroke state (old screen coordinates are invalid after rotation)
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
