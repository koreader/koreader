local en_popup = require("ui/data/keyboardlayouts/keypopup/en_popup")
local com = en_popup.com -- comma (,)
local prd = en_popup.prd -- period (.)
local _at = en_popup._at
local _eq = en_popup._eq -- equals sign (=)
local _A_ = en_popup._A_
local _a_ = en_popup._a_
local _B_ = en_popup._B_
local _b_ = en_popup._b_
local _C_ = en_popup._C_
local _c_ = en_popup._c_
local _D_ = en_popup._D_
local _d_ = en_popup._d_
local _E_ = en_popup._E_
local _e_ = en_popup._e_
local _F_ = en_popup._F_
local _f_ = en_popup._f_
local _G_ = en_popup._G_
local _g_ = en_popup._g_
local _H_ = en_popup._H_
local _h_ = en_popup._h_
local _I_ = en_popup._I_
local _i_ = en_popup._i_
local _J_ = en_popup._J_
local _j_ = en_popup._j_
local _K_ = en_popup._K_
local _k_ = en_popup._k_
local _L_ = en_popup._L_
local _l_ = en_popup._l_
local _M_ = en_popup._M_
local _m_ = en_popup._m_
local _N_ = en_popup._N_
local _n_ = en_popup._n_
local _O_ = en_popup._O_
local _o_ = en_popup._o_
local _P_ = en_popup._P_
local _p_ = en_popup._p_
local _Q_ = en_popup._Q_
local _q_ = en_popup._q_
local _R_ = en_popup._R_
local _r_ = en_popup._r_
local _S_ = en_popup._S_
local _s_ = en_popup._s_
local _T_ = en_popup._T_
local _t_ = en_popup._t_
local _U_ = en_popup._U_
local _u_ = en_popup._u_
local _V_ = en_popup._V_
local _v_ = en_popup._v_
local _W_ = en_popup._W_
local _w_ = en_popup._w_
local _X_ = en_popup._X_
local _x_ = en_popup._x_
local _Y_ = en_popup._Y_
local _y_ = en_popup._y_
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
            { _Q_,        _q_,    "„",    "0",    "Й",    "й",    "?",    "!",    "Å",    "å",    "1",    "ª", },
            { _W_,        _w_,    "!",    "1",    "Ц",    "ц",    "(",    "1",    "Ä",    "ä",    "2",    "º", },
            { _E_,        _e_,    _at,    "2",    "У",    "у",    ")",    "2",    "Ö",    "ö",    "3",    "¡", },
            { _R_,        _r_,    "#",    "3",    "К",    "к",    "~",    "3",    "ß",    "ß",    "4",    "¿", },
            { _T_,        _t_,    "+",    _eq,    "Е",    "е",    "Ә",    "ә",    "À",    "à",    "5",    "¼", },
            { _Y_,        _y_,    "€",    "(",    "Н",    "н",    "І",    "і",    "Â",    "â",    "6",    "½", },
            { _U_,        _u_,    "‰",    ")",    "Г",    "г",    "Ң",    "ң",    "Æ",    "æ",    "7",    "¾", },
            { _I_,        _i_,    "|",   "\\",    "Ш",    "ш",    "Ғ",    "ғ",    "Ü",    "ü",    "8",    "©", },
            { _O_,        _o_,    "?",    "/",    "Щ",    "щ",    "Х",    "х",    "È",    "è",    "9",    "®", },
            { _P_,        _p_,    "~",    "`",    "З",    "з",    "Ъ",    "ъ",    "É",    "é",    "0",    "™", },
        },
        -- second row
        {  --  1           2       3       4       5       6       7       8       9       10      11      12
            { _A_,        _a_,    "…",    _at,    "Ф",    "ф",    "*",    "0",    "Ê",    "ê",    "Ş",    "ş", },
            { _S_,        _s_,    "$",    "4",    "Ы",    "ы",    "+",    "4",    "Ë",    "ë",    "İ",    "ı", },
            { _D_,        _d_,    "%",    "5",    "В",    "в",    "-",    "5",    "Î",    "î",    "Ğ",    "ğ", },
            { _F_,        _f_,    "^",    "6",    "А",    "а",    _eq,    "6",    "Ï",    "ï",    "Ć",    "ć", },
            { _G_,        _g_,    ":",    ";",    "П",    "п",    "Ү",    "ү",    "Ô",    "ô",    "Č",    "č", },
            { _H_,        _h_,    '"',    "'",    "Р",    "р",    "Ұ",    "ұ",    "Œ",    "œ",    "Đ",    "đ", },
            { _J_,        _j_,    "{",    "[",    "О",    "о",    "Қ",    "қ",    "Ù",    "ù",    "Š",    "š", },
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
            { _X_,        _x_,    "*",    "8",    "Ч",    "ч",    ";",    "8",    "Ø",    "ø",    "Ã",    "ã", },
            { _C_,        _c_,    "£",    "9",    "С",    "с",    "'",    "9",    "Í",    "í",    "Þ",    "þ", },
            { _V_,        _v_,    "<",    "‚",    "М",    "м",    "Ө",    "ө",    "Ñ",    "ñ",    "Ý",    "ý", },
            { _B_,        _b_,    ">",    prd,    "И",    "и",    "Һ",    "һ",    "Ó",    "ó",    "†",    "‡", },
            { _N_,        _n_,    "‘",    "↑",    "Т",    "т",    "Б",    "б",    "Ú",    "ú",    "–",    "—", },
            { _M_,        _m_,    "’",    "↓",    "Ь",    "ь",    "Ю",    "ю",    "Ç",    "ç",    "…",    "¨", },
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
