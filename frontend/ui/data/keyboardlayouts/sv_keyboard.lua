-- Start with the norwegian keyboard layout (deep copy, to not alter it)
local sv_keyboard = require("util").tableDeepCopy(require("ui/data/keyboardlayouts/no_keyboard"))

local keys = sv_keyboard.keys

-- replace "Ø" and "ø" with "Ö" and "ö"
keys[3][10][1] = { "Ö", north = "ö", }
keys[3][10][2] = { "ö", north = "Ö", }

-- replace "Æ" and "æ" with "Ä" and "ä"
keys[3][11][1] = { "Ä", north = "ä", }
keys[3][11][2] = { "ä", north = "Ä", }

return sv_keyboard
