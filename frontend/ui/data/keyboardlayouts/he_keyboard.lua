local en_popup = require("ui/data/keyboardlayouts/keypopup/en_popup")
local he_popup = require("ui/data/keyboardlayouts/keypopup/he_popup")
local pco = en_popup.pco
local cop = en_popup.cop
local cse = en_popup.cse
local sec = en_popup.sec
local quo = en_popup.quo
local com = en_popup.com -- comma (,)
local prd = en_popup.prd -- period (.)
local _at = en_popup._at
local _eq = en_popup._eq -- equals sign (=)
local aleph = he_popup.aleph
local beis = he_popup.beis
local gimmel = he_popup.gimmel
local daled = he_popup.daled
local hey = he_popup.hey
local vov = he_popup.vov
local zayin = he_popup.zayin
local tes = he_popup.tes
local yud = he_popup.yud
local chof = he_popup.chof
local lamed = he_popup.lamed
local mem = he_popup.mem
local mem_sofis = he_popup.mem_sofis
local nun = he_popup.nun
local samech = he_popup.samech
local ayin = he_popup.ayin
local pey = he_popup.pey
local pey_sofis = he_popup.pey_sofis
local tzadik = he_popup.tzadik
local kuf = he_popup.kuf
local reish = he_popup.reish
local shin = he_popup.shin
local taf = he_popup.taf

return {
    min_layer = 1,
    max_layer = 4,
    shiftmode_keys = {[""] = true},
    symbolmode_keys = { ["⌥"] = true },
    utf8mode_keys = {["🌐"] = true},
    keys = {
        -- first row
        {  --  1           2       3       4
            { "׳",    "״",       "„",    "0", },
            { "֘֘֙֙ ",    kuf,       "!",    "1", },
            { "֘ ",    reish,     _at,    "2", },
            { "֗",    aleph,      "#",    "3", },
            { "֖ ",    tes,       "+",    _eq, },
            { "֕ ",    vov,       "€",    "(", },
            { "֔ ",    "ן",       "‰",    ")", },
            { "֓ ",    mem_sofis, "|",   "\\", },
            { "֒ ",    pey,       "?",    "/", },
            { "֑ ",    pey_sofis, "~",    "`", },
        },
        -- second row
        {  --  1           2       3       4
            { "ּ ",    shin,      "…",    _at, },
            { "ֻ ",    daled,     "$",    "4", },
            { "ִ ",    gimmel,    "%",    "5", },
            { "ֹ",    chof,      "^",    "6",  },
            { "ְ ",    ayin,      ":",    ";", },
            { "ֵ ",    yud,        '"',   "'", },
            { "ֶ ",    "ח",       "{",    "[", },
            { "ַ ",   lamed,      "}",    "]", },
            { "ָ ",    "ך",       "_",    "-", },
            { sec, cse, sec, cse, }, -- comma/semicolon with CSS popup block
        },
        -- third row
        {  --  1           2       3       4
            { label = "",
              width = 1.5
            },
            { "׃",    zayin,     "&",    "7", },
            { "׀",    samech,    "*",    "8", },
            { "ׄ ",    beis,      "£",    "9", },
            { "ׅ ",    hey,       "<",    com, },
            { "־",    nun,       ">",    prd, },
            { "ֿ ",    mem,      "‘",    "↑",  },
            { "ֽ ",    tzadik,   "’",    "↓",  },
            { label = "",
              width = 1.5,
              bold = false
            },
        },
        -- fourth row
        {
            { label = "⌥", width = 1.5, bold = true, alt_label = "SYM"}, -- SYM key
            { label = "🌐", },
            { cop, pco, cop, pco, }, -- period/colon with RegEx popup block
            { " ",        " ",    " ",    " ",
              width = 3.0, label = "_"},
            { com,    taf,      "“",    "←", },
            { prd,    "ץ",      "”",    "→", },
            { label = "⮠",
              "\n",   "\n",    "\n",   "\n",
              width = 1.5,
              bold = true
            },
        },
    },
}
