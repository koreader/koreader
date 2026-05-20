--[[--
input/touchdev.lua
FFI layer: find the capacitive touchscreen, open its /dev/input/eventX node,
read multi-touch protocol B events, and emit per-slot events.

ASSUMES: KOReader FFI environment (ffi/posix_h + ffi/linux_input_h loaded).
ASSUMES: Running on a device with a capacitive multi-touch panel (Kobo Libra Colour).
ASSUMES: LuaJIT 2.1 (Lua 5.1).

Not directly busted-testable (needs real /dev/input device fd).
The palm rejection logic in lib/palmreject.lua IS testable.

Multi-touch protocol B summary:
  EV_ABS, ABS_MT_SLOT            → selects active slot (0..N-1)
  EV_ABS, ABS_MT_TRACKING_ID     → -1 = contact up; ≥0 = contact down/continuing
  EV_ABS, ABS_MT_POSITION_X/Y    → contact coordinates (screen-space pixels)
  EV_ABS, ABS_MT_TOUCH_MAJOR     → major axis of contact ellipse (approx. contact area)
  EV_SYN, SYN_REPORT             → frame boundary; emit per-slot events for changed slots
--]]--

require("ffi/posix_h")
require("ffi/linux_input_h")

local ffi    = require("ffi")
local bit    = require("bit")
local logger = require("logger")

local C   = ffi.C
local bor = bit.bor

-- MT axis codes (from linux/input-event-codes.h)
local ABS_MT_SLOT        = 0x2f
local ABS_MT_TRACKING_ID = 0x39
local ABS_MT_POSITION_X  = 0x35
local ABS_MT_POSITION_Y  = 0x36
local ABS_MT_TOUCH_MAJOR = 0x30

local MAX_SLOTS  = 10
local BATCH_SIZE = 64

local TouchDev = {}
TouchDev.__index = TouchDev

--- Scan /proc/bus/input/devices for the capacitive touchscreen.
-- Identifies the device by the presence of ABS_MT_POSITION_X in its ABS= bitmask.
-- On Kobo Libra Colour this is typically a FocalTech FT series chip.
-- @treturn string|nil  Path like "/dev/input/event1", or nil if not found.
function TouchDev.find()
    local f = io.open("/proc/bus/input/devices", "r")
    if not f then
        logger.warn("FastNote touchdev: cannot open /proc/bus/input/devices")
        return nil
    end

    local result     = nil
    local cur_abs    = nil
    local cur_handlers = nil

    -- ABS_MT_POSITION_X = 0x35 = 53; bitmask bit 53 set means the device
    -- reports MT position X.  The ABS= field is a hex bitmask of reported axes.
    -- Bit 53 is in the second 32-bit word (word = bit/32 = 1, position = bit%32 = 21).
    -- We check for the presence of "ABS_MT" by inspecting the bitmask value.
    -- The ABS= line looks like "ABS=660800013ff" — parse the least-significant
    -- bit-53 by checking (tonumber(hex, 16) >> 53) & 1, but Lua 5.1 lacks
    -- bit-shifts on doubles.  Use bit library instead (LuaJIT).

    local function has_mt_position(abs_hex)
        -- Remove spaces; abs_hex may be e.g. "660800013ff"
        abs_hex = abs_hex:gsub("%s", "")
        -- We need bit 53 of the full bitmask.  The hex string is big-endian
        -- (MSB first), so we work from the right: each hex digit is 4 bits.
        -- Bit 53: hex digit index from right = floor(53/4) = 13.
        -- Within digit position = 53 mod 4 = 1.
        local n = #abs_hex
        local digit_from_right = math.floor(53 / 4)  -- 0-indexed
        local bit_in_digit     = 53 % 4

        local idx = n - digit_from_right  -- 1-indexed from left
        if idx < 1 then return false end
        local digit = tonumber(abs_hex:sub(idx, idx), 16)
        if not digit then return false end
        return bit.band(digit, bit.lshift(1, bit_in_digit)) ~= 0
    end

    for line in f:lines() do
        if line:find("^B: ABS=") then
            local abs = line:match("ABS=(%x+)")
            if abs then cur_abs = abs end
        elseif line:find("^H:") then
            cur_handlers = line:match("H: Handlers=(.*)")
        elseif line == "" then
            -- End of device block: check if this device has MT position X
            if cur_abs and cur_handlers and has_mt_position(cur_abs) then
                local ev = cur_handlers:match("(event%d+)")
                if ev then
                    result = "/dev/input/" .. ev
                    break
                end
            end
            cur_abs, cur_handlers = nil, nil
        end
    end

    f:close()

    if result then
        logger.dbg("FastNote touchdev: found touchscreen at", result)
    else
        logger.warn("FastNote touchdev: capacitive touchscreen not found")
    end
    return result
