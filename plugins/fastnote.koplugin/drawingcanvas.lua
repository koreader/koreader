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
local time              = require("ui/time")
local utils             = require("lib/canvas_utils")

-- Chrome strip (Stage 7)
local CHROME_HEIGHT     = 75   -- top strip height in pixels
local CHROME_EXIT_W     = 80   -- width of exit tap area (left)
local CHROME_TOOLS_W    = 80   -- width of tools tap area (right)

-- Default stroke appearance
local DEFAULT_LINE_WIDTH = 4
local DEFAULT_COLOR      = "#000000"

-- Eraser (Stage 10)
local ERASER_RADIUS = 24       -- stroke-erase hit radius in pixels

-- Poll intervals and idle-save delay
local PEN_POLL_INTERVAL   = 0.008  -- ~120 Hz pen sampling
local TOUCH_POLL_INTERVAL = 0.016  -- ~60 Hz touch sampling
local IDLE_SAVE_DELAY     = 30     -- seconds of inactivity before auto-save

-- 6-color ink palette (Kaleido 3).  Stored as hex; rendered via colorFromString.
local PALETTE = {
    { name = "Black",  hex = "#000000" },
    { name = "Red",    hex = "#cc2222" },
    { name = "Blue",   hex = "#2244cc" },
    { name = "Green",  hex = "#22aa44" },
    { name = "Orange", hex = "#cc7700" },
    { name = "Purple", hex = "#8822bb" },
}

-- Hover-prevention: minimum digitizer pressure to accept a "down" event.
-- The Elan chip can send BTN_TOUCH=1 a few mm above the screen; real contact
-- registers significantly higher pressure than hover proximity.
local MIN_PEN_PRESSURE = 50

-- Rotation mode constants
local ROT_PORTRAIT  = 0  -- DEVICE_ROTATED_UPRIGHT
local ROT_LANDSCAPE = 3  -- DEVICE_ROTATED_COUNTER_CLOCKWISE

