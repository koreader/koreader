-- Start with the english keyboard layout (deep copy, to not alter it)
local pl_keyboard = require("util").tableDeepCopy(require("ui/data/keyboardlayouts/en_keyboard"))

local keys = pl_keyboard.keys

-- Umlaut keys on standard keyboard
keys[1][3][5] = 'Ę'
keys[1][3][6] = 'ę'
keys[1][9][5] = 'Ó'
keys[1][9][6] = 'ó'
keys[2][1][5] = 'Ą'
keys[2][1][6] = 'ą'
keys[2][2][5] = 'Ś'
keys[2][2][6] = 'ś'
keys[2][9][5] = 'Ł'
keys[2][9][6] = 'ł'
keys[3][2][5] = 'Ż'
keys[3][2][6] = 'ż'
keys[3][3][5] = 'Ź'
keys[3][3][6] = 'ź'
keys[3][4][5] = 'Ć'
keys[3][4][6] = 'ć'
keys[3][7][5] = 'Ń'
keys[3][7][6] = 'ń'

-- popup keyboard - move polish characters to east
keys[1][3][1].east = 'Ę'; keys[1][3][1].south = 'Ê'
keys[1][3][2].east = 'ę'; keys[1][3][2].south = 'ê'
keys[1][9][1].east = 'Ó'; keys[1][9][1].northeast = 'Ô'
keys[1][9][2].east = 'ó'; keys[1][9][2].northeast = 'ô'
keys[2][1][1].east = 'Ą'; keys[2][1][1].south = 'Â'
keys[2][1][2].east = 'ą'; keys[2][1][2].south = 'â'
keys[2][2][1].east = 'Ś'; keys[2][2][1].northeast = 'Ŝ'
keys[2][2][2].east = 'ś'; keys[2][2][2].northeast = 'ŝ'
keys[2][9][1].east = 'Ł'; keys[2][9][1].west = '+'
keys[2][9][2].east = 'ł'; keys[2][9][2].west = '+'
keys[3][2][1].east = 'Ż'; keys[3][2][1].southwest = ''
keys[3][2][1].west = 'Ź'; keys[3][2][1].northeast = 'Ž'
keys[3][2][2].east = 'ż'; keys[3][2][2].southwest = ''
keys[3][2][2].west = 'ź'; keys[3][2][2].northeast = 'ž'
keys[3][3][1].east = 'Ź'; keys[3][3][1].north = 'Χ'
keys[3][3][2].east = 'ź'; keys[3][3][2].north = 'χ'
keys[3][4][1].east = 'Ć'; keys[3][4][1].northeast = 'Ĉ'
keys[3][4][2].east = 'ć'; keys[3][4][2].northeast = 'ĉ'
keys[3][7][1].east = 'Ń'; keys[3][7][1].northeast = 'ɲ'
keys[3][7][2].east = 'ń'; keys[3][7][2].northeast = 'ɲ'

-- space
keys[4][4].label = ""

return pl_keyboard
