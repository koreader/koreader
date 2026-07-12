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
local InfoMessage       = require("ui/widget/infomessage")
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

-- Color tighten: seconds of pen inactivity before a targeted GLRC16 cleanup
-- refresh fires over the accumulated stroke bounding box.
-- Cancels on any pen-down so mid-session strokes are never interrupted.
-- Device-tuned default; overridable via config (tighten_delay) -- see
-- .github/instructions/eink-refresh.instructions.md before lowering it.
local COLOR_TIGHTEN_DELAY = 2.5

-- live_color_refresh (flag-gated, default off; see DrawingCanvas defaults
-- table and _useLiveColorRefresh): throttle interval for the direct
-- Screen:refreshUI call over the accumulated pending rect, ~30 fps.
-- Precomputed as an fts (ui/time) value since it's compared every segment.
local LIVE_REFRESH_INTERVAL     = 0.033
local LIVE_REFRESH_INTERVAL_FTS = time.s(LIVE_REFRESH_INTERVAL)

-- 6-color ink palette (Kaleido 3).  Stored as hex; rendered via colorFromString.
local PALETTE = {
    { name = "Black",  hex = "#000000" },
    { name = "Red",    hex = "#cc2222" },
    { name = "Blue",   hex = "#2244cc" },
    { name = "Green",  hex = "#22aa44" },
    { name = "Orange", hex = "#cc7700" },
    { name = "Purple", hex = "#8822bb" },
}

