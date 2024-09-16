-- Start with the english keyboard layout
local no_keyboard = dofile("frontend/ui/data/keyboardlayouts/en_keyboard.lua")

local keys = no_keyboard.keys

-- add ' key next to numeric 0
table.insert(
    keys[1],
    {
        { "*", alt_label = "'", north = "'", },
        { "'", alt_label = "*", north = "*", },
        { "/", alt_label = "÷", north = "÷", },
        { "÷", alt_label = "/", north = "/", },
    }
)

-- add Å key
table.insert(
    keys[2],
    {
        { "Å", north = "å", },
        { "å", north = "Å", },
        { "*", alt_label = "×", north = "×", },
        { "×", alt_label = "*", north = "*", },
    }
)

-- add Æ key
table.insert(
    keys[3],
    {
        { "Æ", north = "æ", },
        { "æ", north = "Æ", },
        { "✗", north = "✘", west = "☐", south = "☒", },
        {
            "⭤",
            north = "⭡",
            northeast = "⭧",
            northwest = "⭦",
            east = "⭢",
            west = "⭠",
            south = "⭣",
            southeast = "⭨",
            southwest = "⭩",
        },
    }
)

-- add Ø key
table.insert(
    keys[4],
    7,
    {
        { "Ø", north = "ø", },
        { "ø", north = "Ø", },
        { "✓", north = "✔", west = "☐", south = "☑", },
        { "•", alt_label = "◦", north = "◦", northwest = "⁃", west = "‣", },
    }
)

-- swap "Ø" and ";" / "ø" and ","
keys[4][7][1], keys[3][10][1] = keys[3][10][1], keys[4][7][1]
keys[4][7][2], keys[3][10][2] = keys[3][10][2], keys[4][7][2]

-- swap ";" and "✓" / "," and "•"
keys[4][7][3], keys[3][10][3] = keys[3][10][3], keys[4][7][3]
keys[4][7][4], keys[3][10][4] = keys[3][10][4], keys[4][7][4]

-- change order ", n m" to "n m ,"
keys[4][7][1], keys[4][8][1], keys[4][9][1] = keys[4][8][1], keys[4][9][1], keys[4][7][1]
keys[4][7][2], keys[4][8][2], keys[4][9][2] = keys[4][8][2], keys[4][9][2], keys[4][7][2]

-- Rename "space" and resize buttons
keys[5][4].label = "␣" -- label the Spacebar with Unicode space symbol
keys[4][1].width = 1.5 -- resize Shift
keys[4][10].width = 1.5 -- resize Backspace
keys[5][4].width = 4 -- resize Spacebar
keys[5][1].width = 1.5 -- resize Symbols
keys[5][7].width = 1.5 -- resize Enter

return no_keyboard
