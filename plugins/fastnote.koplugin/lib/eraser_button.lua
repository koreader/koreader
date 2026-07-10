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

local BTN_STYLUS  = codes.BTN_STYLUS
local BTN_STYLUS2 = codes.BTN_STYLUS2

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

return M