-- Color self-test (Task C1): layout of the reference-bar rect painted into
-- self._bb.  One bar per PALETTE color plus a black and a white reference
-- bar, stacked vertically, centered in the drawable area below the chrome
-- strip.  See _runColorSelfTest.
local COLOR_SELFTEST_BAR_HEIGHT     = 40    -- px, per bar
local COLOR_SELFTEST_WIDTH_FRACTION = 0.6   -- fraction of screen width

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

    -- Color tighten: deferred GLRC16 cleanup pass over new strokes (color HW only)
    _tighten_fn   = nil,   -- scheduled timer function
    _tighten_rect = nil,   -- accumulated bbox of strokes since last tighten (or nil)
    _tighten_delay   = nil, -- resolved seconds (config override or COLOR_TIGHTEN_DELAY); set in init()
    _tighten_enabled = nil, -- resolved bool (config override or true); set in init()

    -- live_color_refresh (flag-gated, default off): pending union of dirty
    -- rects not yet flushed to the screen, and the fts timestamp of the
    -- last direct refresh. Both nil when idle / flag off.
    _live_pending_rect  = nil,
    _live_refresh_last  = nil,

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

    -- Flag-gated experiment (candidate 1, pencil-koplugin-research.md):
    -- throttled direct-refresh live colour drawing instead of per-segment
    -- "a2". Only takes effect when _has_color_hw and use_raw_input are both
    -- true (see _useLiveColorRefresh); toggleable live from the hamburger
    -- menu, session-only, same as finger_draw.
    live_color_refresh = false,

    -- Config overrides for the colour tighten pass (lib/config.lua); nil
    -- means "use the built-in default" (see init()).
    tighten_delay      = nil,
    tighten_enabled    = nil,

    -- Which raw button code the hardware eraser tip sends (lib/config.lua,
    -- lib/eraser_button.lua); nil means "use the built-in default"
    -- ("stylus") -- see init() and _pollPen's PenDev.open call.
    eraser_button      = nil,

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

    -- Resolve tighten-pass config overrides. tighten_delay is a number, so
    -- `or` is safe here (a number is never falsy). tighten_enabled is a
    -- boolean -- `or` would silently turn an explicit `false` into `true`
    -- (see lua.instructions.md), so it needs an explicit if.
    self._tighten_delay = self.tighten_delay or COLOR_TIGHTEN_DELAY
    if self.tighten_enabled ~= nil then
        self._tighten_enabled = self.tighten_enabled
    else
        self._tighten_enabled = true
    end

    -- Resolve the eraser_button config override. It is a non-empty string
    -- ("stylus"/"stylus2"), never false/nil once set, so `or` is safe here.
    self._eraser_button = self.eraser_button or "stylus"

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
    self.dithered = has_color_hw

    self._stroke_buf = StrokeBuffer.new()

    -- Task C1 gate diagnostics: extends the existing init log (was
    -- has_color_hw/hw_dithering/isColorEnabled only) with the remaining
    -- gates from the color gate chain -- see the "color gate chain and the
    -- 8bpp trap" section of .agents/notes/waveform-refresh-research.md.
    local gate = self:_colorGateSnapshot()
    logger.dbg("FastNote canvas: init", self.dimen.w, "x", self.dimen.h,
               self:_colorGateLogLine(gate))

    -- Proactive warning: color-capable hardware with color rendering
    -- turned off means ink can never appear in color, no matter what the
    -- plugin does (8bpp trap). Fires once per canvas open -- init() runs
    -- exactly once per DrawingCanvas instance/open (_reinitAtRotation
    -- reuses this instance for rotation and never calls init() again).
    if gate.has_color_hw and not gate.is_color_enabled then
        UIManager:show(InfoMessage:new{
            text = "Fast Note: color rendering is turned off in KOReader, " ..
                   "so ink will draw in grayscale no matter what color you " ..
                   "pick. To fix: top menu -> gear icon -> Screen -> Color " ..
                   "rendering, then restart KOReader.",
        })
    end

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
            local pd, err = PenDev.open(pen_path, self._eraser_button)
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
    local live_color_lbl = self.live_color_refresh
                            and "Live color ink (experimental): on"
                            or  "Live color ink (experimental): off"
    local menu

    local function close() UIManager:close(menu) end

    local function color_btn(entry)
        local lbl = (entry.hex == self._current_color)
                    and (entry.name .. " \xE2\x9C\x93")
                    or  entry.name
        return {
            text = lbl,
            callback = function()
                close()
                self._current_color = entry.hex
                if self.on_color_change then self.on_color_change(entry.hex) end
                logger.dbg("FastNote canvas: ink color =", entry.hex)
            end,
        }
    end

    menu = ButtonDialogTitle:new{
        title = "Fast Note",
        buttons = {
            -- Row 1: orientation
            {
                {text = portrait_lbl,
                 callback = function()
                     close()
                     self:_reinitAtRotation(ROT_PORTRAIT)
                 end},
                {text = landscape_lbl,
                 callback = function()
                     close()
                     self:_reinitAtRotation(ROT_LANDSCAPE)
                 end},
            },
            -- Row 2: undo / redo
            {
                {text = "Undo",
                 callback = function()
                     close()
                     if self._stroke_buf:undo() then
                         self._page_dirty = true
                         self:_repaintAll()
                     end
                 end},
                {text = "Redo",
                 callback = function()
                     close()
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
                     close()
                     self._eraser_locked = not self._eraser_locked
                     if not self._eraser_locked then
                         self._eraser_mode = false
                     end
                     logger.dbg("FastNote canvas: eraser_locked =", self._eraser_locked)
                 end},
                {text = mode_lbl,
                 callback = function()
                     close()
                     self:_toggleDarkMode()
                 end},
            },
            -- Row 4: finger draw / clear page
            {
                {text = finger_lbl,
                 callback = function()
                     close()
                     self.finger_draw = not self.finger_draw
                     logger.dbg("FastNote canvas: finger_draw =", self.finger_draw)
                 end},
                {text = "Clear page",
                 callback = function()
                     close()
                     self:_confirmClearPage()
                 end},
            },
            -- Row 4b: live color ink toggle (experimental, flag-gated;
            -- session-only, same as finger_draw -- see live_color_refresh).
            {
                {text = live_color_lbl,
                 callback = function()
                     close()
                     self.live_color_refresh = not self.live_color_refresh
                     logger.dbg("FastNote canvas: live_color_refresh =", self.live_color_refresh)
                 end},
            },
            -- Row 5: ink color (top 3)
            { color_btn(PALETTE[1]), color_btn(PALETTE[2]), color_btn(PALETTE[3]) },
            -- Row 6: ink color (bottom 3)
            { color_btn(PALETTE[4]), color_btn(PALETTE[5]), color_btn(PALETTE[6]) },
            -- Row 7: contact sensitivity
            {
                {
                    text = string.format("Contact Sensitivity: %d / 512", self._pressure_floor),
                    callback = function()
                        close()
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
            -- Row 7b: color self-test + gate diagnostics (Task C1)
            {
                {text = "Color self-test",
                 callback = function()
                     close()
                     self:_runColorSelfTest()
                 end},
            },
            -- Row 8: notebooks browser / close
            {
                {text = "Notebooks",
                 callback = function()
                     close()
                     self:_doClose()
                     if self.on_show_browser then
                         self.on_show_browser()
                     end
                 end},
                {text = "Close canvas",
                 callback = function()
                     close()
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
        -- New finger-down: cancel the tighten timer but keep the rect so
        -- new strokes union into the same bbox for a single color refresh.
        if self._tighten_fn then self:_cancelTightenTimer() end
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
    self:_scheduleTighten()

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
    -- A full repaint already provides color quality — cancel any pending tighten.
    self:_cancelTighten()
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

-- ---------------------------------------------------------------------------
-- Task C1: color self-test + gate diagnostics
-- ---------------------------------------------------------------------------

--- Snapshot every link of the color gate chain (see the "color gate chain
-- and the 8bpp trap" section of .agents/notes/waveform-refresh-research.md).
-- If any of these is off, no plugin code can ever produce color -- this is
-- what the self-test and the proactive warning both check.
-- @return table {
--   has_color_hw      -- this plugin's own capability flag (self._has_color_hw)
--   is_color_enabled  -- Screen:isColorEnabled(): the user's color_rendering setting
--   has_kaleido_wfm   -- Device:hasKaleidoWfm(): true on all MTK Kobo color panels
--   hw_dithering      -- Screen.hw_dithering: required for the GLRC16/GCC16 promotion
--   hw_night_mode     -- Screen:getHWNightmode() (MTK only): HW inversion state
--   screen_bb_type    -- Screen.bb:getType(): the *actual* framebuffer's BB type
--   bb8_trap          -- true when screen_bb_type == Blitbuffer.TYPE_BB8, the
--                        definitive tell that KOReader booted the framebuffer
--                        at 8bpp with CFA skipped (color_rendering was off at
--                        startup) -- unfixable from plugin code.
-- }
function DrawingCanvas:_colorGateSnapshot()
    local screen_bb_type = Screen.bb and Screen.bb:getType()
    local hw_night_mode = false
    if Screen.getHWNightmode then
        hw_night_mode = Screen:getHWNightmode()
    end
    return {
        has_color_hw     = self._has_color_hw,
        is_color_enabled = Screen:isColorEnabled(),
        has_kaleido_wfm  = (Device.hasKaleidoWfm and Device:hasKaleidoWfm()) or false,
        hw_dithering     = Screen.hw_dithering and true or false,
        hw_night_mode    = hw_night_mode,
        screen_bb_type   = screen_bb_type,
        bb8_trap         = (screen_bb_type == Blitbuffer.TYPE_BB8),
    }
end

--- Render a color gate snapshot (see _colorGateSnapshot) as one log/display line.
function DrawingCanvas:_colorGateLogLine(gate)
    return string.format(
        "color gate: has_color_hw=%s is_color_enabled=%s has_kaleido_wfm=%s " ..
        "hw_dithering=%s hw_night_mode=%s screen_bb_type=%s bb8_trap=%s",
        tostring(gate.has_color_hw), tostring(gate.is_color_enabled),
        tostring(gate.has_kaleido_wfm), tostring(gate.hw_dithering),
        tostring(gate.hw_night_mode), tostring(gate.screen_bb_type),
        tostring(gate.bb8_trap))
end

--- One-tap, on-device answer to "is the color pipeline intact at the
-- KOReader level, independent of drawing code?" Paints a reference-bar
-- pattern (one bar per PALETTE color, plus black and white reference bars)
-- straight into the display buffer and forces the highest-fidelity color
-- refresh ("full" + dither=true -> GCC16), then shows the gate values next
-- to it. Does not touch StrokeBuffer or any live-drawing/tighten state --
-- purely additive diagnostics; the page is restored via _repaintAll() when
-- the InfoMessage is dismissed.
function DrawingCanvas:_runColorSelfTest()
    if not self._bb then return end
    local gate = self:_colorGateSnapshot()
    logger.dbg("FastNote canvas: color self-test,", self:_colorGateLogLine(gate))

    local bar_names = {}
    local bar_colors = {}
    for __, entry in ipairs(PALETTE) do
        bar_names[#bar_names + 1]  = entry.name
        bar_colors[#bar_colors + 1] = Blitbuffer.colorFromString(entry.hex) or Blitbuffer.COLOR_BLACK
    end
    bar_names[#bar_names + 1]   = "Black (reference)"
    bar_colors[#bar_colors + 1] = Blitbuffer.COLOR_BLACK
    bar_names[#bar_names + 1]   = "White (reference)"
    bar_colors[#bar_colors + 1] = Blitbuffer.COLOR_WHITE

    local rect_w = math.floor(self.dimen.w * COLOR_SELFTEST_WIDTH_FRACTION)
    local rect_h = #bar_colors * COLOR_SELFTEST_BAR_HEIGHT
    local drawable_h = self.dimen.h - CHROME_HEIGHT
    local rect_x = math.floor((self.dimen.w - rect_w) / 2)
    local rect_y = CHROME_HEIGHT + math.floor((drawable_h - rect_h) / 2)

    local bar_y = rect_y
    for __, color in ipairs(bar_colors) do
        self._bb:paintRect(rect_x, bar_y, rect_w, COLOR_SELFTEST_BAR_HEIGHT, color)
        bar_y = bar_y + COLOR_SELFTEST_BAR_HEIGHT
    end

    local test_rect = { x = rect_x, y = rect_y, w = rect_w, h = rect_h }
    -- "full" + dither=true -> GCC16, the highest-fidelity Kaleido color mode
    -- on an intact pipeline. A flash is expected and fine for a one-shot
    -- diagnostic (see eink-refresh.instructions.md -- one-shot "partial"/
    -- "full" + dither is correct; only per-segment "partial" is the hazard).
    UIManager:setDirty(self, function() return "full", Geom:new(test_rect), true end)

    local msg_lines = {
        "Color self-test -- bars top to bottom: " .. table.concat(bar_names, ", "),
        "",
        self:_colorGateLogLine(gate),
        "",
        "Bars in color -> the color pipeline is intact; any remaining issue is plugin-side.",
        "Bars gray (or black/white only) -> a KOReader-level gate is broken " ..
        "(usually Screen -> Color rendering is off, tripping the 8bpp trap) " ..
        "-- no plugin change can help until that setting is fixed.",
    }

    UIManager:show(InfoMessage:new{
        text = table.concat(msg_lines, "\n"),
        dismiss_callback = function()
            self:_repaintAll()
        end,
    })
end

--- Cancel the pending tighten timer but preserve the accumulated rect.
-- Use on pen-down: the user is still writing and new strokes need to
-- union into the existing rect.
function DrawingCanvas:_cancelTightenTimer()
    if self._tighten_fn then
        UIManager:unschedule(self._tighten_fn)
        self._tighten_fn = nil
    end
end

--- Cancel the tighten timer AND clear the accumulated rect, plus any
-- pending live_color_refresh state.
-- Use when a full-quality refresh makes all deferred refresh state
-- redundant (e.g. _repaintAll, loadPage, _doClose). Discarding
-- _live_pending_rect here also matters after _reinitAtRotation: a rect
-- recorded in the old orientation's coordinate space must never reach a
-- post-rotation Screen:refreshUI call.
function DrawingCanvas:_cancelTighten()
    self:_cancelTightenTimer()
    self._tighten_rect = nil
    self._live_pending_rect = nil
    self._live_refresh_last = nil
end

--- Schedule the deferred GLRC16 cleanup pass (color HW only).
-- Call on pen-up / stroke-end.  Resets the timer so a series of quick
-- strokes all promote together in one flash after _tighten_delay seconds
-- of inactivity (config override of COLOR_TIGHTEN_DELAY; see init()).
function DrawingCanvas:_scheduleTighten()
    if not self._has_color_hw then return end
    if not self._tighten_enabled then return end
    if not self._tighten_rect then return end
    if self._tighten_fn then
        UIManager:unschedule(self._tighten_fn)
    end
    self._tighten_fn = function()
        self._tighten_fn = nil
        local r = self._tighten_rect
        self._tighten_rect = nil
        if r then
            UIManager:setDirty(self, function() return "partial", Geom:new(r), true end)
        end
    end
    UIManager:scheduleIn(self._tighten_delay, self._tighten_fn)
end

--- Expand the accumulated tighten bbox to include rect (color HW only).
-- Called from _drawSegment so every live segment contributes.
function DrawingCanvas:_expandTightenRect(rect)
    if not self._has_color_hw then return end
    if not self._tighten_enabled then return end
    if self._tighten_rect then
        self._tighten_rect = utils.union_rect(self._tighten_rect, rect)
    else
        self._tighten_rect = { x = rect.x, y = rect.y, w = rect.w, h = rect.h }
    end
end

--- Schedule an A2 refresh for the given dirty rect.
-- Always A2 for live drawing — fast 1-bit B&W at pen-move rate.
-- Color ink appears gray during drawing; the deferred tighten pass
-- (_scheduleTighten) fires a single GLRC16 after pen inactivity to
-- reveal true color over the accumulated stroke bbox.
function DrawingCanvas:_refreshRect(rect)
    UIManager:setDirty(self, function() return "a2", Geom:new(rect) end)
end

--- Whether the flag-gated live-color-refresh path applies right now.
-- EXPERIMENTAL (default off; see live_color_refresh in the defaults table).
-- Only color hardware on the raw evdev pen path qualify — the gesture/
-- emulator path and monochrome hardware always keep the "a2" path in
-- _drawSegment, regardless of this flag's value.
function DrawingCanvas:_useLiveColorRefresh()
    return self.live_color_refresh and self._has_color_hw and self.use_raw_input
end

--- EXPERIMENTAL live_color_refresh path: blit the segment's dirty rect
-- straight into the framebuffer and throttle a direct Screen:refreshUI
-- over the accumulated pending rect to at most once per
-- LIVE_REFRESH_INTERVAL_FTS. Bypasses UIManager entirely — the sanctioned
-- escape hatch for high-frequency refresh, see
-- .github/instructions/eink-refresh.instructions.md. StrokeBuffer remains
-- authoritative (ADR-002); this only changes what's shown between ticks.
-- @param rect table {x, y, w, h} — this segment's dirty rect
function DrawingCanvas:_liveColorRefresh(rect)
    Screen.bb:blitFrom(self._bb, rect.x, rect.y, rect.x, rect.y, rect.w, rect.h)

    if self._live_pending_rect then
        self._live_pending_rect = utils.union_rect(self._live_pending_rect, rect)
    else
        self._live_pending_rect = { x = rect.x, y = rect.y, w = rect.w, h = rect.h }
    end

    local now = time.now()
    if self._live_refresh_last
       and (now - self._live_refresh_last) < LIVE_REFRESH_INTERVAL_FTS then
        return
    end
    self._live_refresh_last = now
    self:_flushLiveRefresh()
end

--- Fire a direct Screen:refreshUI over the pending live_color_refresh rect
-- and clear it. No-op if there is nothing pending. Called both by the
-- throttled tick in _liveColorRefresh and to flush on pen/touch "up" so the
-- final segment of a stroke is never left un-refreshed by the throttle.
function DrawingCanvas:_flushLiveRefresh()
    local rect = self._live_pending_rect
    if not rect then return end
    self._live_pending_rect = nil
    Screen:refreshUI(rect.x, rect.y, rect.w, rect.h)
end

--- Draw a live segment from (x0,y0) to (x1,y1) into _bb and schedule a refresh.
-- Also expands the tighten bbox so the deferred cleanup covers this segment.
-- Flag OFF (default): unchanged "a2" per-segment refresh via _refreshRect.
-- Flag ON (live_color_refresh, color HW + raw pen path only): see
-- _liveColorRefresh instead.
-- @int x0, y0  start point (screen coords)
-- @int x1, y1  end point
-- @int lw      line width in pixels
function DrawingCanvas:_drawSegment(x0, y0, x1, y1, lw)
    utils.drawLine(self._bb, x0, y0, x1, y1, lw, self:_strokeColor())
    local dirty = utils.compute_dirty_rect(x0, y0, x1, y1, lw)
    if self:_useLiveColorRefresh() then
        self:_liveColorRefresh(dirty)
    else
        self:_refreshRect(dirty)
    end
    self:_expandTightenRect(dirty)
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
                    -- Segments blitted since the last throttled tick would
                    -- otherwise never reach the panel (no-op unless a
                    -- live_color_refresh rect is pending).
                    self:_flushLiveRefresh()
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
                    -- Flush pending live-refresh ink before erasing starts
                    -- (no-op unless a live_color_refresh rect is pending).
                    self:_flushLiveRefresh()
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
                logger.dbg("FastNote pen down: tool=", ev.tool,
                           "eraser_mode=", self._eraser_mode,
                           "eraser_locked=", self._eraser_locked,
                           "pressure=", raw_p)
                -- New pen contact: cancel the tighten timer but keep the rect
                -- so all strokes in this session share one color refresh.
                if self._tighten_fn then self:_cancelTightenTimer() end
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
            -- Flush any rect the live-refresh throttle hadn't fired for yet,
            -- so the last segments of a stroke are never left un-refreshed.
            -- Unconditional (not behind had_stroke or the flag check): it's a
            -- no-op unless a live_color_refresh rect is actually pending, and
            -- it must also fire when _last_pen_x was already nulled or the
            -- menu toggle was flipped off with ink still pending.
            self:_flushLiveRefresh()
            -- Only act if a stroke was actually drawn (not just hover).
            local had_stroke = self._last_pen_x ~= nil
            if had_stroke then
                self._page_dirty = true
                self:_scheduleIdleSave()
                -- On mono HW: a2 confirms the stroke visually.
                -- On color HW: the last segment's partial already refreshed the
                -- display; schedule the deferred tighten instead.
                if self._has_color_hw then
                    self:_scheduleTighten()
                else
                    UIManager:setDirty(self, "a2")
                end
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
                if self._tighten_fn then self:_cancelTightenTimer() end
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
                -- Unconditional flush, same reasoning as the pen-up handler:
                -- no-op unless a live_color_refresh rect is pending.
                self:_flushLiveRefresh()
                if self._last_touch_x then
                    self._page_dirty = true
                    if self._has_color_hw then
                        self:_scheduleTighten()
                    else
                        UIManager:setDirty(self, "a2")
                    end
                end
                self._last_touch_x = nil
                self._last_touch_y = nil
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
        self:_cancelTighten()
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
    self:_cancelTighten()
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