end

--- Open the touchscreen device node.
-- @string path   /dev/input/eventX path (from TouchDev.find()).
-- @treturn TouchDev|nil, string?
function TouchDev.open(path)
    if not path then return nil, "touchdev.open: nil path" end

    local fd = C.open(path, bor(C.O_RDONLY, C.O_NONBLOCK))
    if fd < 0 then
        local msg = "FastNote touchdev: cannot open " .. path
        logger.warn(msg)
        return nil, msg
    end

    -- Per-slot state (MT protocol B)
    local slots = {}
    for i = 0, MAX_SLOTS - 1 do
        slots[i] = {id=-1, x=0, y=0, touch_major=0, dirty=false}
    end

    local self = setmetatable({
        fd           = fd,
        path         = path,
        _slot        = 0,      -- currently selected slot
        _slots       = slots,
    }, TouchDev)

    logger.dbg("FastNote touchdev: opened", path)
    return self
end

--- Non-blocking poll: read all available MT events, emit slot-level events via cb.
-- Called from a UIManager:scheduleIn loop (~60 Hz is sufficient for touch).
-- @func cb  Callback: receives {type, slot, id, x, y, touch_major} tables.
--           type = "down" (new contact), "move" (position changed), "up" (contact ended)
function TouchDev:poll(cb)
    if not self.fd then return end

    local ev_type  = ffi.typeof("struct input_event[?]")
    local buf      = ev_type(BATCH_SIZE)
    local ev_sz    = ffi.sizeof("struct input_event")

    while true do
        local n = C.read(self.fd, buf, ev_sz * BATCH_SIZE)
        if n <= 0 then break end

        local count = math.floor(n / ev_sz)
        for i = 0, count - 1 do
            local e = buf[i]
            if e.type == C.EV_ABS then
                local code = e.code
                local val  = e.value

                if code == ABS_MT_SLOT then
                    -- Update the active slot FIRST; all following codes in
                    -- this frame apply to the newly-selected slot.
                    if val >= 0 and val < MAX_SLOTS then
                        self._slot = val
                    end
                else
                    -- Fetch slot AFTER any ABS_MT_SLOT event has updated self._slot.
                    local slot = self._slots[self._slot]
                    if code == ABS_MT_TRACKING_ID then
                        if slot then slot.id    = val; slot.dirty = true end
                    elseif code == ABS_MT_POSITION_X then
                        if slot then slot.x     = val; slot.dirty = true end
                    elseif code == ABS_MT_POSITION_Y then
                        if slot then slot.y     = val; slot.dirty = true end
                    elseif code == ABS_MT_TOUCH_MAJOR then
                        if slot then slot.touch_major = val; slot.dirty = true end
                    end
                end

            elseif e.type == C.EV_SYN then
                -- SYN_REPORT: flush changed slots
                for si = 0, MAX_SLOTS - 1 do
                    local s = self._slots[si]
                    if s.dirty then
                        s.dirty = false
                        local prev_id = s._prev_id

                        if s.id == -1 then
                            -- Contact ended
                            if prev_id and prev_id ~= -1 then
                                cb({type="up", slot=si, id=prev_id,
                                    x=s.x, y=s.y})
                            end
                            s._prev_id = -1
                        elseif prev_id == nil or prev_id == -1 then
                            -- New contact
                            s._prev_id = s.id
                            cb({type="down", slot=si, id=s.id,
                                x=s.x, y=s.y, touch_major=s.touch_major})
                        else
                            -- Continuing contact
                            s._prev_id = s.id
                            cb({type="move", slot=si, id=s.id,
                                x=s.x, y=s.y, touch_major=s.touch_major})
                        end
                    end
                end
            end
        end
    end
end

--- Close the device file descriptor.
function TouchDev:close()
    if self.fd then
        C.close(self.fd)
        self.fd = nil
        logger.dbg("FastNote touchdev: closed", self.path)
    end
end

return TouchDev
