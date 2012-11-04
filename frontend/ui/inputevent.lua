require "ui/event"
require "ui/device"
require "settings"

-- constants from <linux/input.h>
EV_SYN = 0
EV_KEY = 1
EV_ABS = 3

-- Synchronization events (SYN.code).
SYN_REPORT = 0
SYN_CONFIG = 1
SYN_MT_REPORT = 2

-- For multi-touch events (ABS.code).
ABS_MT_SLOT = 47
ABS_MT_POSITION_X = 53
ABS_MT_POSITION_Y = 54
ABS_MT_TRACKING_ID = 57
ABS_MT_PRESSURE = 58

-- key press event values (KEY.value)
EVENT_VALUE_KEY_PRESS = 1
EVENT_VALUE_KEY_REPEAT = 2
EVENT_VALUE_KEY_RELEASE = 0


--[[
an interface for key presses
]]

Key = {}

function Key:new(key, modifiers)
	local o = { key = key, modifiers = modifiers }

	-- we're a hash map, too
	o[key] = true
	for mod, pressed in pairs(modifiers) do
		if pressed then
			o[mod] = true
		end
	end

	setmetatable(o, self)
	self.__index = self
	return o
end

function Key:__tostring()
	return table.concat(self:getSequence(), "-")
end

--[[
get a sequence that can be matched against later

use this to let the user press a sequence and then
store this as configuration data (configurable
shortcuts)
]]
function Key:getSequence()
	local seq = {}
	for mod, pressed in pairs(self.modifiers) do
		if pressed then
			table.insert(seq, mod)
		end
	end
	table.insert(seq, self.key)
end

--[[
this will match a key against a sequence

the sequence should be a table of key names that
must be pressed together to match.
if an entry in this table is itself a table, at
least one key in this table must match.

E.g.:

Key:match({ "Alt", "K" }) -- match Alt-K
Key:match({ "Alt", { "K", "L" }}) -- match Alt-K _or_ Alt-L
]]
function Key:match(sequence)
	local mod_keys = {} -- a hash table for checked modifiers
	for _, key in ipairs(sequence) do
		if type(key) == "table" then
			local found = false
			for _, variant in ipairs(key) do
				if self[variant] then
					found = true
					break
				end
			end
			if not found then
				-- one of the needed keys is not pressed
				return false
			end
		elseif not self[key] then
			-- needed key not pressed
			return false
		elseif self.modifiers[key] ~= nil then
			-- checked key is a modifier key
			mod_keys[key] = true
		end
	end

	for mod, pressed in pairs(self.modifiers) do
		if pressed and not mod_keys[mod] then
			-- additional modifier keys are pressed, don't match
			return false
		end
	end
	
	return true
end

