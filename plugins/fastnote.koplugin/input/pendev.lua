--[[--
input/pendev.lua
FFI layer: find the Elan/Wacom digitizer, open its /dev/input/eventX node,
poll raw events, and delegate state transitions to lib/pen_statemachine.

The Kobo Libra Colour uses an Elan combo chip (event1, "Elan Touchscreen")
that sends pen input via **MT protocol** (ABS_MT_TOOL_TYPE=1 for pen,
ABS_MT_POSITION_X/Y, ABS_MT_TRACKING_ID, ABS_MT_PRESSURE) rather than
the single-touch Wacom protocol (ABS_X/Y, BTN_TOUCH).

poll() handles both:
  • MT events: tracked per slot; pen slot (TOOL_TYPE_PEN=1) synthesizes
    ABS_X/Y/PRESSURE into the state machine.  BTN_TOUCH is derived from
    ABS_MT_PRESSURE (see below) rather than from EV_KEY — the Elan fires
    EV_KEY BTN_TOUCH at hover distance, not at physical contact.
  • Single-touch EV_KEY / EV_ABS: passed directly to the state machine
    (handles Wacom EMR devices and provides BTN_TOOL_PEN if sent).

Hover-prevention for Elan MT pen:
  The Elan chip asserts EV_KEY BTN_TOUCH=1 when the pen enters proximity
  (~10 mm), long before physical contact.  If we feed that directly to the
  state machine, the canvas receives "down" events while the pen is in the
  air.  Fix: once we identify a device as an MT pen device (_has_mt_pen),
  we ignore EV_KEY BTN_TOUCH entirely and instead synthesize contact state
  from ABS_MT_PRESSURE on each EV_SYN:
    pressure >= PRESSURE_CONTACT_THRESHOLD  →  BTN_TOUCH=1  (contact)
    pressure <  PRESSURE_CONTACT_THRESHOLD  →  BTN_TOUCH=0  (hover/lift)

ASSUMES: KOReader FFI environment (ffi/posix_h + ffi/linux_input_h loaded).
ASSUMES: LuaJIT 2.1 (Lua 5.1) — uses bit.bor for O_RDONLY | O_NONBLOCK.
--]]--

require("ffi/posix_h")         -- O_RDONLY, O_NONBLOCK, open, read, close, ioctl
require("ffi/linux_input_h")   -- struct input_event, EV_KEY, EV_ABS, EV_SYN, …

local ffi      = require("ffi")
local bit      = require("bit")
local logger   = require("logger")
local SM       = require("lib/pen_statemachine")

local C   = ffi.C
local bor = bit.bor

-- ---------------------------------------------------------------------------
-- MT protocol constants (linux/input-event-codes.h)
-- Hardcoded to avoid dependency on whether linux_input_h.lua exports them.
-- ---------------------------------------------------------------------------
local ABS_MT_SLOT        = 0x2f  -- 47  Switch to MT slot N
local ABS_MT_POSITION_X  = 0x35  -- 53  X for current MT slot
local ABS_MT_POSITION_Y  = 0x36  -- 54  Y for current MT slot
local ABS_MT_TOOL_TYPE   = 0x37  -- 55  Tool: 0=finger, 1=pen, 2=eraser
local ABS_MT_TRACKING_ID = 0x39  -- 57  Contact ID; -1 = lifted
local ABS_MT_PRESSURE    = 0x3a  -- 58  Pressure for current MT slot
local MT_TOOL_PEN        = 1     -- ABS_MT_TOOL_TYPE value for pen
local MT_TOOL_ERASER     = 2     -- ABS_MT_TOOL_TYPE value for eraser end

-- EV_KEY codes
local BTN_TOOL_PEN = 0x140  -- 320
local BTN_TOUCH    = 0x14a  -- 330

-- Pressure at or above this value is treated as physical contact.
-- The Elan chip reports 0 (or near-0) for hover and measurable pressure
-- only when the pen actually touches the glass.
local PRESSURE_CONTACT_THRESHOLD = 20