---@class DrawingCanvas : InputContainer
local DrawingCanvas = InputContainer:extend{
    on_close_callback    = nil,
    on_save_callback     = nil,    -- called with path after each save (Stage 5)
    on_dark_mode_change  = nil,    -- called with (bool) when dark mode toggles; persist in state
    on_color_change      = nil,    -- called with (hex) when ink color changes; persist in state
    on_pressure_change   = nil,    -- called with (number) when pressure floor changes; persist in state
    on_show_browser      = nil,    -- called when user picks "Notebooks" from hamburger (Stage 9)
    load_path            = nil,    -- if set, load this SVG on init (Stage 5)
    dark_mode            = false,  -- initial dark mode state (from persisted state)
    current_color        = nil,    -- initial ink color hex (from persisted state; nil = default black)
    pressure_floor       = nil,    -- initial pressure floor (from persisted state; nil = default 200)

    -- Page navigation callbacks (Stage 8).
    -- Each returns (new_page_idx, total_pages, path) or nil at boundary.
    on_page_forward    = nil,
    on_page_back       = nil,

    _bb           = nil,           -- BlitBuffer (display cache)
    _stroke_buf   = nil,           -- StrokeBuffer (source of truth, Stage 4)
    _current_color = DEFAULT_COLOR, -- canonical ink color (#000000 always for now)

    _page_path  = nil,             -- path of the current page SVG (Stage 5)
    _page_dirty = false,           -- true when strokes added since last save

    -- Chrome (Stage 7)
    page_index  = 1,               -- current page number (set by caller)
    page_count  = 1,               -- total pages in notebook (set by caller)

    -- Eraser (Stage 10)
    _eraser_mode   = false,        -- true while eraser end of stylus is active (per-stroke)
    _eraser_locked = false,        -- true when menu eraser toggle is ON (persistent)

    -- Dark mode
    _dark_mode = false,

    -- Auto-save idle timer (30 s after last stroke change)
    _idle_save_fn = nil,

    -- Minimum pressure floor applied before pressure_to_width.
    -- Ensures a light touch produces a readable stroke; hardware hover stays below.
    _pressure_floor = 200,

    -- Stage 8: hardware page buttons (Kobo right-side rocker: 193=RPgBack, 194=RPgFwd)
    key_events = {
        PageForward = { { "RPgFwd" }, { "LPgFwd" } },
        PageBack    = { { "RPgBack" }, { "LPgBack" } },
    },

    use_raw_input      = false,    -- false = gesture layer; true = raw evdev
    finger_draw        = false,    -- allow capacitive touch to draw (pen-only default)

    init_rotation_mode = nil,
    _rotation_mode     = nil,

    _pendev    = nil,              -- PenDev instance
    _touchdev  = nil,              -- TouchDev instance (Stage 3)
    _palmreject = nil,             -- PalmReject instance (Stage 3)

    -- Raw pen tracking (raw input path)
    _last_pen_x         = nil,
    _last_pen_y         = nil,

    -- Raw touch tracking (separate from pen to avoid cross-contamination)
    _last_touch_x = nil,
    _last_touch_y = nil,

    -- Gesture path tracking
    _stroke_x     = nil,
    _stroke_y     = nil,
    _stroke_min_x = nil,
    _stroke_min_y = nil,
    _stroke_max_x = nil,
    _stroke_max_y = nil,

    -- Tracks ges.start_pos of the current pan gesture to detect new finger-downs
    -- even when pan_release was missed (straight-line bug prevention).
    _ges_start_x  = nil,
    _ges_start_y  = nil,
}

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

function DrawingCanvas:init()
    self.dimen = Geom:new{x=0, y=0,
                          w=Screen:getWidth(), h=Screen:getHeight()}

    -- Restore persisted preferences from caller.
    self._dark_mode      = self.dark_mode == true
    self._current_color  = self.current_color or DEFAULT_COLOR
    self._pressure_floor = self.pressure_floor or 200

    -- Use BBRGB32 on colour e-ink panels so ink renders in the chosen colour.
    -- Screen:isColorEnabled() is a user toggle (reads G_reader_settings) and
    -- can be off even on a Kaleido 3 device.  Use the hardware capability
    -- queries instead: hasKaleidoWfm() is set for all MTK Kobo colour panels;
    -- isColorScreen() is the broader fallback for other colour e-ink devices.
    local has_color_hw = (Device.hasKaleidoWfm and Device:hasKaleidoWfm())
                         or Screen:isColorScreen()
    local bb_type = has_color_hw
                    and Blitbuffer.TYPE_BBRGB32
                    or  Blitbuffer.TYPE_BB8
    self._bb = Blitbuffer.new(self.dimen.w, self.dimen.h, bb_type)
    self._bb:fill(self:_bgColor())
    self._has_color_hw = has_color_hw

    self._stroke_buf = StrokeBuffer.new()

    logger.dbg("FastNote canvas: init", self.dimen.w, "x", self.dimen.h,
               "has_color_hw=", has_color_hw,
               "isColorEnabled=", Screen:isColorEnabled())

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

    -- Double-tap anywhere below the chrome strip opens the quick-access overlay
    -- (color picker + sensitivity).  Chrome tap zones take priority for the top strip.
    self.ges_events.QuickDoubleTap = {
        GestureRange:new{
            ges   = "double_tap",
            range = Geom:new{
                x = 0,
                y = CHROME_HEIGHT,
                w = self.dimen.w,
                h = self.dimen.h - CHROME_HEIGHT,
            },
        },
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
                UIManager:scheduleIn(PEN_POLL_INTERVAL, function() self:_pollPen() end)
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
                    UIManager:scheduleIn(TOUCH_POLL_INTERVAL, function() self:_pollTouch() end)
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
    local finger_lbl    = self.finger_draw  and "Finger draw: on"  or "Finger draw: off"
    local eraser_lbl    = self._eraser_locked and "Eraser: on"     or "Eraser: off"
    local mode_lbl      = self._dark_mode  and "Light mode"        or "Dark mode"
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
            -- Row 2: undo / redo
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
            -- Row 3: eraser toggle / dark mode toggle
            {
                {text = eraser_lbl,
                 callback = function()
                     UIManager:close(menu)
                     self._eraser_locked = not self._eraser_locked
                     -- Sync per-stroke mode immediately
                     if not self._eraser_locked then
                         self._eraser_mode = false
                     end
                     logger.dbg("FastNote canvas: eraser_locked =", self._eraser_locked)
                 end},
                {text = mode_lbl,
                 callback = function()
                     UIManager:close(menu)
                     self:_toggleDarkMode()
                 end},
            },
            -- Row 4: finger draw / clear page
            {
                {text = finger_lbl,
                 callback = function()
                     UIManager:close(menu)
                     self.finger_draw = not self.finger_draw
                     logger.dbg("FastNote canvas: finger_draw =", self.finger_draw)
                 end},
                {text = "Clear page",
                 callback = function()
                     UIManager:close(menu)
                     self:_confirmClearPage()
                 end},
            },
            -- Row 5: notebooks browser
            {
                {text = "Notebooks",
                 callback = function()
                     UIManager:close(menu)
                     self:_doClose()
                     if self.on_show_browser then
                         self.on_show_browser()
                     end
                 end},
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

function DrawingCanvas:onQuickDoubleTap()
    self:_showQuickMenu()
    return true
end

--- Compact overlay: ink color palette + contact sensitivity.
-- Opens on double-tap anywhere on the drawing area.
function DrawingCanvas:_showQuickMenu()
    -- Dismiss any previously-open quick menu (e.g. user double-tapped again
    -- without selecting, or tapped outside which leaves _quick_menu stale).
    if self._quick_menu then
        UIManager:close(self._quick_menu)
        self._quick_menu = nil
    end

    local function color_btn(entry)
        local lbl = (entry.hex == self._current_color)
                    and (entry.name .. " \xE2\x9C\x93")  -- ✓
                    or  entry.name
        return {
            text = lbl,
            callback = function()
                UIManager:close(self._quick_menu)
                self._quick_menu = nil
                self._current_color = entry.hex
                if self.on_color_change then self.on_color_change(entry.hex) end
                logger.dbg("FastNote canvas: ink color =", entry.hex)
            end,
        }
    end

    self._quick_menu = ButtonDialogTitle:new{
        title = "Ink & Pressure",
        buttons = {
            -- Color row 1: Black / Red / Blue
            { color_btn(PALETTE[1]), color_btn(PALETTE[2]), color_btn(PALETTE[3]) },
            -- Color row 2: Green / Orange / Purple
            { color_btn(PALETTE[4]), color_btn(PALETTE[5]), color_btn(PALETTE[6]) },
            -- Sensitivity row
            {
                {
                    text = string.format("Contact Sensitivity: %d / 512", self._pressure_floor),
                    callback = function()
                        UIManager:close(self._quick_menu)
                        self._quick_menu = nil
                        local ok_sw, SpinWidget = pcall(require, "ui/widget/spinwidget")
                        if not ok_sw then return end
                        UIManager:show(SpinWidget:new{
                            title_text   = "Contact Sensitivity",
                            value        = self._pressure_floor,
                            value_min    = 0,
                            value_max    = 512,
                            value_step   = 25,
                            default_value = 200,
                            callback     = function(spin)
                                self._pressure_floor = spin.value
                                if self.on_pressure_change then
                                    self.on_pressure_change(spin.value)
                                end
                                logger.dbg("FastNote canvas: pressure_floor =", spin.value)
                            end,
                        })
                    end,
                },
            },
        },
    }
    UIManager:show(self._quick_menu)
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

    -- Eraser mode via menu toggle
    if self._eraser_locked then
        self:_doEraseAt(x, y)
        return true
    end

    -- Detect a new gesture via ges.start_pos (the initial touch-down point, constant
    -- throughout one pan sequence).  When start_pos changes, a new finger-down occurred.
    -- If the previous pan_release was missed, the old stroke is still open in the buffer
    -- and _stroke_x/y are stale.  Close and reset before starting the new stroke so we
    -- never draw a line from the previous gesture's last point to the new start point.
    local gsx = ges.start_pos and math.floor(ges.start_pos.x) or x
    local gsy = ges.start_pos and math.floor(ges.start_pos.y) or y
    if gsx ~= self._ges_start_x or gsy ~= self._ges_start_y then
        if self._stroke_buf.current then
            self._stroke_buf:penUp()
            self._page_dirty = true
        end
        self._stroke_x     = nil; self._stroke_y     = nil
        self._stroke_min_x = nil; self._stroke_max_x = nil
        self._stroke_min_y = nil; self._stroke_max_y = nil
        self._ges_start_x  = gsx
        self._ges_start_y  = gsy
    end

    local prev_x = self._stroke_x or x
    local prev_y = self._stroke_y or y

    -- StrokeBuffer: start or extend current stroke
    if not self._stroke_buf.current then
        self._stroke_buf:penDown(prev_x, prev_y, DEFAULT_LINE_WIDTH, self._current_color)
    end
    self._stroke_buf:penMove(x, y, DEFAULT_LINE_WIDTH)

    self:_drawSegment(prev_x, prev_y, x, y, DEFAULT_LINE_WIDTH)

    self._stroke_min_x = math.min(self._stroke_min_x or x, prev_x, x)
    self._stroke_min_y = math.min(self._stroke_min_y or y, prev_y, y)
    self._stroke_max_x = math.max(self._stroke_max_x or x, prev_x, x)
    self._stroke_max_y = math.max(self._stroke_max_y or y, prev_y, y)
    self._stroke_x     = x
    self._stroke_y     = y
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
            self:_drawSegment(self._stroke_x, self._stroke_y, x, y, DEFAULT_LINE_WIDTH)
        end
        self._stroke_max_x = math.max(self._stroke_max_x or x, x)
        self._stroke_max_y = math.max(self._stroke_max_y or y, y)
        self._stroke_min_x = math.min(self._stroke_min_x or x, x)
        self._stroke_min_y = math.min(self._stroke_min_y or y, y)
    end

    self._stroke_buf:penUp()
    self._page_dirty = true
    self:_scheduleIdleSave()

    if self._stroke_min_x then
        self:_refreshRect(utils.compute_dirty_rect(
            self._stroke_min_x, self._stroke_min_y,
            self._stroke_max_x, self._stroke_max_y,
            DEFAULT_LINE_WIDTH))
    end

    self._stroke_x     = nil
    self._stroke_y     = nil
    self._stroke_min_x = nil
    self._stroke_min_y = nil
    self._stroke_max_x = nil
    self._stroke_max_y = nil
    self._ges_start_x  = nil   -- allow next gesture to be fresh even if startPos repeats
    self._ges_start_y  = nil
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
-- Use after undo, redo, erase, or mode changes to rebuild the display cache.
function DrawingCanvas:_repaintAll()
    if not self._bb then return end
    self._bb:fill(self:_bgColor())
    if self._stroke_buf then
        -- Dark mode: override all strokes to white (bg inversion).
        -- Light mode: nil = each stroke uses its stored #rrggbb color.
        local override = self._dark_mode and Blitbuffer.COLOR_WHITE or nil
        self._stroke_buf:repaintTo(self._bb, override)
    end
    if self._has_color_hw then
        UIManager:setDirty(self, function() return "partial", nil, true end)
    else
        UIManager:setDirty(self, "partial")
    end
end

--- Return the Blitbuffer color for new live strokes (current ink, mode-aware).
-- In dark mode always returns white (ink inverts with background).
-- In light mode returns a color derived from _current_color.
function DrawingCanvas:_strokeColor()
    if self._dark_mode then
        return Blitbuffer.COLOR_WHITE
    end
    return Blitbuffer.colorFromString(self._current_color or DEFAULT_COLOR)
           or Blitbuffer.COLOR_BLACK
end

--- Return the Blitbuffer color for the page background (mode-dependent).
function DrawingCanvas:_bgColor()
    return self._dark_mode and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE
end

--- Schedule an a2 e-ink refresh for the given rect table {x,y,w,h}.
-- @table rect  dirty rectangle (from utils.compute_dirty_rect or Geom)
function DrawingCanvas:_refreshRect(rect)
    UIManager:setDirty(self, function() return "a2", Geom:new(rect) end)
end

--- Draw a live segment from (x0,y0) to (x1,y1) into _bb and schedule an a2 refresh.
-- @int x0, y0  start point (screen coords)
-- @int x1, y1  end point
-- @int lw      line width in pixels
function DrawingCanvas:_drawSegment(x0, y0, x1, y1, lw)
    utils.drawLine(self._bb, x0, y0, x1, y1, lw, self:_strokeColor())
    self:_refreshRect(utils.compute_dirty_rect(x0, y0, x1, y1, lw))
end

--- Erase strokes at (x, y) within ERASER_RADIUS, repaint if any were removed.
-- @int x, y  screen coordinates
function DrawingCanvas:_doEraseAt(x, y)
    local removed = self._stroke_buf:eraseAt(x, y, ERASER_RADIUS)
    if #removed > 0 then
        self._page_dirty = true
        self:_repaintAll()
    end
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
    local bb_type = self._has_color_hw
                    and Blitbuffer.TYPE_BBRGB32
                    or  Blitbuffer.TYPE_BB8
    self._bb = Blitbuffer.new(self.dimen.w, self.dimen.h, bb_type)
    self._bb:fill(self:_bgColor())

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

            -- ── Eraser mode ───────────────────────────────────────────────
            -- Activated by hardware BTN_TOOL_RUBBER OR the menu eraser lock.
            -- Check on both "down" and "move" so a mid-stroke tool flip (user
            -- flips the stylus while the pen is touching) activates eraser mode.
            if not self._eraser_mode then
                if ev.tool == "eraser" or self._eraser_locked then
                    self._eraser_mode = true
                    self._stroke_buf:penUp()
                    self._last_pen_x = nil
                    self._last_pen_y = nil
                end
            end

            if self._eraser_mode then
                self:_doEraseAt(sx, sy)
                return
            end

            -- ── Pen drawing ───────────────────────────────────────────────
            -- Apply pressure floor: boosts light-touch pressure to a minimum
            -- so a gentle stroke still produces a readable line, while hover
            -- (pressure near 0) remains below MIN_PEN_PRESSURE and is rejected.
            local raw_p     = ev.pressure or 0
            local floored_p = math.max(self._pressure_floor, raw_p)
            local lw        = utils.pressure_to_width(floored_p, self._pendev.p_max, 1, 8)

            if ev.type == "down" then
                -- Guard against hover: Elan BTN_TOUCH fires before contact on
                -- some firmware.  Real contact has significantly higher pressure.
                if raw_p < MIN_PEN_PRESSURE then
                    self._last_pen_x = nil
                    self._last_pen_y = nil
                    return
                end
                self._stroke_buf:penDown(sx, sy, lw, self._current_color)
            else
                self._stroke_buf:penMove(sx, sy, lw)
            end

            -- Only update the display buffer when there is an active stroke,
            -- so hover events that slipped through can't leave marks in the BB.
            if self._stroke_buf.current then
                if self._last_pen_x then
                    self:_drawSegment(self._last_pen_x, self._last_pen_y, sx, sy, lw)
                end
                self._last_pen_x = sx
                self._last_pen_y = sy
            end

        elseif ev.type == "up" then
            -- Clear hardware eraser mode; menu eraser lock (_eraser_locked) persists.
            if not self._eraser_locked then
                self._eraser_mode = false
            end
            self._stroke_buf:penUp()
            -- Only refresh if a stroke was actually drawn (not just hover).  Gating
            -- setDirty prevents visible refreshes on every pen proximity cycle.
            local had_stroke = self._last_pen_x ~= nil
            if had_stroke then
                self._page_dirty = true
                self:_scheduleIdleSave()
                UIManager:setDirty(self, "a2")
            end
            self._last_pen_x = nil
            self._last_pen_y = nil
        end
    end)

    if self._pendev then
        UIManager:scheduleIn(PEN_POLL_INTERVAL, function() self:_pollPen() end)
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
            local fx, fy = filtered.x, filtered.y

            -- Eraser mode via menu toggle
            if self._eraser_locked and filtered.type ~= "up" then
                self:_doEraseAt(fx, fy)
            elseif filtered.type == "down" then
                -- Clear stale touch tracking to avoid a line from the previous
                -- gesture if the "up" event was dropped by palm rejection.
                self._last_touch_x = nil
                self._last_touch_y = nil
                self._stroke_buf:penDown(fx, fy, DEFAULT_LINE_WIDTH, self._current_color)
                self._last_touch_x = fx
                self._last_touch_y = fy
            elseif filtered.type == "move" then
                self._stroke_buf:penMove(fx, fy, DEFAULT_LINE_WIDTH)
                if self._last_touch_x then
                    self:_drawSegment(self._last_touch_x, self._last_touch_y,
                                      fx, fy, DEFAULT_LINE_WIDTH)
                end
                self._last_touch_x = fx
                self._last_touch_y = fy
            elseif filtered.type == "up" then
                self._stroke_buf:penUp()
                if self._last_touch_x then
                    self._page_dirty = true
                end
                self._last_touch_x = nil
                self._last_touch_y = nil
                UIManager:setDirty(self, "a2")
            end
        end
    end)

    if self._touchdev then
        UIManager:scheduleIn(TOUCH_POLL_INTERVAL, function() self:_pollTouch() end)
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
        self._bb:fill(self:_bgColor())
        local override = self._dark_mode and Blitbuffer.COLOR_WHITE or nil
        self._stroke_buf:repaintTo(self._bb, override)
        UIManager:setDirty(self, "full")
    end

    logger.dbg("FastNote canvas: loadPage", path,
               "(" .. #sb.strokes .. " strokes)")
    return true
end

function DrawingCanvas:_doClose()
    if self._idle_save_fn then
        UIManager:unschedule(self._idle_save_fn)
        self._idle_save_fn = nil
    end
    self:_autoSave()
    -- Close the canvas, then schedule a full e-ink refresh on the next tick
    -- so the underlying UI gets a complete paint cycle without ghosting.
    UIManager:close(self)
    UIManager:nextTick(function()
        UIManager:setDirty(nil, "full")
    end)
    if self.on_close_callback then
        self.on_close_callback()
    end
end

-- ---------------------------------------------------------------------------
-- Dark mode / clear page helpers
-- ---------------------------------------------------------------------------

--- Toggle between dark (black bg, white ink) and light (white bg, black ink) mode.
-- Dark mode is a pure display transform: stroke data (#000000 canonical) is
-- never mutated.  _repaintAll passes _strokeColor() as a color_override to
-- paintTo, so all strokes flip visually without changing their stored color.
function DrawingCanvas:_toggleDarkMode()
    self._dark_mode = not self._dark_mode
    self._page_dirty = true
    self:_repaintAll()
    UIManager:setDirty(self, "full")
    if self.on_dark_mode_change then
        self.on_dark_mode_change(self._dark_mode)
    end
    logger.dbg("FastNote canvas: dark_mode =", self._dark_mode)
end

--- Show a confirmation dialog before clearing the page.
function DrawingCanvas:_confirmClearPage()
    local confirm
    confirm = ButtonDialogTitle:new{
        title = "Clear page?",
        buttons = {
            {
                {text = "Cancel",
                 callback = function() UIManager:close(confirm) end},
                {text = "Clear",
                 callback = function()
                     UIManager:close(confirm)
                     self:_clearPage()
                 end},
            },
        },
    }
    UIManager:show(confirm)
end

--- Erase all strokes on the current page (cannot be undone).
function DrawingCanvas:_clearPage()
    self._stroke_buf = StrokeBuffer.new()
    self._page_dirty = true
    self:_repaintAll()
    UIManager:setDirty(self, "full")
    logger.dbg("FastNote canvas: page cleared")
end

-- ---------------------------------------------------------------------------
-- Save / close / navigation
-- ---------------------------------------------------------------------------

--- Save the current page silently if dirty (no InfoMessage).
function DrawingCanvas:_autoSave()
    if not (self._page_path and self._page_dirty
            and not self._stroke_buf:isEmpty()) then
        return
    end
    local ok_svg, svg_module = pcall(require, "lib/svg")
    if not ok_svg then return end
    local f = io.open(self._page_path, "w")
    if not f then return end
    f:write(svg_module.write(self._stroke_buf, self.dimen.w, self.dimen.h))
    f:close()
    self._page_dirty = false
    if self.on_save_callback then self.on_save_callback(self._page_path) end
    logger.dbg("FastNote canvas: auto-saved to", self._page_path)
end

--- Schedule a silent save 30 s after the last stroke change.
-- Cancels any previously pending timer so only one fires per idle period.
function DrawingCanvas:_scheduleIdleSave()
    if self._idle_save_fn then
        UIManager:unschedule(self._idle_save_fn)
        self._idle_save_fn = nil
    end
    self._idle_save_fn = function()
        self._idle_save_fn = nil
        self:_autoSave()
    end
    UIManager:scheduleIn(IDLE_SAVE_DELAY, self._idle_save_fn)
end

--- Save before the device suspends so work is never lost to a sleep-induced shutdown.
function DrawingCanvas:onSuspend()
    self:_autoSave()
    return false  -- propagate; do not consume the suspend event
end

--- Navigate to a neighbouring page (+1 forward, -1 back).
function DrawingCanvas:_navigatePage(delta)
    local cb = delta > 0 and self.on_page_forward or self.on_page_back
    if not cb then return end

    self:_autoSave()

    local new_idx, new_count, new_path = cb()
    if not new_path then return end   -- at boundary (page 1 going back, etc.)

    self.page_index = new_idx
    self.page_count = new_count

    -- Reset stroke buffer and display before loading so a blank new page is clean.
    self._stroke_buf = StrokeBuffer.new()
    if self._bb then self._bb:fill(self:_bgColor()) end

    self:loadPage(new_path)           -- populates _stroke_buf if SVG exists

    UIManager:setDirty(self, "full")
    logger.dbg("FastNote canvas: navigated to page", new_idx, "/", new_count)
end

--- Key handler: physical forward-page button (RPgFwd / LPgFwd).
function DrawingCanvas:onPageForward()
    self:_navigatePage(1)
    return true
end

--- Key handler: physical back-page button (RPgBack / LPgBack).
function DrawingCanvas:onPageBack()
    self:_navigatePage(-1)
    return true
end

return DrawingCanvas
