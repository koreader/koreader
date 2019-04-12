-- Start with the english keyboard layout
local es_keyboard = dofile("frontend/ui/data/keyboardlayouts/en_keyboard.lua")

local keys = es_keyboard.keys

-- Insert an additional key at the end of 2nd row for easy Ñ and ñ
table.insert(keys[2],
           --  1           2       3       4       5       6       7       8       9       10      11      12
            { "Ñ",        "ñ",    "Ñ",    "ñ",    "Ñ",    "ñ",    "Ñ",    "ñ",    "Ñ",    "ñ",    "Ñ",    "ñ",  }
)

-- Rename "space"
keys[4][4].label = "espacio"

return es_keyboard