--[[
an interface to get input events
]]
Input = {
	event_map = {
		[2]  = "1", [3]  = "2", [4]  = "3", [5]  = "4", [6]  = "5", [7]  = "6", [8]  = "7", [9]  = "8", [10] = "9", [11] = "0",
		[16] = "Q", [17] = "W", [18] = "E", [19] = "R", [20] = "T", [21] = "Y", [22] = "U", [23] = "I", [24] = "O", [25] = "P",
		[30] = "A", [31] = "S", [32] = "D", [33] = "F", [34] = "G", [35] = "H", [36] = "J", [37] = "K", [38] = "L", [14] = "Del",
		[44] = "Z", [45] = "X", [46] = "C", [47] = "V", [48] = "B", [49] = "N", [50] = "M", [52] = ".", [53] = "/", -- only KDX

		[28] = "Enter",
		[29] = "ScreenKB", -- K[4]
		[42] = "Shift",
		[56] = "Alt",
		[57] = " ",
		[90] = "AA", -- KDX
		[91] = "Back", -- KDX
		[92] = "Press", -- KDX
		[94] = "Sym", -- KDX
		[98] = "Home", -- KDX
		[102] = "Home", -- K[3] & k[4]
		[104] = "LPgBack", -- K[3] only
		[103] = "Up", -- K[3] & k[4]
		[105] = "Left",
		[106] = "Right",
		[108] = "Down", -- K[3] & k[4]
		[109] = "RPgBack",
		[114] = "VMinus",
		[115] = "VPlus",
		[122] = "Up", -- KDX
		[123] = "Down", -- KDX
		[124] = "RPgFwd", -- KDX
		[126] = "Sym", -- K[3]
		[139] = "Menu",
		[158] = "Back", -- K[3] & K[4]
		[190] = "AA", -- K[3]
		[191] = "RPgFwd", -- K[3] & k[4]
		[193] = "LPgFwd", -- K[3] only
		[194] = "Press", -- K[3] & k[4]

		[10000] = "IntoSS", -- go into screen saver
		[10001] = "OutOfSS", -- go out of screen saver
		[10020] = "Charging",
		[10021] = "NotCharging",
	},
	sdl_event_map = {
		[10] = "1", [11] = "2", [12] = "3", [13] = "4", [14] = "5", [15] = "6", [16] = "7", [17] = "8", [18] = "9", [19] = "0",
		[24] = "Q", [25] = "W", [26] = "E", [27] = "R", [28] = "T", [29] = "Y", [30] = "U", [31] = "I", [32] = "O", [33] = "P",
		[38] = "A", [39] = "S", [40] = "D", [41] = "F", [42] = "G", [43] = "H", [44] = "J", [45] = "K", [46] = "L",
		[52] = "Z", [53] = "X", [54] = "C", [55] = "V", [56] = "B", [57] = "N", [58] = "M",

		[22] = "Back", -- Backspace
		[36] = "Enter", -- Enter
		[50] = "Shift", -- left shift
		[60] = ".",
		[61] = "/",
		[62] = "Sym", -- right shift key
		[64] = "Alt", -- left alt
		[65] = " ", -- Spacebar
		[67] = "Menu", -- F[1]
		[72] = "LPgBack", -- F[6]
		[73] = "LPgFwd", -- F[7]
		[95] = "VPlus", -- F[11]
		[96] = "VMinus", -- F[12]
		[105] = "AA", -- right alt key
		[110] = "Home", -- Home
		[111] = "Up", -- arrow up
		[112] = "RPgBack", -- normal PageUp
		[113] = "Left", -- arrow left
		[114] = "Right", -- arrow right
		[115] = "Press", -- End (above arrows)
		[116] = "Down", -- arrow down
		[117] = "RPgFwd", -- normal PageDown
		[119] = "Del", -- Delete
	},
	rotation = 0,
	rotation_map = {
		[0] = {},
		[1] = { Up = "Right", Right = "Down", Down = "Left", Left = "Up" },
		[2] = { Up = "Down", Right = "Left", Down = "Up", Left = "Right" },
		[3] = { Up = "Left", Right = "Up", Down = "Right", Left = "Down" }
	},
	modifiers = {
		Alt = false,
		Shift = false
	},

	-- these groups are just helpers:
	group = {
		Cursor = { "Up", "Down", "Left", "Right" },
		PgFwd = { "RPgFwd", "LPgFwd" },
		PgBack = { "RPgBack", "LPgBack" },
		Alphabet = {
			"A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M",
			"N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z"
		},
		AlphaNumeric = {
			"0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
			"A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M",
			"N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z"
		},
		Numeric = {
			"0", "1", "2", "3", "4", "5", "6", "7", "8", "9"
		},
		Text = {
			" ", ".", "/",
			"0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
			"A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M",
			"N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z"
		},
		Any = {
			" ", ".", "/",
			"0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
			"A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M",
			"N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
			"Up", "Down", "Left", "Right", "Press",
			"Back", "Enter", "Sym", "AA", "Menu", "Home", "Del",
			"LPgBack", "RPgBack", "LPgFwd", "RPgFwd"
		}
	},
}

function Input:init()
	if util.isEmulated()==1 then
		-- dummy call that will initialize SDL input handling
		os.execute("rm -f emu_event && mkfifo emu_event")
		input.open("emu_event")
		-- SDL key codes
		self.event_map = self.sdl_event_map
	else
		input.open("fake_events")
		local dev_mod = Device:getModel()

		input.open("/dev/input/event0")
		if dev_mod ~= "KindlePaperWhite" then
			-- we don't have event1 in KindlePaperWhite
			input.open("/dev/input/event1")
		elseif dev_mod == "KindlePaperWhite" then
			print("Auto-detected Kindle PaperWhite")
		elseif dev_mod == "Kindle4" then
			print("Auto-detected Kindle 4")
			self:adjustKindle4EventMap()
		elseif dev_mod == "Kindle3" then
			input.open("/dev/input/event2")
			print("Auto-detected Kindle 3")
		elseif dev_mod == "KindleDXG" then
			print("Auto-detected Kindle DXG")
		elseif dev_mod == "Kindle2" then
			print("Auto-detected Kindle 2")
		else
			print("Not supported device model!")
			os.exit(-1)
		end
	end