-- ---------------------------------------------------------------------------
-- Axis fallback ranges (Elan I2C digitizer on Kobo Libra Colour).
-- Updated by _query_abs() if EVIOCGABS succeeds.
-- ---------------------------------------------------------------------------
local FALLBACK_X_MIN   = 0
local FALLBACK_Y_MIN   = 0
local FALLBACK_P_MIN   = 0
local FALLBACK_X_MAX   = 4095
local FALLBACK_Y_MAX   = 4095
local FALLBACK_P_MAX   = 4095

-- Declare struct once at module level.
-- pcall guards against benign re-definition on second require.
pcall(ffi.cdef, [[
    struct fn_input_absinfo {
        int value;
        int minimum;
        int maximum;
        int fuzz;
        int flat;
        int resolution;
    };
]])

-- Read batch size: how many input_event records to attempt per poll call.
local BATCH_SIZE = 64

local PenDev = {}
PenDev.__index = PenDev

-- Pen device name fragments (case-insensitive) to match against N: lines.
local PEN_NAME_PATTERNS = {"wacom", "elan", "digitizer", "pen", "stylus", "tablet"}

--- Check if a KEY= bitmask hex string has BTN_TOOL_PEN (0x140 = bit 320) set.
local function has_btn_tool_pen(key_hex)
    key_hex = key_hex:gsub("%s", "")
    local idx = #key_hex - 80
    if idx < 1 then return false end
    local digit = tonumber(key_hex:sub(idx, idx), 16)
    return digit ~= nil and bit.band(digit, 1) ~= 0
end

--- Check if an ABS= bitmask hex string has ABS_PRESSURE (0x18 = bit 24) set.
local function has_abs_pressure(abs_hex)
    abs_hex = abs_hex:gsub("%s", "")
    local idx = #abs_hex - 6
    if idx < 1 then return false end
    local digit = tonumber(abs_hex:sub(idx, idx), 16)
    return digit ~= nil and bit.band(digit, 1) ~= 0
end

--- Scan /proc/bus/input/devices for the pen digitizer.
-- @treturn string|nil  Path like "/dev/input/event1", or nil if not found.
function PenDev.find()
    local f = io.open("/proc/bus/input/devices", "r")
    if not f then
        logger.warn("FastNote pendev: cannot open /proc/bus/input/devices")
        return nil
    end

    local result       = nil
    local cur_name     = nil
    local cur_key      = nil
    local cur_abs      = nil
    local cur_handlers = nil

    local function check_block()
        if not cur_handlers then return end
        local name_match = false
        if cur_name then
            for _, pat in ipairs(PEN_NAME_PATTERNS) do
                if cur_name:find(pat, 1, true) then
                    name_match = true; break
                end
            end
        end
        local is_pen = name_match
                    or (cur_key and has_btn_tool_pen(cur_key))
                    or (cur_abs and has_abs_pressure(cur_abs))
        if is_pen then
            local ev = cur_handlers:match("(event%d+)")
            if ev then
                result = "/dev/input/" .. ev
            end
        end
    end

    for line in f:lines() do
        if line:find("^N:") then
            cur_name = line:lower()
        elseif line:find("^B: KEY=") then
            cur_key = line:match("KEY=(%x[%x ]*)")
        elseif line:find("^B: ABS=") then
            cur_abs = line:match("ABS=(%x[%x ]*)")
        elseif line:find("^H:") then
            cur_handlers = line:match("H: Handlers=(.*)")
        elseif line == "" then
            check_block()
            if result then break end
            cur_name, cur_key, cur_abs, cur_handlers = nil, nil, nil, nil
        end
    end
    if not result then check_block() end

    f:close()

    if result then
        logger.dbg("FastNote pendev: found pen digitizer at", result)
    else
        logger.warn("FastNote pendev: pen digitizer not found in /proc/bus/input/devices")
    end
    return result
end

