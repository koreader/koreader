--[[--
lib/eraser_button.lua

Pure translation: given a raw BTN_STYLUS / BTN_STYLUS2 event and the
configured `eraser_button` setting, decide what pendev.lua should feed into
the pen state machine.

Background: the Kobo Stylus 2 eraser tip reports `ABS_MT_TOOL_TYPE = 1`
(pen) on this device's Elan combo chip -- it does NOT distinguish itself at
the tool-type level. Instead it sends `BTN_STYLUS` (level signal: 1 while
touching, 0 on release). The side button sends `BTN_STYLUS2` the same way.
Some units/pens ship with the two swapped. The `eraser_button` config key
("stylus" default | "stylus2") tells fastnote which raw code is wired to
the eraser tip on a given unit; the other code is the side button and is
reported for logging only (see
.agents/plans/live-color-refresh-and-eraser-hardening.md Workstream B2 and
.agents/plans/color-drawing-fix-and-menu-access.md Fix F).

No KOReader or FFI dependencies. Fully busted-testable.

@module fastnote.lib.eraser_button
--]]--

local codes = require("lib/input_codes")

local M = {}

local BTN_STYLUS      = codes.BTN_STYLUS
local BTN_STYLUS2     = codes.BTN_STYLUS2
local BTN_TOOL_PEN    = codes.BTN_TOOL_PEN
local BTN_TOOL_RUBBER = codes.BTN_TOOL_RUBBER
local MT_TOOL_PEN     = codes.MT_TOOL_PEN

--- Decide what pendev.lua should do for a BTN_STYLUS / BTN_STYLUS2 event.
-- @int    code             BTN_STYLUS or BTN_STYLUS2 (any other code returns "unknown")
-- @int    value             1 = pressed (button contacting), 0 = released
-- @string configured_button "stylus" (default; nil is treated the same) or
--                            "stylus2" -- which raw code is wired to the
--                            eraser tip on this unit
-- @treturn string  One of:
--   "rubber_on"   -- the configured eraser code just pressed; feed BTN_TOOL_RUBBER, 1
--   "pen_restore" -- the configured eraser code just released; feed BTN_TOOL_PEN, 1
--   "side_button" -- a stylus button event, but not the configured eraser code;
--                    log only, no state-machine feed
--   "unknown"     -- code is neither BTN_STYLUS nor BTN_STYLUS2
function M.decode(code, value, configured_button)
    if code ~= BTN_STYLUS and code ~= BTN_STYLUS2 then
        return "unknown"
    end

    -- configured_button is a string (or nil); BTN_STYLUS2 is never
    -- false/nil, so this and/or is safe (see lua.instructions.md).
    local eraser_code = (configured_button == "stylus2") and BTN_STYLUS2 or BTN_STYLUS

    if code ~= eraser_code then
        return "side_button"
    end

    if value == 1 then
        return "rubber_on"
    else
        return "pen_restore"
    end
end

--- Update the order-independent eraser latch from a decoded M.decode() action.
--
-- Background: pendev.lua's poll loop can see EV_KEY (BTN_STYLUS/BTN_STYLUS2)
-- and EV_ABS (ABS_MT_TOOL_TYPE) in either order within a frame, and the Elan
-- chip may re-report ABS_MT_TOOL_TYPE=1 (pen) in a later frame while the
-- eraser tip is still touching (sticky tool-type reporting). A held-flag that
-- only changes on the authoritative BTN_STYLUS/BTN_STYLUS2 level signal --
-- and is otherwise left alone -- makes the eraser state a latch instead of a
-- one-shot "correction" that depends on event order. See
-- .agents/plans/eraser-capture-runbook.md and the "Fix F" section of
-- .agents/plans/color-drawing-fix-and-menu-access.md.
--
-- @bool   held    Current held-state (true = eraser tip latched active).
-- @string action  Result of M.decode(): "rubber_on" | "pen_restore" |
--                  "side_button" | "unknown".
-- @treturn bool  The new held-state.
function M.update_held(held, action)
    if action == "rubber_on" then
        return true
    elseif action == "pen_restore" then
        return false
    else
        -- "side_button" and "unknown" don't touch the latch.
        return held
    end
end

--- Decide which BTN_TOOL_* code to feed the state machine when
-- ABS_MT_TOOL_TYPE reports MT_TOOL_PEN, consulting the eraser latch.
--
-- The Elan combo chip never distinguishes the eraser tip at the MT
-- tool-type level (it always reports MT_TOOL_PEN=1, see module comment
-- above) -- so pendev.lua's ABS_MT_TOOL_TYPE == MT_TOOL_PEN branch must
-- defer to this latch rather than unconditionally feeding BTN_TOOL_PEN.
-- This makes the mapping order-independent: whether BTN_STYLUS or
-- ABS_MT_TOOL_TYPE arrives first in a frame, or ABS_MT_TOOL_TYPE is
-- re-emitted in a later frame while the eraser is still held, the result
-- is the same.
--
-- @bool held           Current held-state from M.update_held().
-- @int  mt_tool_value   The ABS_MT_TOOL_TYPE value being handled.
-- @treturn int|nil  BTN_TOOL_RUBBER while held, BTN_TOOL_PEN while not held,
--   or nil if mt_tool_value isn't MT_TOOL_PEN (not this function's concern --
--   the caller's ABS_MT_TOOL_TYPE == MT_TOOL_ERASER branch already knows what
--   to feed without consulting the latch).
function M.mt_tool_for_pen_slot(held, mt_tool_value)
    if mt_tool_value ~= MT_TOOL_PEN then
        return nil
    end

    if held then
        return BTN_TOOL_RUBBER
    else
        return BTN_TOOL_PEN
    end
end

return M