end

function Input:adjustKindle4EventMap()
	self.event_map[193] = "LPgBack"
	self.event_map[104] = "LPgFwd"
end

function Input:waitEvent(timeout_us, timeout_s)
	-- wrapper for input.waitForEvents that will retry for some cases
	local ok, ev
	while true do
		ok, ev = pcall(input.waitForEvent, timeout_us, timeout_s)
		if ok then
			break
		end
		if ev == "Waiting for input failed: timeout\n" then
			-- don't report an error on timeout
			ev = nil
			break
		elseif ev == "application forced to quit" then
			os.exit(0)
		end
		DEBUG("got error waiting for events:", ev)
		if ev ~= "Waiting for input failed: 4\n" then
			-- we only abort if the error is not EINTR
			break
		end
	end
	if ok and ev then
		if ev.type == EV_KEY then
			local keycode = self.event_map[ev.code]
			if not keycode then
				-- do not handle keypress for keys we don't know
				return
			end

			-- take device rotation into account
			if self.rotation_map[self.rotation][keycode] then
				keycode = self.rotation_map[self.rotation][keycode]
			end

			if keycode == "IntoSS" then
				Device:intoScreenSaver()
				return
			elseif keycode == "OutOfSS" then
				Device:outofScreenSaver()
				return
			elseif keycode == "Charging" then
				Device:usbPlugIn()
				return
			elseif keycode == "NotCharging" then
				Device:usbPlugOut()
				return
			end

			-- handle modifier keys
			if self.modifiers[keycode] ~= nil then
				if ev.value == EVENT_VALUE_KEY_PRESS then
					self.modifiers[keycode] = true
				elseif ev.value == EVENT_VALUE_KEY_RELEASE then
					self.modifiers[keycode] = false
				end
				return
			end

			local key = Key:new(keycode, self.modifiers)

			if ev.value == EVENT_VALUE_KEY_PRESS then
				return Event:new("KeyPress", key)
			elseif ev.value == EVENT_VALUE_KEY_RELEASE then
				return Event:new("KeyRelease", key)
			end
		elseif ev.type == EV_ABS then
			if ev.code == ABS_MT_SLOT then
				DEBUG("MT_SLOT:", ev.value)
			elseif ev.code == ABS_MT_TRACKING_ID then
				DEBUG("MT_TRACK_ID:", ev.value)
			elseif ev.code == ABS_MT_POSITION_X then
				DEBUG("MT_X:", ev.value)
			elseif ev.code == ABS_MT_POSITION_Y then
				DEBUG("MT_Y:", ev.value)
			else
				DEBUG("unknown touch event!", ev)
				return Event:new("UnkonwnTouchEvent", ev)
			end
		elseif ev.type == EV_SYN then
			if ev.code == SYN_REPORT then
				DEBUG("SYN REPORT")
			elseif ev.code == SYN_MT_REPORT then
				DEBUG("SYN MT_REPORT")
			elseif ev.code == SYN_CONFIG then
				DEBUG("SYN CONFIG")
			else
				DEBUG(ev)
			end
		else
			-- some other kind of event that we do not know yet
			return Event:new("GenericInput", ev)
		end
	elseif not ok and ev then
		return Event:new("InputError", ev)
	end
end

--[[
helper function for formatting sequence definitions for output
]]
function Input:sequenceToString(sequence)
	local modifiers = {}
	local keystring = {"",""} -- first entries reserved for modifier specification
	for _, key in ipairs(sequence) do
		if type(key) == "table" then
			local alternatives = {}
			for _, alternative in ipairs(key) do
				table.insert(alternatives, alternative)
			end
			table.insert(keystring, "{")
			table.insert(keystring, table.concat(alternatives, "|"))
			table.insert(keystring, "}")
		elseif self.modifiers[key] ~= nil then
			table.insert(modifiers, key)
		else
			table.insert(keystring, key)
		end
	end
	if #modifiers then
		keystring[1] = table.concat(modifiers, "-")
		keystring[2] = "-"
	end
	return table.concat(keystring)
end
