--[[--
lib/input_codes.lua — Linux input event constants for the fastnote pen stack.

Single source of truth; imported by pen_statemachine.lua and pendev.lua so the
same hex codes are never typed twice.  Pure Lua; no KOReader / FFI deps.
--]]--

local M = {}

-- EV_KEY button codes used for pen proximity / contact detection
M.BTN_TOOL_PEN    = 0x140   -- pen tip entered proximity
M.BTN_TOOL_RUBBER = 0x141   -- eraser tip entered proximity
M.BTN_TOUCH       = 0x14a   -- pen tip physically contacting screen

-- EV_ABS single-touch axes (Wacom EMR protocol / pen_statemachine fallback)
M.ABS_X        = 0
M.ABS_Y        = 1
M.ABS_PRESSURE = 24

-- EV_ABS MT axes (Elan combo chip — ABS_MT_* events per slot)
M.ABS_MT_SLOT        = 0x2f   -- 47  active slot index
M.ABS_MT_POSITION_X  = 0x35   -- 53  X coordinate for current slot
M.ABS_MT_POSITION_Y  = 0x36   -- 54  Y coordinate for current slot
M.ABS_MT_TOOL_TYPE   = 0x37   -- 55  tool type (see MT_TOOL_* below)
M.ABS_MT_TRACKING_ID = 0x39   -- 57  contact ID; -1 = slot released
M.ABS_MT_PRESSURE    = 0x3a   -- 58  pressure for current slot

-- ABS_MT_TOOL_TYPE values
M.MT_TOOL_FINGER = 0
M.MT_TOOL_PEN    = 1
M.MT_TOOL_ERASER = 2

return M
