local en_popup = require("ui/data/keyboardlayouts/keypopup/en_popup")
local ar_popup = require("ui/data/keyboardlayouts/keypopup/ar_AA_popup")
local com = en_popup.com -- comma (,)
local prd = en_popup.prd -- period (.)
local _at = en_popup._at
local _eq = en_popup._eq -- equals sign (=)
local alef = ar_popup.alef
local ba = ar_popup.ba
local jeem = ar_popup.jeem
local daal = ar_popup.daal
local h_aa = ar_popup.h_aa
local waw = ar_popup.waw
local zay = ar_popup.zay
local ha = ar_popup.ha
local tah = ar_popup.tah
local yaa = ar_popup.yaa
local kaf = ar_popup.kaf
local lam = ar_popup.lam
local meem = ar_popup.meem
local nun = ar_popup.nun
local seen = ar_popup.seen
local ayin = ar_popup.ayin
local fah = ar_popup.fah
local saad = ar_popup.saad
local qaf = ar_popup.qaf
local raa = ar_popup.raa
local sheen = ar_popup.sheen
local taa = ar_popup.taa
local thaa = ar_popup.thaa
local thaal = ar_popup.thaal
local dhad = ar_popup.dhad
local ghayn = ar_popup.ghayn
local khaa = ar_popup.khaa
local hamza = ar_popup.hamza
local wawhamza = ar_popup.wawhamza
local laa = ar_popup.laa
local alefmaqsoura = ar_popup.alefmaqsoura
local taamarbouta = ar_popup.taamarbouta
local diacritics = ar_popup.diacritics
local diacritic_fat_ha = ar_popup.diacritic_fat_ha
local diacritic_damma = ar_popup.diacritic_damma
local diacritic_kasra = ar_popup.diacritic_kasra
local diacritic_sukoon = ar_popup.diacritic_sukoon
local diacritic_shadda = ar_popup.diacritic_shadda
local diacritic_tanween_fath = ar_popup.diacritic_tanween_fath
local diacritic_tanween_damm = ar_popup.diacritic_tanween_damm
local diacritic_tanween_kasr = ar_popup.diacritic_tanween_kasr
local arabic_comma = ar_popup.arabic_comma


return {
    min_layer = 1,
    max_layer = 4,
    shiftmode_keys = {["بدّل"] = true},
    symbolmode_keys = {["رمز"] = true,["حرف"]=true},
    utf8mode_keys = {["🌐"] = true},
    umlautmode_keys = {["Äéß"] = false},
    keys = {
        -- first row
        {  --  1        2       3       4
            { diacritic_fat_ha,    dhad,    "׳",    "0", },
            { diacritic_tanween_fath,    saad,    "",    "1", },
            { diacritic_damma,    thaa,    "֘ ",    "2", },
            { diacritic_tanween_damm,     qaf,     "֗",    "3", },
            { "ﻹ",     fah,     "֖ ",    _eq, },
            { "إ",   ghayn,    "֕ ",    "(", },
            { "`",    ayin,    "֔ ",    ")", },
            { "÷",    h_aa,    "֓ ",    "ـ", },
            { "×",    khaa,    "֒ ",    "ّ",  },
            { "؛",      ha,    "֑ ",    "ٌ",  },
            { "<",    jeem,    "֑",     "ً",  },
            { ">",    daal,    "ֽ ",    "~", },
        },
        -- second row
        {  --  1         2       3       4
            { diacritic_kasra,     sheen,    "ּ ",    "4", },
            { diacritic_tanween_kasr,     seen,     "ֻ ",   "5", },
            { "]",      yaa,     "ִ ",   "6", },
            { "[",       ba,     "ֹ",    ";", },
            { "ﻷ",      lam,     "ְ ",   "'", },
            { "أ",     alef,     "ֵ ",  "\\", },
            { "ـ",      taa,     "ֶ ",    "ّ", },
            { "،",      nun,     "ַ ",    "ْ", },
            { "/",     meem,     "ָ ",    "ِ", },
            { ":",      kaf,     "ָ ",    "ُ", },
            { "\"",      tah,     "ָ ",    "َ", },
        },
        -- third row
        {  --  1              2            3       4
            { diacritic_shadda,          thaal,        "׃",    "7", },
            { diacritic_sukoon,        hamza,        "׀",    "8", },
            { "}",     wawhamza,     "ׄ ",    "9", },
            { "{",          raa,          "ׅ ",    com, },
            { "ﻵ",          laa,          "־",    prd, },
            { "آ", alefmaqsoura, "ֿ ",    "[", },
            { "'",  taamarbouta,  "ֽ ",    "]", },
            {  arabic_comma,          waw,          "ֽ ",    "↑", },
            { ".",          zay,          "ֽ ",    "↓", },
            { "؟",         thaa,         "ֽ ",    _at, },
            { label = "Backspace",
              icon = "resources/icons/appbar.clear.reflect.horizontal.png",
              width = 1.5
            },
        },
        -- fourth row
        {
            { "بدّل",     "بدّل",  "بدّل",  "بدّل",
              width = 1.5},
            { label = "🌐", },
            { "رمز",     "رمز",  "حرف",  "حرف", 
              width = 1.25},
            { label = "مسافة",
              " ",        " ",    " ",    " ",
              width = 3.0},
            { com,    arabic_comma, "“",    "←", },
            { prd,    prd,          "”",    "→", },
            { label = "حركات", diacritics, diacritics,    diacritics,  diacritics,  
              width = 1.25},
            { label = "Enter",
              "\n",       "\n",   "\n",   "\n",
              icon = "resources/icons/appbar.arrow.enter.png",
              width = 1.5,
            },

    },
}
}
