local en_popup = dofile("frontend/ui/data/keyboardlayouts/keypopup/en_popup.lua")
local fa_popup = dofile("frontend/ui/data/keyboardlayouts/keypopup/fa_popup.lua")
local prd = en_popup.prd -- period (.)
local _at = en_popup._at
local alef = fa_popup.alef
local h_aa = fa_popup.h_aa -- This is Persian letter هـ / as in English "hello".
local waw = fa_popup.waw
local yaa = fa_popup.yaa
local kaf = fa_popup.kaf
local diacritics = fa_popup.diacritics
local arabic_comma = fa_popup.arabic_comma

return {
    min_layer = 1,
    max_layer = 4,
    shiftmode_keys = {["1/2"] = true, ["2/2"] = true},
    symbolmode_keys = {["نشانه‌ها"] = true,["الفبا"]=true},      -- نشانه‌ها means "Symbol", الفبا means "letter" (traditionally "ABC" on QWERTY layouts)
    utf8mode_keys = {["🌐"] = true},                      -- The famous globe key for layout switching
    umlautmode_keys = {["Äéß"] = false},                  -- No need for this keyboard panel
    keys = {
        -- first row
        {  --  1                         2            3      4
            { "ض",                     "ض",        "~",   "1", },
            { "ص",                     "ص",        "`",   "2", },
            { "ث",                     "ث",        "|",   "3", },
            { "ق",                      "ق",         "•",   "4", },
            { "ف",                      "ف",         "√",   "5", },
            { "غ",                    "غ",       "π",   "6", },
            { "ع",                     "ع",        "÷",   "7", },
            { h_aa,                     h_aa,        "×",   "8", },
            { "خ",                     "خ",        "¶",   "9",  },
            { "ح",                       "ح",          "Δ",  "0",  },
            { "ج",                     "ج",        "‘",   ">"  },
        },
        -- second row
        {  --  1                         2            3       4
            { "ش",                    "ش",       "£",    _at, },
            { "س",                     "س",        "¥",    "#", },
            { yaa,                      yaa,         "$",    "﷼", },
            { "ب",                       "ب",          "¢",    "ـ", },
            { "ل",                      "ل",         "^",    "&", },
            { alef,                     alef,        "°",    "-", },
            { "ت",                      "ت",         "=",    "+", },
            { "ن",                      "ن",         "{",    "(", },
            { "م",                     "م",        "}",    ")" },
            { kaf,                      kaf,         "\\",   "٫", },
            { "گ",                      "گ",         "/",     "<", },
        },
        -- third row
        {  --  1                         2             3       4
            { "ظ",                    "ظ",        "٪",    "/", },
            { "ط",                      "ط",          "©",     "«", },
            { "ژ",                      "ژ",          "®",    "»", },
            { "ز",                      "ز",          "™",    ":", },
            { "ر",                      "ر",          "✓",   "؛", },
            { "ذ",                    "ذ",        "[",    "!", },
            { "د",                     "د",         "]",   "؟", },
            { "پ",                       "پ",         "↑",   "↑", },
            { waw,                      waw,          "←",    "←", },
            { "چ",                      "چ",        "→",   "→",  },
            { label = "",
              width = 1,
              bold = false
            },
        },
        -- fourth row
        {
            {"نشانه‌ها","نشانه‌ها","الفبا","الفبا",
              width = 1.75},
            { arabic_comma,    arabic_comma,  "2/2",  "1/2",
              width = 1},
            { label = "🌐", },
            { label = "فاصله",
              " ",        " ",    " ",    " ",
              width = 3.6},
              { label = ".‌|‌.",
              diacritics,        diacritics,    diacritics,    diacritics,
              width = 1},
            { prd,    prd,          "↓",    "↓", },
            { label = "⮠",
              "\n",       "\n",   "\n",   "\n",
              width = 1.7,
            },
        },
    },
}
