local en_popup = dofile("frontend/ui/data/keyboardlayouts/keypopup/en_popup.lua")
local ro_popup = dofile("frontend/ui/data/keyboardlayouts/keypopup/ro_popup.lua")
local com = en_popup.com -- comma (,)
local prd = en_popup.prd -- period (.)
local _at = en_popup._at
local _eq = en_popup._eq -- equals sign (=)
local _A_ = ro_popup._A_
local _a_ = ro_popup._a_
local _I_ = ro_popup._I_
local _i_ = ro_popup._i_
local _S_ = ro_popup._S_
local _s_ = ro_popup._s_
local _T_ = ro_popup._T_
local _t_ = ro_popup._t_
local _U_ = ro_popup._U_
local _u_ = ro_popup._u_

return {
    min_layer = 1,
    max_layer = 8,
    shiftmode_keys = {[""] = true, ["1/2"] = true, ["2/2"] = true},
    symbolmode_keys = {["123"] = true, ["ABC"] = true, ["alt"] = true},
    utf8mode_keys = {["🌐"] = true},
    umlautmode_keys = {["Îșț"] = true},
    keys = {
        -- first row
        {  --  1       2       3       4       5       6       7       8
            { "Q",    "q",    "„",    "0",    "Ӂ",    "ӂ",    "1",    "ª", },
            { "W",    "w",    "!",    "1",    "Џ",    "џ",    "2",    "º", },
            { "E",    "e",    _at,    "2",    "Ѫ",    "ѫ",    "3",    "¡", },
            { "R",    "r",    "#",    "3",    "Ꙟ",    "ꙟ",    "4",    "¿", },
            { _T_,    _t_,    "+",    _eq,    "Ѧ",    "ѧ",    "5",    "¼", },
            { "Y",    "y",    "€",    "(",    "Ô",    "ô",    "6",    "½", },
            { _U_,    _u_,    "‰",    ")",    "Ḑ",    "ḑ",    "7",    "¾", },
            { _I_,    _i_,    "|",   "\\",    "Ĕ",    "ĕ",    "8",    "©", },
            { "O",    "o",    "?",    "/",    "Ă",    "ă",    "9",    "®", },
            { "P",    "p",    "~",    "`",    "Î",    "î",    "0",    "™", },
        },
        -- second row
        {  --  1       2       3       4       5       6       7       8
            { _A_,    _a_,    "…",    _at,    "Ї",    "ї",    "«",    "«", },
            { _S_,    _s_,    "$",    "4",    "Ѡ",    "ѡ",    "»",    "»", },
            { "D",    "d",    "%",    "5",    "Є",    "є",    "Ǧ",    "ǧ", },
            { "F",    "f",    "^",    "6",    "Ꙋ",    "ꙋ",    "Ć",    "ć", },
            { "G",    "g",    ":",    ";",    "Û",    "û",    "Č",    "č", },
            { "H",    "h",    '"',    "'",    "Ê",    "ê",    "Đ",    "đ", },
            { "J",    "j",    "{",    "[",    "Ș",    "ș",    "Š",    "š", },
            { "K",    "k",    "}",    "]",    "Ț",    "ț",    "Ž",    "ž", },
            { "L",    "l",    "_",    "-",    "Â",    "â",    "§",    "§", },
        },
        -- third row
        {  --  1       2       3       4       5       6       7       8
            { "",   "",   "2/2",  "1/2",   "",   "",   "",    "",
              width = 1.5
            },
            { "Z",    "z",    "&",    "7",    "Ѣ",    "ѣ",    "Ű",    "ű", },
            { "X",    "x",    "*",    "8",    "Ѩ",    "ѩ",    "Ã",    "ã", },
            { "C",    "c",    "£",    "9",    "Ѥ",    "ѥ",    "Þ",    "þ", },
            { "V",    "v",    "<",    com,    "Ó",    "ó",    "Ý",    "ý", },
            { "B",    "b",    ">",    prd,    "É",    "é",    "†",    "‡", },
            { "N",    "n",    "‘",    "↑",    "Ŭ",    "ŭ",    "–",    "—", },
            { "M",    "m",    "’",    "↓",    "Ĭ",    "ĭ",    "…",    "¨", },
            { label = "",
              width = 1.5,
              bold = false
            },
        },
        -- fourth row
        {
            { "123",  "123",  "ABC",  "ABC",  "alt",  "alt",  "ABC",  "ABC",
              width = 1.5},
            { label = "🌐", },
            { "Îșț",  "Îșț",  "Îșț",  "Îșț",  "Îșț",  "Îșț",  "Îșț",  "Îșț", },
            { label = "spațiu",
              " ",    " ",    " ",    " ",    " ",    " ",    " ",    " ",
              width = 3.0},
            { com,    com,    "“",    "←",    "Ç",   "ç",    com,    com, },
            { prd,    prd,    "”",    "→",    "Ŏ",   "ŏ",    prd,    prd, },
            { label = "⮠",
              "\n",   "\n",   "\n",   "\n",   "\n",   "\n",   "\n",   "\n",
              width = 1.5,
              bold = true
            },
        },
    },
}
