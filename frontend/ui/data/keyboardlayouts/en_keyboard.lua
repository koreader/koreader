local en_popup = require("ui/data/keyboardlayouts/keypopup/en_popup")
local com = en_popup.com -- comma (,)
local prd = en_popup.prd -- period (.)
local _at = en_popup._at
local _A_ = en_popup._A_
local _a_ = en_popup._a_
local _B_ = en_popup._B_
local _b_ = en_popup._b_
local _C_ = en_popup._C_
local _c_ = en_popup._c_
local _E_ = en_popup._E_
local _e_ = en_popup._e_
local _D_ = en_popup._D_
local _d_ = en_popup._d_
local _I_ = en_popup._I_
local _i_ = en_popup._i_
local _K_ = en_popup._K_
local _k_ = en_popup._k_
local _L_ = en_popup._L_
local _l_ = en_popup._l_
local _O_ = en_popup._O_
local _o_ = en_popup._o_
local _S_ = en_popup._S_
local _s_ = en_popup._s_
local _T_ = en_popup._T_
local _t_ = en_popup._t_
local _U_ = en_popup._U_
local _u_ = en_popup._u_
local _Z_ = en_popup._Z_
local _z_ = en_popup._z_

return {
    shiftmode_keys = {["Shift"] = true},
    symbolmode_keys = {["Sym"] = true, ["ABC"] = true},
    utf8mode_keys = {["IM"] = true},
    umlautmode_keys = {["Äéß"] = true},
    keys = {
        -- first row
        {  --  1           2       3       4       5       6       7       8       9       10      11      12
            { "Q",        "q",    "„",    "0",    "Й",    "й",    "?",    "!",    "Å",    "å",    "1",    "ª", },
            { "W",        "w",    "!",    "1",    "Ц",    "ц",    "(",    "1",    "Ä",    "ä",    "2",    "º", },
            { _E_,        _e_,    _at,    "2",    "У",    "у",    ")",    "2",    "Ö",    "ö",    "3",    "¡", },
            { "R",        "r",    "#",    "3",    "К",    "к",    "~",    "3",    "ß",    "ß",    "4",    "¿", },
            { _T_,        _t_,    "+",    "=",    "Е",    "е",    "Ә",    "ә",    "À",    "à",    "5",    "¼", },
            { "Y",        "y",    "€",    "(",    "Н",    "н",    "І",    "і",    "Â",    "â",    "6",    "½", },
            { _U_,        _u_,    "‰",    ")",    "Г",    "г",    "Ң",    "ң",    "Æ",    "æ",    "7",    "¾", },
            { _I_,        _i_,    "|",   "\\",    "Ш",    "ш",    "Ғ",    "ғ",    "Ü",    "ü",    "8",    "©", },
            { _O_,        _o_,    "?",    "/",    "Щ",    "щ",    "Х",    "х",    "È",    "è",    "9",    "®", },
            { "P",        "p",    "~",    "`",    "З",    "з",    "Ъ",    "ъ",    "É",    "é",    "0",    "™", },
        },
        -- second row
        {  --  1           2       3       4       5       6       7       8       9       10      11      12
            { _A_,        _a_,    "…",    _at,    "Ф",    "ф",    "*",    "0",    "Ê",    "ê",    "Ş",    "ş", },
            { _S_,        _s_,    "$",    "4",    "Ы",    "ы",    "+",    "4",    "Ë",    "ë",    "İ",    "ı", },
            { _D_,        _d_,    "%",    "5",    "В",    "в",    "-",    "5",    "Î",    "î",    "Ğ",    "ğ", },
            { "F",        "f",    "^",    "6",    "А",    "а",    "=",    "6",    "Ï",    "ï",    "Ć",    "ć", },
            { "G",        "g",    ":",    ";",    "П",    "п",    "Ү",    "ү",    "Ô",    "ô",    "Č",    "č", },
            { "H",        "h",    "\"",   "'",    "Р",    "р",    "Ұ",    "ұ",    "Œ",    "œ",    "Đ",    "đ", },
            { "J",        "j",    "{",    "[",    "О",    "о",    "Қ",    "қ",    "Ù",    "ù",    "Š",    "š", },
            { _K_,        _k_,    "}",    "]",   "Л",    "л",    "Ж",    "ж",    "Û",    "û",    "Ž",    "ž", },
            { _L_,        _l_,    "_",    "-",    "Д",    "д",    "Э",    "э",    "Ÿ",    "ÿ",    "Ő",    "ő", },
        },
        -- third row
        {  --  1           2       3       4       5       6       7       8       9       10      11      12
            { label = "Shift",
              icon = "resources/icons/appbar.arrow.shift.png",
              width = 1.5
            },
            { _Z_,        _z_,    "&",    "7",    "Я",    "я",    ":",    "7",    "Á",    "á",    "Ű",    "ű", },
            { "X",        "x",    "*",    "8",    "Ч",    "ч",    ";",    "8",    "Ø",    "ø",    "Ã",    "ã", },
            { _C_,        _c_,    "£",    "9",    "С",    "с",    "'",    "9",    "Í",    "í",    "Þ",    "þ", },
            { "V",        "v",    "<",    "‚",    "М",    "м",    "Ө",    "ө",    "Ñ",    "ñ",    "Ý",    "ý", },
            { _B_,        _b_,    ">",    prd,    "И",    "и",    "Һ",    "һ",    "Ó",    "ó",    "†",    "‡", },
            { "N",        "n",    "‘",    "↑",    "Т",    "т",    "Б",    "б",    "Ú",    "ú",    "–",    "—", },
            { "M",        "m",    "’",    "↓",    "Ь",    "ь",    "Ю",    "ю",    "Ç",    "ç",    "…",    "¨", },
            { label = "Backspace",
              icon = "resources/icons/appbar.clear.reflect.horizontal.png",
              width = 1.5
            },
        },
        -- fourth row
        {
            { "Sym",     "Sym",  "ABC",  "ABC",  "Sym",  "Sym",  "ABC",  "ABC",  "Sym",  "Sym",  "ABC",  "ABC",
              width = 1.5},
            { label = "IM",
              icon = "resources/icons/appbar.globe.wire.png",
            },
            { "Äéß",     "Äéß",  "Äéß",  "Äéß",  "Äéß",  "Äéß",  "Äéß",  "Äéß",  "Äéß",  "Äéß",  "Äéß",  "Äéß", },
            { label = "space",
              " ",        " ",    " ",    " ",    " ",    " ",    " ",    " ",    " ",    " ",    " ",    " ",
              width = 3.0},
            { com,        com,    "“",    "←",    com,    com,    "Ё",    "ё",    "Ũ",   "ũ",    com,    com, },
            { prd,        prd,    "”",    "→",    prd,    prd,    prd,    prd,    "Ĩ",   "ĩ",    prd,    prd, },
            { label = "Enter",
              "\n",       "\n",   "\n",   "\n",   "\n",   "\n",   "\n",   "\n",   "\n",   "\n",   "\n",   "\n",
              icon = "resources/icons/appbar.arrow.enter.png",
              width = 1.5,
            },
        },
    },
}
