--[[--
lib/palmreject.lua — proximity-gated palm rejection state machine.

Pure Lua; no KOReader or FFI dependencies — fully busted-testable.

The machine maintains two independent inputs:
  1. Pen events (from lib/pen_statemachine via input/pendev):
       {type = "down"|"move"|"hover"|"up", ...}
  2. Touch slot events (from input/touchdev):
       {type = "down"|"move"|"up", slot, id, x, y, touch_major}

Rejection rules (applied in order):
  1. Pen-proximity gate: if the pen is "proximate" (down, hovering, or within
     BLACKOUT_MS of its last lift), any new touch contact is rejected.
  2. Area gate: if touch_major > area_threshold AND area_threshold > 0, the
     contact is rejected regardless of pen state.

"Proximate" persists for BLACKOUT_MS after a pen "up" event to cover the
brief gap when the pen lifts between strokes (e.g. writing a "t" cross).

The clock_fn parameter is injectable for testing (default: os.clock in ms).
--]]--

local PalmReject = {}
PalmReject.__index = PalmReject

--- Create a new PalmReject instance.
-- @param opts  table  optional: {blackout_ms=250, area_threshold=0}
-- @param clock_fn  function  returns current time in ms (injectable for tests)
function PalmReject.new(opts, clock_fn)
    opts = opts or {}
    return setmetatable({
        blackout_ms     = opts.blackout_ms    or 250,
        area_threshold  = opts.area_threshold or 0,    -- 0 = disabled

        _pen_proximate  = false,  -- pen is in proximity or in blackout
        _pen_up_at      = nil,    -- clock value when pen last went up
        _slots          = {},     -- tracking_id → {rejected=bool}

        _clock = clock_fn or function()
            return os.clock() * 1000  -- os.clock() → seconds; we want ms
        end,
    }, PalmReject)
end

-- ---------------------------------------------------------------------------
-- Pen event feed
-- ---------------------------------------------------------------------------

--- Feed a high-level pen event (from pen_statemachine).
-- Updates internal proximity state.
-- @param ev  table  {type="down"|"move"|"hover"|"up", ...}
function PalmReject:onPenEvent(ev)
    if ev.type == "down" or ev.type == "move" or ev.type == "hover" then
        self._pen_proximate = true
        self._pen_up_at     = nil
    elseif ev.type == "up" then
        -- Keep proximate flag set; start blackout timer.
        self._pen_up_at = self._clock()
    end
end

--- True if the pen is currently considered proximate (down, hovering, or
-- within the blackout window after lifting).
function PalmReject:isPenProximate()
    if self._pen_proximate then
        if self._pen_up_at ~= nil then
            -- Check if we're still within the blackout window
            if (self._clock() - self._pen_up_at) >= self.blackout_ms then
                self._pen_proximate = false
                self._pen_up_at     = nil
            end
        end
    end
    return self._pen_proximate
end

-- ---------------------------------------------------------------------------
-- Touch event filter
-- ---------------------------------------------------------------------------

--- Filter a touch slot event through the rejection rules.
-- Returns the event unmodified if it should pass through, or nil if rejected.
-- @param ev  table  {type, slot, id, x, y, touch_major}
-- @return table|nil
function PalmReject:onTouchEvent(ev)
    local slot = ev.slot

    if ev.type == "down" then
        local rejected = false

        -- Rule 1: pen proximity gate
        if self:isPenProximate() then
            rejected = true
        end

        -- Rule 2: area gate (large contact = palm)
        if not rejected and self.area_threshold > 0
                and (ev.touch_major or 0) > self.area_threshold then
            rejected = true
        end

        self._slots[slot] = {rejected = rejected}
        if rejected then return nil end
        return ev

    elseif ev.type == "move" then
        local state = self._slots[slot]
        if state and state.rejected then return nil end
        return ev

    elseif ev.type == "up" then
        local state = self._slots[slot]
        self._slots[slot] = nil  -- drop slot
        if state and state.rejected then return nil end
        return ev
    end

    return ev  -- unknown event type: pass through
end

return PalmReject
