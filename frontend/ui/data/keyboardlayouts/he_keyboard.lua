local en_popup = require("ui/data/keyboardlayouts/keypopup/en_popup")
local he_popup = require("ui/data/keyboardlayouts/keypopup/he_popup")
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
    shiftmode_keys = {["Shift"] = true},
    symbolmode_keys = {["Sym"] = true, ["אבג"] = true},
    utf8mode_keys = {["IM"] = true},
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
        },
        -- third row
        {  --  1           2       3       4
            { label = "Shift",
              icon = "resources/icons/appbar.arrow.shift.png",
              width = 1.5
            },
            { "׃",    zayin,     "&",    "7", },
            { "׀",    samech,    "*",    "8", },
            { "ׄ ",    beis,      "£",    "9", },
            { "ׅ ",    hey,       "<",    com, },
            { "־",    nun,       ">",    prd, },
            { "ֿ ",    mem,      "‘",    "↑",  },
            { "ֽ ",    tzadik,   "’",    "↓",  },
            { label = "Backspace",
              icon = "resources/icons/appbar.clear.reflect.horizontal.png",
              width = 1.5
            },
        },
        -- fourth row
        {
            { "Sym",  "Sym",    "אבג",  "אבג",
              width = 1.5},
            { label = "IM",
              icon = "resources/icons/appbar.globe.wire.png",
            },
            { label = "space",
              " ",        " ",    " ",    " ",
              width = 3.0},
            { com,    taf,      "“",    "←", },
            { prd,    "ץ",      "”",    "→", },
            { label = "Enter",
              "\n",   "\n",    "\n",   "\n",
              icon = "resources/icons/appbar.arrow.enter.png",
              width = 1.5,
            },
        },
    },
}
