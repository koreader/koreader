-- Start with the norwegian keyboard layout
local da_keyboard = dofile("frontend/ui/data/keyboardlayouts/no_keyboard.lua")

local keys = da_keyboard.keys

-- swap "Ø" and "Æ", and "ø" and "æ"
keys[3][10][1], keys[3][11][1] = keys[3][11][1], keys[3][10][1]
keys[3][10][2], keys[3][11][2] = keys[3][11][2], keys[3][10][2]

return da_keyboard
