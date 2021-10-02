local en_popup = require("ui/data/keyboardlayouts/keypopup/en_popup")
local vn_popup = require("ui/data/keyboardlayouts/keypopup/vn_popup")
local com = en_popup.com -- comma (,)
local prd = en_popup.prd -- period (.)
local _at = en_popup._at
local _eq = en_popup._eq -- equals sign (=)

local _A_ = vn_popup._A_
local _a_ = vn_popup._a_
local _AW_ = vn_popup._AW_
local _aw_ = vn_popup._aw_
local _AA_ = vn_popup._AA_
local _aa_ = vn_popup._aa_
local _E_ = vn_popup._E_
local _e_ = vn_popup._e_
local _EE_ = vn_popup._EE_
local _ee_ = vn_popup._ee_
local _I_ = vn_popup._I_
local _i_ = vn_popup._i_
local _O_ = vn_popup._O_
local _o_ = vn_popup._o_
local _OO_ = vn_popup._OO_
local _oo_ = vn_popup._oo_
local _OW_ = vn_popup._OW_
local _ow_ = vn_popup._ow_
local _U_ = vn_popup._U_
local _u_ = vn_popup._u_
local _UW_ = vn_popup._UW_
local _uw_ = vn_popup._uw_
local _Y_ = vn_popup._Y_
local _y_ = vn_popup._y_

return {
    min_layer = 1,
    max_layer = 8,
    shiftmode_keys = {[""] = true, ["1/2"] = true, ["2/2"] = true,},
    symbolmode_keys = {["Sym"] = true, ["ABC"] = true},
    utf8mode_keys = {["🌐"] = true},
    umlautmode_keys = {["Äéß"] = true},
    keys = {
        -- first row
        {  --  1       2       3       4       5       6       7       8
            { "Q",    "q",    "„",    "0",    _AW_,  _aw_,    "1",    "ª", },
            { "W",    "w",    "!",    "1",    _AA_,  _aa_,    "2",    "º", },
            { _E_,    _e_,    _at,    "2",    "Đ",    "đ",    "3",    "¡", },
            { "R",    "r",    "#",    "3",    _EE_,   _ee_,   "4",    "¿", },
            { "T",    "t",    "+",    _eq,    _OO_,   _oo_,   "5",    "¼", },
            { _Y_,    _y_,    "€",    "(",    _OW_,   _ow_,   "6",    "½", },
            { _U_,    _u_,    "‰",    ")",    _UW_,   _uw_,   "7",    "¾", },
            { _I_,    _i_,    "|",   "\\",    "Ā",    "ā",    "8",    "©", },
            { _O_,    _o_,    "?",    "/",    "Ī",    "ī",    "9",    "®", },
            { "P",    "p",    "~",    "`",    "Ū",    "ū",    "0",    "™", },
        },
        -- second row
        {  --  1       2       3       4       5       6       7       8
            { _A_,    _a_,    "…",    _at,    "Ñ",    "ñ",    "Ş",    "ş", },
            { "S",    "s",    "$",    "4",    "Ṇ",    "ṇ",    "İ",    "ı", },
            { "D",    "d",    "%",    "5",    "Ṃ",    "ṃ",    "Ğ",    "ğ", },
            { "F",    "f",    "^",    "6",    "Ṭ",    "ṭ",    "Ć",    "ć", },
            { "G",    "g",    ":",    ";",    "Ḍ",    "ḍ",    "Č",    "č", },
            { "H",    "h",    '"',    "'",    "Ḷ",    "ḷ",    "Đ",    "đ", },
            { "J",    "j",    "{",    "[",    "Ù",    "ù",    "Š",    "š", },
            { "K",    "k",    "}",    "]",    "Û",    "û",    "Ž",    "ž", },
            { "L",    "l",    "_",    "-",    "Ÿ",    "ÿ",    "Ő",    "ő", },
        },
        -- third row
        {  --  1       2       3       4       5       6       7       8
            { "",   "",   "2/2",  "1/2",   "",   "",   "",    "",
              width = 1.5
            },
            { "Z",    "z",    "&",    "7",    "Á",    "á",    "Ű",    "ű", },
            { "X",    "x",    "*",    "8",    "Ø",    "ø",    "Ã",    "ã", },
            { "C",    "c",    "£",    "9",    "Í",    "í",    "Þ",    "þ", },
            { "V",    "v",    "<",    com,    "Ñ",    "ñ",    "Ý",    "ý", },
            { "B",    "b",    ">",    prd,    "Ó",    "ó",    "†",    "‡", },
            { "N",    "n",    "‘",    "↑",    "Ú",    "ú",    "–",    "—", },
            { "M",    "m",    "’",    "↓",    "Ç",    "ç",    "…",    "¨", },
            { label = "",
              width = 1.5,
              bold = false
            },
        },
        -- fourth row
        {
            { "Sym",  "Sym",  "ABC",  "ABC",  "Sym",  "Sym",  "ABC",  "ABC",
              width = 1.5},
            { label = "🌐", },
            { "Äéß",  "Äéß",  "Äéß",  "Äéß",  "Äéß",  "Äéß",  "Äéß",  "Äéß", },
            { label = "space",
              " ",    " ",    " ",    " ",    " ",    " ",    " ",    " ",
              width = 3.0},
            { com,    com,    "“",    "←",    "Ũ",   "ũ",    com,    com, },
            { prd,    prd,    "”",    "→",    "Ĩ",   "ĩ",    prd,    prd, },
            { label = "⮠",
              "\n",   "\n",   "\n",   "\n",   "\n",   "\n",   "\n",   "\n",
              width = 1.5,
              bold = true
            },
        },
    },
}