--- Open a digitizer device node and create a PenDev instance.
-- @string path   /dev/input/eventX path (typically from PenDev.find()).
-- @treturn PenDev|nil, string?
function PenDev.open(path)
    if not path then
        return nil, "pendev.open: nil path"
    end

    local fd = C.open(path, bor(C.O_RDONLY, C.O_NONBLOCK))
    if fd < 0 then
        local msg = "FastNote pendev: cannot open " .. path
        logger.warn(msg)
        return nil, msg
    end

    local self = setmetatable({
        fd      = fd,
        path    = path,
        sm      = SM:new(),
        -- Axis calibration
        x_min   = FALLBACK_X_MIN,
        y_min   = FALLBACK_Y_MIN,
        p_min   = FALLBACK_P_MIN,
        x_max   = FALLBACK_X_MAX,
        y_max   = FALLBACK_Y_MAX,
        p_max   = FALLBACK_P_MAX,
        -- MT pen tracking (Elan combo chip protocol)
        _mt_cur      = 0,    -- current MT slot being updated
        _mt_slots    = {},   -- slot# -> {tool, id, x, y, p}
        _mt_pen_slot = nil,  -- slot# identified as pen (TOOL_TYPE_PEN)
        _has_mt_pen  = false, -- true once MT pen protocol detected; gates BTN_TOUCH skip
    }, PenDev)

    self:_query_abs()

    logger.dbg("FastNote pendev: opened", path,
               "x_max=" .. self.x_max,
               "y_max=" .. self.y_max,
               "p_max=" .. self.p_max)
    return self
end

--- Attempt to read axis ranges via EVIOCGABS ioctl.
-- Tries single-touch axes first, then MT axes as fallback.
function PenDev:_query_abs()
    local function eviocgabs(axis)
        return bit.bor(
            bit.lshift(2, 30),
            bit.lshift(0x45, 8),   -- 'E' = 0x45
            bit.lshift(24, 16),    -- sizeof(struct fn_input_absinfo) = 24
            0x40 + axis
        )
    end

    local absinfo = ffi.new("struct fn_input_absinfo")

    local function query(axis)
        local ret = C.ioctl(self.fd, eviocgabs(axis), absinfo)
        if ret == 0 and absinfo.maximum > 0 then
            return absinfo.minimum, absinfo.maximum
        end
        return nil, nil
    end

    -- Single-touch axes first (Wacom EMR), MT axes as fallback (Elan MT)
    local xmin, xm = query(0)             -- ABS_X
    if not xm then xmin, xm = query(ABS_MT_POSITION_X) end
    local ymin, ym = query(1)             -- ABS_Y
    if not ym then ymin, ym = query(ABS_MT_POSITION_Y) end
    local pmin, pm = query(24)            -- ABS_PRESSURE
    if not pm then pmin, pm = query(ABS_MT_PRESSURE) end

    if xm then self.x_min = xmin or 0; self.x_max = xm end
    if ym then self.y_min = ymin or 0; self.y_max = ym end
    if pm then self.p_min = pmin or 0; self.p_max = pm end
end

