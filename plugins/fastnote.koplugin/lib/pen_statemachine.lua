--[[--
lib/pen_statemachine.lua
Pure state machine: converts raw linux input events → high-level pen events.

No KOReader or FFI dependencies. Fully busted-testable.

The caller feeds EV_KEY, EV_ABS, EV_SYN events in order (as they arrive
from the kernel). The state machine tracks pen proximity / contact state
and emits high-level events via a callback:

  {type="down",  x, y, pressure, tool="pen"|"eraser"}
  {type="move",  x, y, pressure}
  {type="hover", x, y}
  {type="up"}

Design note: "down" is emitted on the first EV_SYN after BTN_TOUCH 1, not
immediately on the key event. This ensures x/y/pressure are fully latched
(ABS events in the same sync frame arrive before or alongside BTN_TOUCH).

ASSUMES: events arrive in kernel order (ABS/KEY before SYN in each frame).
--]]--

local codes = require("lib/input_codes")

local M = {}
M.__index = M

-- Aliases from shared constants (see lib/input_codes.lua)
local BTN_TOOL_PEN    = codes.BTN_TOOL_PEN
local BTN_TOOL_RUBBER = codes.BTN_TOOL_RUBBER
local BTN_TOUCH       = codes.BTN_TOUCH
local ABS_X           = codes.ABS_X
local ABS_Y           = codes.ABS_Y
local ABS_PRESSURE    = codes.ABS_PRESSURE

--- Create a new state machine instance.
-- @treturn table State machine with clean initial state.
function M:new()
    return setmetatable({
        in_proximity   = false,  -- pen is within hover range of the screen
        pen_down       = false,  -- pen is touching the screen
        tool           = "pen",  -- "pen" | "eraser"
        raw_x          = 0,      -- latched ABS_X value
        raw_y          = 0,      -- latched ABS_Y value
        raw_p          = 0,      -- latched ABS_PRESSURE value
        _just_downed   = false,  -- BTN_TOUCH 1 seen; next EV_SYN emits "down"
    }, M)
end

--- Feed an EV_KEY event.
-- @int  code   Key code (BTN_TOOL_PEN, BTN_TOOL_RUBBER, BTN_TOUCH, …)
-- @int  value  1 = pressed, 0 = released
-- @func cb     Optional callback; receives emitted event tables.
function M:feed_key(code, value, cb)
    if code == BTN_TOOL_PEN then
        if value == 1 then
            self.in_proximity = true
            self.tool = "pen"
        else
            self.in_proximity = false
            if self.pen_down then
                self.pen_down = false
                self._just_downed = false
                if cb then cb({type = "up"}) end
            end
        end

    elseif code == BTN_TOOL_RUBBER then
        if value == 1 then
            self.in_proximity = true
            self.tool = "eraser"
        else
            self.in_proximity = false
            -- Reset the tool latch: without this, a subsequent BTN_TOUCH
            -- with no fresh BTN_TOOL_PEN=1 (e.g. the Wacom-direct path)
            -- would emit "down" with tool still "eraser" -- phantom eraser.
            self.tool = "pen"
            if self.pen_down then
                self.pen_down = false
                self._just_downed = false
                if cb then cb({type = "up"}) end
            end
        end

    elseif code == BTN_TOUCH then
        if value == 1 then
            self.pen_down    = true
            self._just_downed = true
            -- Do NOT emit "down" here; wait for EV_SYN so coords are fully latched
        else
            self.pen_down    = false
            self._just_downed = false
            if cb then cb({type = "up"}) end
        end
    end
end

--- Feed an EV_ABS event (coordinate / pressure update).
-- @int code   ABS_X, ABS_Y, or ABS_PRESSURE
-- @int value  Raw axis value from the digitizer
function M:feed_abs(code, value)
    if     code == ABS_X        then self.raw_x = value
    elseif code == ABS_Y        then self.raw_y = value
    elseif code == ABS_PRESSURE then self.raw_p = value
    end
    -- Unknown codes are silently ignored.
end

--- Feed an EV_SYN / SYN_REPORT event.
-- Emits at most one high-level event per sync frame:
--   • "down"  — first frame after pen touched down
--   • "move"  — subsequent frames while pen is down
--   • "hover" — frames while pen is in proximity but not touching
--   • nothing — if pen is not in proximity
-- @func cb   Optional callback; receives the emitted event table.
function M:feed_syn(cb)
    if self._just_downed then
        self._just_downed = false
        if cb then
            cb({type     = "down",
                x        = self.raw_x,
                y        = self.raw_y,
                pressure = self.raw_p,
                tool     = self.tool})
        end
    elseif self.pen_down then
        if cb then
            cb({type     = "move",
                x        = self.raw_x,
                y        = self.raw_y,
                pressure = self.raw_p,
                tool     = self.tool})
        end
    elseif self.in_proximity then
        if cb then
            cb({type = "hover",
                x    = self.raw_x,
                y    = self.raw_y})
        end
    end
end

return M
