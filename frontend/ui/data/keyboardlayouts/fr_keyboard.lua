-- Start with the english keyboard layout
local fr_keyboard = dofile("frontend/ui/data/keyboardlayouts/en_keyboard.lua")

-- Swap the four AZWQ keys (only in the lowercase and
-- uppercase letters layouts) to change it from QWERTY to AZERTY
local keys = fr_keyboard.keys
keys[2][1][1], keys[3][1][1] = keys[3][1][1], keys[2][1][1] -- Q <> A
keys[2][1][2], keys[3][1][2] = keys[3][1][2], keys[2][1][2] -- q <> a
keys[2][2][1], keys[4][2][1] = keys[4][2][1], keys[2][2][1] -- W <> Z
keys[2][2][2], keys[4][2][2] = keys[4][2][2], keys[2][2][2] -- w <> z
-- And as A/a is now near the left border, re-order the popup keys so that we can get
-- the à (very common in french) with a swipe south-east instead of hard north-west
keys[2][1][1].southeast, keys[2][1][1].northwest = keys[2][1][1].northwest, keys[2][1][1].southeast
keys[2][1][2].southeast, keys[2][1][2].northwest = keys[2][1][2].northwest, keys[2][1][2].southeast

-- Swap the M and ',' keys
keys[3][10][1], keys[4][8][1] = keys[4][8][1], keys[3][10][1] -- M <> ;
keys[3][10][2], keys[4][8][2] = keys[4][8][2], keys[3][10][2] -- m <> ,
-- And as M/m is now near the right border, swap its popup east swipes to be west swipes
keys[3][10][1].northwest, keys[3][10][1].northeast = keys[3][10][1].northeast, nil
keys[3][10][2].northwest, keys[3][10][2].northeast = keys[3][10][2].northeast, nil
keys[3][10][1].west, keys[3][10][1].east = keys[3][10][1].east, nil
keys[3][10][2].west, keys[3][10][2].east = keys[3][10][2].east, nil

-- Remove the "space" string
keys[5][4].label = ""
-- Or, if we'd rather have it in french:
-- keys[5][4].label = "espace"

return fr_keyboard
