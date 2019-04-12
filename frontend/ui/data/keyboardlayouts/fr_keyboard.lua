-- Start with the english keyboard layout
local fr_keyboard = dofile("frontend/ui/data/keyboardlayouts/en_keyboard.lua")

-- Swap the four AZWQ keys (only in the lowercase and
-- uppercase letters layouts) to change it from QWERTY to AZERTY
local keys = fr_keyboard.keys
keys[1][1][1], keys[2][1][1] = keys[2][1][1], keys[1][1][1] -- Q <> A
keys[1][1][2], keys[2][1][2] = keys[2][1][2], keys[1][1][2] -- q <> a
keys[1][2][1], keys[3][2][1] = keys[3][2][1], keys[1][2][1] -- W <> Z
keys[1][2][2], keys[3][2][2] = keys[3][2][2], keys[1][2][2] -- w <> z

-- Insert an additional key at the end of 2nd row for M
table.insert(keys[2],
           --  1           2       3       4       5       6       7       8       9       10      11      12
            { "M",        "m",    "§",    "+",    "Д",    "д",    "Э",    "э",    "Œ",    "œ",    "Ő",    "ő", }
)
-- And swap the english M on the 3rd row to ','
keys[3][8][1] = ","
keys[3][8][2] = ","
-- And swap the english ',' on the 4th row (an extended key
-- including a popup) to ';'
local en_com = keys[4][5][1]
en_com[1] = ";"
en_com.north = "," -- and swap the ';' there to ','

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
