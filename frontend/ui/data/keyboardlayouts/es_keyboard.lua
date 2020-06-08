-- Start with the english keyboard layout (deep copy, to not alter it)
local es_keyboard = require("util").tableDeepCopy(require("ui/data/keyboardlayouts/en_keyboard"))

local keys = es_keyboard.keys

-- Insert an additional key at the end of 2nd row for easy Ñ and ñ
table.insert(keys[2],
           --  1       2       3       4       5       6       7       8
            { "Ñ",    "ñ",    "Ñ",    "ñ",    "Ñ",    "ñ",    "Ñ",    "ñ",  }
)

-- Rename "space"
keys[4][4].label = "espacio"

return es_keyboard
