-- Start with the english keyboard layout
local pl_keyboard = dofile("frontend/ui/data/keyboardlayouts/en_keyboard.lua")

local keys = pl_keyboard.keys

-- popup keyboard - move polish characters to east
--keys[2][3][1].east = 'Ę'; keys[1][3][1].south = 'Ê'
--keys[2][3][2].east = 'ę'; keys[1][3][2].south = 'ê'
keys[2][3][1].east, keys[2][3][1].south = keys[2][3][1].south, keys[2][3][1].east
keys[2][3][2].east, keys[2][3][2].south = keys[2][3][2].south, keys[2][3][2].east

-- keys[2][9][1].east = 'Ó'; keys[1][9][1].northeast = 'Ô'
-- keys[2][9][2].east = 'ó'; keys[1][9][2].northeast = 'ô'
keys[2][9][1].east, keys[2][9][1].south = keys[2][9][1].south, keys[2][9][1].east
keys[2][9][2].east, keys[2][9][2].south = keys[2][9][2].south, keys[2][9][2].east

-- keys[3][1][1].east = 'Ą'; keys[2][1][1].south = 'Â'
-- keys[3][1][2].east = 'ą'; keys[2][1][2].south = 'â'
keys[3][1][1].east, keys[3][1][1].south = keys[3][1][1].south, keys[3][1][1].east
keys[3][1][2].east, keys[3][1][2].south = keys[3][1][2].south, keys[3][1][2].east

-- keys[3][2][1].east = 'Ś'; keys[2][2][1].northeast = 'Ŝ'
-- keys[3][2][2].east = 'ś'; keys[2][2][2].northeast = 'ŝ'
keys[3][2][1].east, keys[3][2][1].northeast = keys[3][2][1].northeast, keys[3][2][1].east
keys[3][2][2].east, keys[3][2][2].northeast = keys[3][2][2].northeast, keys[3][2][2].east


-- keys[3][9][1].east = 'Ł'; keys[2][9][1].west = '+'
-- keys[3][9][2].east = 'ł'; keys[2][9][2].west = '+'
keys[3][9][1].east, keys[3][9][1].west = keys[3][9][1].west, keys[3][9][1].east
keys[3][9][2].east, keys[3][9][2].west = keys[3][9][2].west, keys[3][9][2].east

-- keys[4][2][1].east = 'Ż'; keys[3][2][1].southwest = ''
-- keys[4][2][2].east = 'ż'; keys[3][2][2].southwest = ''
keys[4][2][1].west, keys[4][2][1].southwest = keys[4][2][1].southwest, keys[4][2][1].west
keys[4][2][2].west, keys[4][2][2].southwest = keys[4][2][2].southwest, keys[4][2][2].west

-- keys[4][2][1].west = 'Ź'; keys[3][2][1].northeast = 'Ž'
-- keys[4][2][2].west = 'ź'; keys[3][2][2].northeast = 'ž'
-- ?
-- keys[4][3][1].east = 'Ź'; keys[3][3][1].north = 'Χ'
-- keys[4][3][2].east = 'ź'; keys[3][3][2].north = 'χ'
-- ?

-- keys[4][4][1].east = 'Ć'; keys[3][4][1].northeast = 'Ĉ'
-- keys[4][4][2].east = 'ć'; keys[3][4][2].northeast = 'ĉ'
keys[4][4][1].east, keys[4][4][1].northeast = keys[4][4][1].northeast, keys[4][4][1].east
keys[4][4][2].east, keys[4][4][2].northeast = keys[4][4][2].northeast, keys[4][4][2].east

-- keys[4][7][1].east = 'Ń'; keys[3][7][1].northeast = 'ɲ'
-- keys[4][7][2].east = 'ń'; keys[3][7][2].northeast = 'ɲ'
keys[4][7][1].east, keys[4][7][1].northeast = keys[4][7][1].northeast, keys[4][7][1].east
keys[4][7][2].east, keys[4][7][2].northeast = keys[4][7][2].northeast, keys[4][7][2].east

-- space
keys[5][4].label = ""

return pl_keyboard
