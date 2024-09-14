-- Start with the english keyboard layout
local es_keyboard = dofile("frontend/ui/data/keyboardlayouts/en_keyboard.lua")

local keys = es_keyboard.keys

-- Insert an additional key at the end of 2nd row for easy Ñ and ñ
table.insert(keys[4], 7,
            { { "Ñ", north = "ñ", }, { "ñ", north = "Ñ", }, { "¿", alt_label = "¡", }, { "¡", alt_label = "¿", }, }
)

-- put zero in its usual space under numpad (layers 3 and 4)
keys[4][6][3], keys[4][7][3] = keys[4][7][3], keys[4][6][3]
keys[4][6][4], keys[4][7][4] = keys[4][7][4], keys[4][6][4]

-- swap "ñ" and ","
keys[4][7][1], keys[3][10][1] = keys[3][10][1], keys[4][7][1]
keys[4][7][2], keys[3][10][2] = keys[3][10][2], keys[4][7][2]

-- change order ", n m" to "n m ,"
keys[4][7][1], keys[4][8][1], keys[4][9][1] = keys[4][8][1], keys[4][9][1], keys[4][7][1]
keys[4][7][2], keys[4][8][2], keys[4][9][2] = keys[4][8][2], keys[4][9][2], keys[4][7][2]

-- Rename "space"
keys[5][4].label = "espacio"
keys[4][1].width = 1.0 -- resize Shift
keys[4][10].width = 1.0 -- resize Enter

return es_keyboard
