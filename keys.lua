--[[
This file contains settings related to key codes
]]--

KEY_PAGEUP = 109 -- nonstandard
KEY_PAGEDOWN = 124 -- nonstandard
KEY_BACK = 91 -- nonstandard
KEY_MENU = 139

-- DPad:
KEY_UP = 122 -- nonstandard
KEY_DOWN = 123 -- nonstandard
KEY_LEFT = 105
KEY_RIGHT = 106
KEY_BTN = 92 -- nonstandard

-- constants from <linux/input.h>
EV_KEY = 1

-- event values
EVENT_VALUE_KEY_PRESS = 1
EVENT_VALUE_KEY_REPEAT = 2
EVENT_VALUE_KEY_RELEASE = 0


function set_emu_keycodes()
	KEY_PAGEDOWN = 112
	KEY_PAGEUP = 117
	KEY_BACK = 22 -- backspace
	KEY_MENU = 67 -- F1
	KEY_UP = 111
	KEY_DOWN = 116
	KEY_LEFT = 113
	KEY_RIGHT = 114
	KEY_BTN = 36 -- enter for now
end
