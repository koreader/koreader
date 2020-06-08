-- Start with the english keyboard layout (deep copy, to not alter it)
local fr_keyboard = require("util").tableDeepCopy(require("ui/data/keyboardlayouts/en_keyboard"))

-- Swap the four AZWQ keys (only in the lowercase and
-- uppercase letters layouts) to change it from QWERTY to AZERTY
local keys = fr_keyboard.keys
keys[1][1][1], keys[2][1][1] = keys[2][1][1], keys[1][1][1] -- Q <> A
keys[1][1][2], keys[2][1][2] = keys[2][1][2], keys[1][1][2] -- q <> a
keys[1][2][1], keys[3][2][1] = keys[3][2][1], keys[1][2][1] -- W <> Z
keys[1][2][2], keys[3][2][2] = keys[3][2][2], keys[1][2][2] -- w <> z

-- Insert an additional key at the end of 2nd row for M
table.insert(keys[2],
           --  1       2       3       4       5       6       7       8
            { "M",    "m",    "§",    "+",    "Œ",    "œ",    "Ő",    "ő", }
)
-- But replace the alpha "M" and "m" with the original key+popup from english M/m
keys[2][10][1] = keys[3][8][1]
keys[2][10][2] = keys[3][8][2]

-- We have one more key than en_keyboard: replace that original M key
-- to show another char on alpha layouts: let's use ";", and a popup
-- helpful for CSS style tweaks editing.
local _semicolon = {
    ";",
    -- north = "!",
    north = { label = "!…", key = "!important;" },
    northeast = "}",
    northwest = "{",
    west = "-",
    east = ":",
    south = "*",
    southwest = "0",
    southeast = ">",
    "[",
    '+',
    "]",
}
keys[3][8][1] = _semicolon
keys[3][8][2] = _semicolon

-- Swap ê and ë (and the like) in the keyboard popups, so the
-- common french accentuated chars are all on the upper row.
local popups = {
    keys[1][1][1], -- A
    keys[1][1][2], -- a
    keys[1][3][1], -- E
    keys[1][3][2], -- e
    keys[1][7][1], -- U
    keys[1][7][2], -- u
    keys[1][8][1], -- I
    keys[1][8][2], -- i
    keys[1][9][1], -- O
    keys[1][9][2], -- o
}
for _, popup in ipairs(popups) do
    popup.north, popup.east = popup.east, popup.north
end

-- Remove the "space" string
keys[4][4].label = ""
-- Or, if we'd rather have it in french:
-- keys[4][4].label = "espace"

return fr_keyboard
