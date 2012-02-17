--[[
    This file contains settings related to key codes

    Copyright (C) 2011 Hans-Werner Hilse <hilse@web.de>

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.



    This file is based on include/keydefs.h from "launchpad"
    application, which is
    Copyright (C) 2010 Andy M. aka h1uke	h1ukeguy @ gmail.com
    and was licensed under the GPLv2
]]--

KEY_1 = 2
KEY_2 = 3
KEY_3 = 4
KEY_4 = 5
KEY_5 = 6
KEY_6 = 7
KEY_7 = 8
KEY_8 = 9
KEY_9 = 10
KEY_0 = 11
KEY_Q = 16
KEY_W = 17
KEY_E = 18
KEY_R = 19
KEY_T = 20
KEY_Y = 21
KEY_U = 22
KEY_I = 23
KEY_O = 24
KEY_P = 25
KEY_A = 30
KEY_S = 31
KEY_D = 32
KEY_F = 33
KEY_G = 34
KEY_H = 35
KEY_J = 36
KEY_K = 37
KEY_L = 38
KEY_DEL = 14
KEY_Z = 44
KEY_X = 45
KEY_C = 46
KEY_V = 47
KEY_B = 48
KEY_N = 49
KEY_M = 50
KEY_DOT = 52
KEY_SLASH = 53
KEY_ENTER = 28
KEY_SHIFT = 42
KEY_ALT = 56
KEY_SPACE = 57
KEY_AA = 90
KEY_SYM = 94
KEY_VPLUS = 115
KEY_VMINUS = 114
KEY_HOME = 98
KEY_PGBCK = 109
KEY_PGFWD = 124
KEY_MENU = 139
KEY_BACK = 91
KEY_FW_LEFT = 105
KEY_FW_RIGHT = 106
KEY_FW_UP = 122
KEY_FW_DOWN = 123
KEY_FW_PRESS = 92

-- constants from <linux/input.h>
EV_KEY = 1

-- event values
EVENT_VALUE_KEY_PRESS = 1
EVENT_VALUE_KEY_REPEAT = 2
EVENT_VALUE_KEY_RELEASE = 0
 
function set_k3_keycodes()
	KEY_AA = 190
	KEY_SYM = 126
	KEY_HOME = 102
	KEY_BACK = 158
	KEY_PGFWD = 191
	KEY_LPGBCK = 193
	KEY_LPGFWD = 104
	KEY_VPLUS = 115
	KEY_VMINUS = 114
	KEY_FW_UP = 103
	KEY_FW_DOWN = 108
	KEY_FW_PRESS = 194
end

function set_emu_keycodes()
	KEY_PGFWD = 117
	KEY_PGBCK = 112
	KEY_BACK = 22 -- backspace
	KEY_MENU = 67 -- F1
	KEY_FW_UP = 111
	KEY_FW_DOWN = 116
	KEY_FW_LEFT = 113
	KEY_FW_RIGHT = 114
	KEY_FW_PRESS = 36 -- enter for now

	KEY_ENTER = 36

	KEY_A = 38
	KEY_S = 39
	KEY_D = 40
	KEY_F = 41

	KEY_J = 44
	KEY_K = 45

	KEY_SHIFT = 50 -- left shift
	KEY_ALT = 64   -- left alt
	KEY_VPLUS = 95  -- F11
	KEY_VMINUS = 96 -- F12
end

function getRotationMode()
	--[[
	return code for four kinds of rotation mode:

  0 for no rotation, 
	1 for landscape with bottom on the right side of screen, etc.

	         2
	    -----------
	   |  -------  |
	   | |       | |
	   | |       | |
	   | |       | |  
	 3 | |       | | 1
	   | |       | |
	   | |       | |
	   |  -------  |
	   |           |
	    -----------
	         0
	--]]
	if KEY_FW_DOWN == 116 then -- in EMU mode always return 0
		return 0
	end
	orie_fd = assert(io.open("/sys/module/eink_fb_hal_broads/parameters/bs_orientation", "r"))
	updown_fd = assert(io.open("/sys/module/eink_fb_hal_broads/parameters/bs_upside_down", "r"))
	mode = orie_fd:read() + (updown_fd:read() * 2)
	return mode
end

function adjustFWKey(code)
	if getRotationMode() == 0 then
		return code
	elseif getRotationMode() == 1 then
		if code == KEY_FW_UP then
			return KEY_FW_RIGHT
		elseif code == KEY_FW_RIGHT then
			return KEY_FW_DOWN
		elseif code == KEY_FW_DOWN then
			return KEY_FW_LEFT
		elseif code == KEY_FW_LEFT then
			return KEY_FW_UP
		else
			return code
		end
	elseif getRotationMode() == 2 then
		if code == KEY_FW_UP then
			return KEY_FW_DOWN
		elseif code == KEY_FW_RIGHT then
			return KEY_FW_LEFT
		elseif code == KEY_FW_DOWN then
			return KEY_FW_UP
		elseif code == KEY_FW_LEFT then
			return KEY_FW_RIGHT
		else
			return code
		end
	elseif getRotationMode() == 3 then
		if code == KEY_FW_UP then
			return KEY_FW_LEFT
		elseif code == KEY_FW_RIGHT then
			return KEY_FW_UP
		elseif code == KEY_FW_DOWN then
			return KEY_FW_RIGHT
		elseif code == KEY_FW_LEFT then
			return KEY_FW_DOWN
		else
			return code
		end
	end
end
