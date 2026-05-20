--[[--
input/pendev.lua
FFI layer: find the Wacom EMR digitizer, open its /dev/input/eventX node,
poll raw events, and delegate state transitions to lib/pen_statemachine.

ASSUMES: KOReader FFI environment (ffi/posix_h + ffi/linux_input_h loaded).
ASSUMES: Running on a device with a Wacom EMR digitizer (Kobo Libra Colour).
ASSUMES: LuaJIT 2.1 (Lua 5.1) — uses bit.bor for O_RDONLY | O_NONBLOCK.

Not directly busted-testable (needs real /dev/input device fd).
The state machine logic in lib/pen_statemachine.lua IS testable.
--]]--

require("ffi/posix_h")         -- O_RDONLY, O_NONBLOCK, open, read, close, ioctl
require("ffi/linux_input_h")   -- struct input_event, EV_KEY, EV_ABS, EV_SYN, …

local ffi      = require("ffi")
local bit      = require("bit")
local logger   = require("logger")
local SM       = require("lib/pen_statemachine")

local C   = ffi.C
local bor = bit.bor

-- Wacom axis fallback ranges (if EVIOCGABS is not available or fails).
-- Calibrated for Kobo Libra Colour Wacom I2C digitizer.
local FALLBACK_X_MIN   = 0
local FALLBACK_Y_MIN   = 0
local FALLBACK_P_MIN   = 0
local FALLBACK_X_MAX   = 4095
local FALLBACK_Y_MAX   = 4095
local FALLBACK_P_MAX   = 4095   -- Wacom pressure is commonly 0-4095 or 0-8191;
                                 -- calibrate on device via evtest if needed.

-- Declare struct once at module level so repeated PenDev.open() calls don't
-- trigger a LuaJIT "attempt to redefine" error.
-- pcall guards against benign re-definition if two modules require this file.
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
-- The Kobo Libra Colour uses an Elan combo chip ("Elan Touchscreen") that
-- handles both capacitive touch and the EMR pen on the same event node.
local PEN_NAME_PATTERNS = {"wacom", "elan", "digitizer", "pen", "stylus", "tablet"}

--- Check if a KEY= bitmask hex string has BTN_TOOL_PEN (0x140 = bit 320) set.
-- Bit 320: hex digit index from right = floor(320/4) = 80; bit in digit = 0.
local function has_btn_tool_pen(key_hex)
    key_hex = key_hex:gsub("%s", "")
    local idx = #key_hex - 80
    if idx < 1 then return false end
    local digit = tonumber(key_hex:sub(idx, idx), 16)
    return digit ~= nil and bit.band(digit, 1) ~= 0
end

--- Check if an ABS= bitmask hex string has ABS_PRESSURE (0x18 = bit 24) set.
-- ABS_PRESSURE being reported as a single-axis (not MT) event distinguishes
-- pen digitizers from pure touchscreens.
-- Bit 24: hex digit from right = 6; bit in digit = 0.
local function has_abs_pressure(abs_hex)
    abs_hex = abs_hex:gsub("%s", "")
    local idx = #abs_hex - 6
    if idx < 1 then return false end
    local digit = tonumber(abs_hex:sub(idx, idx), 16)
    return digit ~= nil and bit.band(digit, 1) ~= 0
end

--- Scan /proc/bus/input/devices for the pen digitizer.
-- Detection order: name match, then BTN_TOOL_PEN bitmask, then ABS_PRESSURE.
-- On Kobo Libra Colour the Elan combo chip serves as both pen and touch.
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
                logger.dbg("FastNote pendev: candidate device:", cur_name, "→", result)
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
    if not result then check_block() end  -- last block with no trailing blank line

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
-- @treturn PenDev|nil, string?   Opened instance, or nil + error message.
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
        -- Axis calibration (may be updated by _query_abs if ioctl is available)
        x_min   = FALLBACK_X_MIN,
        y_min   = FALLBACK_Y_MIN,
        p_min   = FALLBACK_P_MIN,
        x_max   = FALLBACK_X_MAX,
        y_max   = FALLBACK_Y_MAX,
        p_max   = FALLBACK_P_MAX,
    }, PenDev)

    -- Best-effort axis query — updates self.x_max / y_max / p_max if possible.
    self:_query_abs()

    logger.dbg("FastNote pendev: opened", path,
               "x_max=" .. self.x_max,
               "y_max=" .. self.y_max,
               "p_max=" .. self.p_max)
    return self
end

--- Attempt to read axis ranges via EVIOCGABS ioctl.
-- Falls back to FALLBACK_* values silently if the ioctl is unavailable.
-- EVIOCGABS(axis) = _IOR('E', 0x40 + axis, struct input_absinfo)
-- On ARM/x86-64 Linux: sizeof(struct input_absinfo) = 24 bytes.
function PenDev:_query_abs()
    local function eviocgabs(axis)
        -- _IOR('E', 0x40+axis, struct input_absinfo)
        -- direction READ = 2, size = 24
        return bit.bor(
            bit.lshift(2, 30),
            bit.lshift(0x45, 8),   -- 'E' = 0x45
            bit.lshift(24, 16),
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

    local xmin, xm = query(0)  -- ABS_X
    local ymin, ym = query(1)  -- ABS_Y
    local pmin, pm = query(24) -- ABS_PRESSURE

    if xm then self.x_min = xmin or 0; self.x_max = xm end
    if ym then self.y_min = ymin or 0; self.y_max = ym end
    if pm then self.p_min = pmin or 0; self.p_max = pm end
end

--- Non-blocking poll: read all available events, emit high-level events via cb.
-- Intended to be called from a UIManager:scheduleIn loop (~120 Hz).
-- @func cb   Callback receiving {type, x, y, pressure, tool} tables.
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
            local e = buf[i]
            local t = e.type
            if t == C.EV_KEY then
                self.sm:feed_key(e.code, e.value, cb)
            elseif t == C.EV_ABS then
                self.sm:feed_abs(e.code, e.value)
            elseif t == C.EV_SYN then
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
