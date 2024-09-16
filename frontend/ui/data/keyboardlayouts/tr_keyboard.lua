-- Start with the english keyboard layout
local tr_keyboard = dofile("frontend/ui/data/keyboardlayouts/en_keyboard.lua")

local keys = tr_keyboard.keys
-- Insert 2 additional key at the end of first 3 rows after numeric row.
-- Kurdish and Azerbaijani letters are on SYM layer (3 and 4).

-- Turkish Lira currency
table.insert(keys[1],
            { "₺", "₺", "₺", "₺", }
)
-- empty key to make extra keys on other rows fit
table.insert(keys[1],
            { "", "", "", "", }
)
-- Add Ğ, G with breve
table.insert(keys[2],
            { { "Ğ", north = "ğ", }, { "ğ", north = "Ğ", }, { "Ź", north = "ź", }, { "ź", north = "Ź", }, }
)
-- Add Ü, U with umlaut
table.insert(keys[2],
            { { "Ü", north = "ü", }, { "ü", north = "Ü", }, { "Ə", north = "ə", }, { "ə", north = "Ə", }, }
)
-- Add Ş, S with cedilla
table.insert(keys[3], 10,
            { { "Ş", north = "ş", }, { "ş", north = "Ş", }, { "Ḧ", north = "ḧ", }, { "ḧ", north = "Ḧ", }, }
)
-- Add İ and i, dotted I and i
table.insert(keys[3], 11,
            { { "İ", north = "i", }, { "i", north = "İ", }, { "Ẍ", north = "ẍ", }, { "ẍ", north = "Ẍ", }, }
)
-- Add Ö, O with umlaut
table.insert(keys[4], 9,
            { { "Ö", north = "ö", }, { "ö", north = "Ö", }, { "Ł", north = "ł", }, { "ł", north = "Ł", }, }
)
-- Add Ç, C with cedilla
table.insert(keys[4], 10,
            { { "Ç", north = "ç", }, { "ç", north = "Ç", }, { "Ř", north = "ř", }, { "ř", north = "Ř", }, }
)

-- change order "ḧ ẍ ," to ", ḧ ẍ"
keys[3][10][3], keys[3][11][3], keys[3][12][3] = keys[3][12][3], keys[3][10][3], keys[3][11][3]
keys[3][10][4], keys[3][11][4], keys[3][12][4] = keys[3][12][4], keys[3][10][4], keys[3][11][4]

-- Add forward slash and .com symbol to 4th row since we have lot of empty space
--and most phones do this.
table.insert(keys[5], 7,
            { ".com", "/", "\"", "\"", }
)

-- Make .com and Unicode buttons larger since we still have space.
--
keys[5][3].width = 1.5
keys[5][7].width = 1.5

-- Change lowercase "i" to dotless "ı"
keys[2][8][2] = {
        "ı", -- dotless i (Turkish)
        north = "I", -- dotless I (Turkish)
        northeast = "í",
        northwest = "ì",
        east = "î",
        west = "ĩ",
        south = "į",
        southeast = "ï",
        southwest = "ɪ",
        "ī",
        "ι", -- Greek iota
        "i", -- latin i
        }

keys[2][8][1] = {
        "I", -- dotless I
        north = "ı", -- dotless i (Turkish)
        northeast = "Í",
        northwest = "Ì",
        east = "Î",
        west = "Ĩ",
        south = "Į",
        southeast = "Ï",
        southwest = "ɪ",
        "Ī",
        "Ι", -- Greek iota
        "I",
        }

-- Translate the "space" string
keys[5][4].label = "boşluk"

return tr_keyboard
