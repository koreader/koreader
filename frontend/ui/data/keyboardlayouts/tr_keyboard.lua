-- Start with the english keyboard layout (deep copy, to not alter it)
local tr_keyboard = require("util").tableDeepCopy(require("ui/data/keyboardlayouts/en_keyboard"))

local keys = tr_keyboard.keys

-- Insert 2 additional key at the end of first 3 rows.
-- 5th and 6th modes are from Kurdish and Azerbaijani alphabets.
-- Add Ğ, G with breve
table.insert(keys[1],
           --  1       2       3       4       5       6       7       8
            { "Ğ",    "ğ",    "«",    "μ",    "Ź",    "ź",    "γ",    "σ", }
)

-- Add Ü, U with umlaut
table.insert(keys[1],
           --  1       2       3       4       5       6       7       8
            { "Ü",    "ü",    "»",    "β",    "Ə",    "ə",    "δ",    "ψ", }
)

-- Add Ş, S with cedilla
table.insert(keys[2],
           --  1       2       3       4       5       6       7       8
            { "Ş",    "ş",    "`",    "α",    "Ḧ",    "ḧ",    "ε",    "χ", }
)

-- Add İ and i, dotted I and i
table.insert(keys[2],
           --  1       2       3       4       5       6       7       8
            { "İ",    "i",    "₺",    "θ",    "Ẍ",    "ẍ",    "η",    "τ", }
)

-- Add Ö, O with umlaut
table.insert(keys[3], 9,
           --  1       2       3       4       5       6       7       8
            { "Ö",    "ö",    "²",    "π",    "Ł",    "ł",    "ι",    "ρ", }
)

-- Add Ç, C with cedilla
table.insert(keys[3], 10,
           --  1       2       3       4       5       6       7       8
            { "Ç",    "ç",    "℃",    "ω",    "Ř",    "ř",    "ν",    "κ", }
)

-- Add forward slash and .com symbol to 4th row since we have lot of empty space
--and most phones do this.
table.insert(keys[4], 7,
           --  1       2       3       4       5       6       7       8
            { ".com", "/",    "√",    "λ",    "\"",   "\"",  "ζ",    "ξ", }
)

-- Make .com and Unicode buttons larger since we still have space.
keys[4][3].width = 1.5
keys[4][7].width = 1.5

-- Change lowercase "i" to "ı"
keys[1][8][2] = "ı"

-- Translate the "space" string
keys[4][4].label = "boşluk"

--Or remove / and move Ü to 3rd row.
--keys[4][7] = keys[3][11]
--keys[3][11] = keys[1][12]
--table.remove(keys[1], 12)
--Shrink Backspace, Shift, Sym, Unicode buttons to normal.
--keys[3][1].width = 1
--keys[3][11].width = 1
--keys[4][1].width = 1
--keys[4][3].width = 1

return tr_keyboard
