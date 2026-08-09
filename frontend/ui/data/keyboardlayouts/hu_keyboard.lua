-- Start with the english keyboard layout
local hu_keyboard = dofile("frontend/ui/data/keyboardlayouts/en_keyboard.lua")

-- Swap Z and Y
local keys = hu_keyboard.keys
keys[2][6][1], keys[4][2][1] = keys[4][2][1], keys[2][6][1] -- Z <-> Y
keys[2][6][2], keys[4][2][2] = keys[4][2][2], keys[2][6][2] -- z <-> y

-- put 0 before 1
keys[1][1][1], keys[1][2][1], keys[1][3][1], keys[1][4][1], keys[1][5][1],
keys[1][6][1], keys[1][7][1], keys[1][8][1], keys[1][9][1], keys[1][10][1] =
keys[1][10][1], keys[1][1][1], keys[1][2][1], keys[1][3][1], keys[1][4][1],
keys[1][5][1], keys[1][6][1], keys[1][7][1], keys[1][8][1], keys[1][9][1]

keys[1][1][2], keys[1][2][2], keys[1][3][2], keys[1][4][2], keys[1][5][2],
keys[1][6][2], keys[1][7][2], keys[1][8][2], keys[1][9][2], keys[1][10][2] =
keys[1][10][2], keys[1][1][2], keys[1][2][2], keys[1][3][2], keys[1][4][2],
keys[1][5][2], keys[1][6][2], keys[1][7][2], keys[1][8][2], keys[1][9][2]

-- add Ö key
table.insert(
    keys[1],
    {
        { "Ö", north = "ö",     south = "Ő", },
        { "ö", north = "Ö",     south = "ő", },
        { "/", alt_label = "÷", north = "÷", },
        { "÷", alt_label = "/", north = "/", },
    }
)

-- add Ü key
table.insert(
    keys[2],
    {
        { "Ü", north = "ü",     south = "Ű", },
        { "ü", north = "Ü",     south = "ű", },
        { "✗", north = "✘", west = "☐", south = "☒", },
        { "✓", north = "✔", west = "☐", south = "☑", },
    }
)

-- add - key
table.insert(
    keys[3],
    {
        { "_", alt_label = "-", north = "-", },
        { "-", alt_label = "_", north = "_", },
        { "*", alt_label = "#", north = "#", },
        { "#", alt_label = "*", north = "*", },
    }
)

keys[5][4].label = "␣"
keys[5][4].width = 4 -- resize Spacebar
keys[4][1].width = 2 -- resize Shift
keys[4][9].width = 2 -- resize Backspace

return hu_keyboard
