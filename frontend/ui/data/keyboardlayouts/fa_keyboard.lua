local en_popup = require("ui/data/keyboardlayouts/keypopup/en_popup")
local fa_popup = require("ui/data/keyboardlayouts/keypopup/fa_popup")
local com = en_popup.com -- comma (,)
local prd = en_popup.prd -- period (.)
local _at = en_popup._at
local _eq = en_popup._eq -- equals sign (=)
local alef = fa_popup.alef
local ba = fa_popup.ba
local pe = fa_popup.pe
local jeem = fa_popup.jeem
local che = fa_popup.che
local daal = fa_popup.daal
local h_aa = fa_popup.h_aa -- This is Persian letter هـ / as in English "hello".
local waw = fa_popup.waw
local zay = fa_popup.zay
local jee = fa_popup.jee
local ha = fa_popup.ha     -- while this is Persian letter ح / as in the sound you make when blowing on a glass to clean it.
local tah = fa_popup.tah
local yaa = fa_popup.yaa
local kaf = fa_popup.kaf
local gaf = fa_popup.gaf
local lam = fa_popup.lam
local meem = fa_popup.meem
local nun = fa_popup.nun
local seen = fa_popup.seen
local ayin = fa_popup.ayin
local fah = fa_popup.fah
local saad = fa_popup.saad
local qaf = fa_popup.qaf
local raa = fa_popup.raa
local sheen = fa_popup.sheen
local taa = fa_popup.taa
local thaa = fa_popup.thaa
local th_aa = fa_popup.th_aa
local thaal = fa_popup.thaal
local dhad = fa_popup.dhad
local ghayn = fa_popup.ghayn
local khaa = fa_popup.khaa
local diacritics = fa_popup.diacritics
local diacritic_fat_ha = fa_popup.diacritic_fat_ha
local diacritic_damma = fa_popup.diacritic_damma
local diacritic_kasra = fa_popup.diacritic_kasra
local diacritic_sukoon = fa_popup.diacritic_sukoon
local diacritic_shadda = fa_popup.diacritic_shadda
local diacritic_tanween_fath = fa_popup.diacritic_tanween_fath
local diacritic_tanween_damm = fa_popup.diacritic_tanween_damm
local diacritic_tanween_kasr = fa_popup.diacritic_tanween_kasr
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
            { dhad,                     dhad,        "~",   "1", },
            { saad,                     saad,        "`",   "2", },
            { thaa,                     thaa,        "|",   "3", },
            { qaf,                      qaf,         "•",   "4", },
            { fah,                      fah,         "√",   "5", },
            { ghayn,                    ghayn,       "π",   "6", },
            { ayin,                     ayin,        "÷",   "7", },
            { h_aa,                     h_aa,        "×",   "8", },
            { khaa,                     khaa,        "¶",   "9",  },
            { ha,                       ha,          "Δ",  "0",  },
            { jeem,                     jeem,        "‘",   ">"  },
        },
        -- second row
        {  --  1                         2            3       4
            { sheen,                    sheen,       "£",    _at, },
            { seen,                     seen,        "¥",    "#", },
            { yaa,                      yaa,         "$",    "﷼", },
            { ba,                       ba,          "¢",    "ـ", },
            { lam,                      lam,         "^",    "&", },
            { alef,                     alef,        "°",    "-", },
            { taa,                      taa,         "=",    "+", },
            { nun,                      nun,         "{",    "(", },
            { meem,                     meem,        "}",    ")" },
            { kaf,                      kaf,         "\\",   "٫", },
            { gaf,                      gaf,         "/",     "<", },
        },
        -- third row
        {  --  1                         2             3       4
            { th_aa,                    th_aa,        "٪",    "/", },
            { tah,                      tah,          "©",     "«", },
            { jee,                      jee,          "®",    "»", },
            { zay,                      zay,          "™",    ":", },
            { raa,                      raa,          "✓",   "؛", },
            { thaal,                    thaal,        "[",    "!", },
            { daal,                     daal,         "]",   "؟", },
            { pe,                       pe,         "↑",   "↑", },
            { waw,                      waw,          "←",    "←", },
            { che,                      che,        "→",   "→",  },
            { label = "",
              width = 1,
              bold = false
            },
        },
        -- fourth row
        {
            {"نشانه‌ها","نشانه‌ها","الفبا","الفبا",
              width = 1},
            { arabic_comma,    arabic_comma,  "2/2",  "1/2",
              width = 1},
            { label = "🌐", },
            { label = "فاصله",
              " ",        " ",    " ",    " ",
              width = 3.5},
              { label = ".‌|‌.",
              "‌",        "‌",    "‌",    "‌",
              width = 1},
            { prd,    prd,          "↓",    "↓", },
            { label = "حركات", diacritics, diacritics,    diacritics,  diacritics,
              width = 1},
            { label = "⮠",
              "\n",       "\n",   "\n",   "\n",
              width = 1.5,
            },
        },
    },
}
