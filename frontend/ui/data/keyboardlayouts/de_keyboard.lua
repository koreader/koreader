-- Start with the english keyboard layout (deep copy, to not alter it)
local de_keyboard = require("util").tableDeepCopy(require("ui/data/keyboardlayouts/en_keyboard"))

local keys = de_keyboard.keys

keys[1][6][1], keys[3][2][1] = keys[3][2][1], keys[1][6][1] -- Z <-> Y
keys[1][6][2], keys[3][2][2] = keys[3][2][2], keys[1][6][2] -- z <-> y

return de_keyboard