--- Non-blocking poll: read all available events, emit high-level events via cb.
-- Handles both single-touch (Wacom) and MT pen (Elan combo chip) protocols.
-- On MT devices, synthesizes ABS_X/Y/PRESSURE + BTN_TOUCH into the SM from
-- the pen's ABS_MT_* events so the state machine stays protocol-agnostic.
-- @func cb  Callback receiving {type, x, y, pressure, tool} tables.
function PenDev:poll(cb)
    if not self.fd then return end

    local ev_type = ffi.typeof("struct input_event[?]")
    local buf     = ev_type(BATCH_SIZE)
    local ev_sz   = ffi.sizeof("struct input_event")

    while true do
        local n = C.read(self.fd, buf, ev_sz * BATCH_SIZE)
        if n <= 0 then break end

        local count = math.floor(n / ev_sz)
        for i = 0, count - 1 do
            local e  = buf[i]
            local t  = e.type
            local ec = e.code
            local ev = e.value

            if t == C.EV_KEY then
                -- For MT pen devices the Elan fires EV_KEY BTN_TOUCH=1 at
                -- hover distance (not contact).  Once we've seen an MT pen
                -- slot (_has_mt_pen), ignore this key — contact state is
                -- derived from ABS_MT_PRESSURE in the EV_SYN handler instead.
                -- BTN_TOOL_PEN/RUBBER still pass through so the SM tracks
                -- proximity and tool type correctly.
                if ec == BTN_TOUCH and self._has_mt_pen then
                    -- deliberately ignored for MT pen devices
                else
                    self.sm:feed_key(ec, ev, cb)
                end

            elseif t == C.EV_ABS then
                -- ── MT protocol ──────────────────────────────────────────
                if ec == ABS_MT_SLOT then
                    self._mt_cur = ev

                elseif ec == ABS_MT_TOOL_TYPE then
                    local s = self._mt_cur
                    if not self._mt_slots[s] then self._mt_slots[s] = {} end
                    self._mt_slots[s].tool = ev
                    if ev == MT_TOOL_PEN then
                        self._mt_pen_slot = s
                        self._has_mt_pen  = true  -- mark device as MT pen
                        logger.dbg("FastNote pendev: pen identified at MT slot", s)
                    elseif ev == MT_TOOL_ERASER then
                        self._mt_pen_slot = s
                        self._has_mt_pen  = true  -- same slot tracking, BTN_TOOL_RUBBER sets tool in SM
                        logger.dbg("FastNote pendev: eraser identified at MT slot", s)
                    end

                elseif ec == ABS_MT_TRACKING_ID then
                    local s = self._mt_cur
                    if not self._mt_slots[s] then self._mt_slots[s] = {} end
                    self._mt_slots[s].id = ev

                elseif ec == ABS_MT_POSITION_X then
                    local s = self._mt_cur
                    if not self._mt_slots[s] then self._mt_slots[s] = {} end
                    self._mt_slots[s].x = ev

                elseif ec == ABS_MT_POSITION_Y then
                    local s = self._mt_cur
                    if not self._mt_slots[s] then self._mt_slots[s] = {} end
                    self._mt_slots[s].y = ev

                elseif ec == ABS_MT_PRESSURE then
                    local s = self._mt_cur
                    if not self._mt_slots[s] then self._mt_slots[s] = {} end
                    self._mt_slots[s].p = ev

                else
                    -- ── Single-touch (Wacom / fallback) ──────────────────
                    -- ABS_X=0, ABS_Y=1, ABS_PRESSURE=24 pass straight through.
                    self.sm:feed_abs(ec, ev)
                end

            elseif t == C.EV_SYN then
                local pen_slot = self._mt_pen_slot
                if pen_slot then
                    local pd = self._mt_slots[pen_slot]
                    if pd then
                        -- Feed MT coordinates into the SM's single-touch axes.
                        if pd.x then self.sm:feed_abs(0,  pd.x) end  -- ABS_X
                        if pd.y then self.sm:feed_abs(1,  pd.y) end  -- ABS_Y
                        if pd.p then self.sm:feed_abs(24, pd.p) end  -- ABS_PRESSURE

                        -- Synthesize BTN_TOUCH from pressure (Elan hover fix).
                        -- The Elan fires EV_KEY BTN_TOUCH for proximity; we
                        -- ignore that and use pressure to detect real contact.
                        local pressure = pd.p or 0
                        if pressure >= PRESSURE_CONTACT_THRESHOLD then
                            if not self.sm.pen_down then
                                -- Pen just touched: prime "down" for next SYN.
                                -- Pass nil cb so "down" fires on feed_syn below.
                                self.sm:feed_key(BTN_TOUCH, 1, nil)
                            end
                        else
                            if self.sm.pen_down then
                                -- Pressure dropped: pen lifted.  Emit "up" now.
                                self.sm:feed_key(BTN_TOUCH, 0, cb)
                            end
                        end
                    end
                end

                self.sm:feed_syn(cb)
            end
        end
    end
end

--- Close the device file descriptor.
function PenDev:close()
    if self.fd then
        C.close(self.fd)
        self.fd = nil
        logger.dbg("FastNote pendev: closed", self.path)
    end
end

return PenDev
