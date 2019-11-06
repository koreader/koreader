local en_popup = require("ui/data/keyboardlayouts/keypopup/en_popup")
local ar_popup = require("ui/data/keyboardlayouts/keypopup/ar_AA_popup")
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
local alef = ar_popup.alef
local baa = ar_popup.baa
local jeem = ar_popup.jeem
local daal = ar_popup.daal
local haa2 = ar_popup.haa2
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
local thaa = ar_popup.thaa
local ghayn = ar_popup.ghayn
local khaa = ar_popup.khaa
local alefmaqsoura = ar_popup.alefmaqsoura

return {
    shiftmode_keys = {["Shift"] = true},
    symbolmode_keys = {["Sym"] = true, ["ABC"] = true},
    utf8mode_keys = {["IM"] = true},
    umlautmode_keys = {["Äéß"] = true},
    keys = {
        -- first row
        {  --  1           2       3       4       5       6           7       8       9       10      11      12
            { _Q_,        _q_,    "„",    "0",    "׳",    dhad,        "?",    "!",    "Å",    "å",    "1",    "ª", },
            { _W_,        _w_,    "!",    "1",    "֘֘֙֙ ",    saad,        "(",    "1",    "Ä",    "ä",    "2",    "º", },
            { _E_,        _e_,    _at,    "2",    "֘ ",    thaa,      ")",    "2",    "Ö",    "ö",    "3",    "¡", },
            { _R_,        _r_,    "#",    "3",    "֗",    qaf,      "~",    "3",    "ß",    "ß",    "4",    "¿", },
            { _T_,        _t_,    "+",    _eq,    "֖ ",    fah,        "Ә",    "ә",    "À",    "à",    "5",    "¼", },
            { _Y_,        _y_,    "€",    "(",    "֕ ",    ghayn,        "І",    "і",    "Â",    "â",    "6",    "½", },
            { _U_,        _u_,    "‰",    ")",    "֔ ",    ayin,         "Ң",    "ң",    "Æ",    "æ",    "7",    "¾", },
            { _I_,        _i_,    "|",   "\\",    "֓ ",    ha,  "Ғ",    "ғ",    "Ü",    "ü",    "8",    "©", },
            { _O_,        _o_,    "?",    "/",    "֒ ",    khaa,       "Х",    "х",    "È",    "è",    "9",    "®", },
            { _P_,        _p_,    "~",    "`",    "֑ ",    ha, "Ъ",    "ъ",    "É",    "é",    "0",    "™", },
            { "[",        "[",    "",    "",    "֑",    jeem, "",    "",    "",    "",    "0",    "™", },
            { "]",        "]",    "’",    "↓",    "ֽ ",    daal,   "Ю",    "ю",    "Ç",    "ç",    "…",    "¨", },
        },
        -- second row
        {  --  1           2       3       4       5       6          7       8       9       10      11      12
            { _A_,        _a_,    "…",    _at,    "ּ ",    sheeb,      "*",    "0",    "Ê",    "ê",    "Ş",    "ş", },
            { _S_,        _s_,    "$",    "4",    "ֻ ",    seen,     "+",    "4",    "Ë",    "ë",    "İ",    "ı", },
            { _D_,        _d_,    "%",    "5",    "ִ ",    yaa,    "-",    "5",    "Î",    "î",    "Ğ",    "ğ", },
            { _F_,        _f_,    "^",    "6",    "ֹ",    baa,      _eq,    "6",    "Ï",    "ï",    "Ć",    "ć", },
            { _G_,        _g_,    ":",    ";",    "ְ ",    lam,      "Ү",    "ү",    "Ô",    "ô",    "Č",    "č", },
            { _H_,        _h_,    '"',    "'",    "ֵ ",    alef,        "Ұ",    "ұ",    "Œ",    "œ",    "Đ",    "đ", },
            { _J_,        _j_,    "{",    "[",    "ֶ ",    taa,       "Қ",    "қ",    "Ù",    "ù",    "Š",    "š", },
            { _K_,        _k_,    "}",    "]",    "ַ ",   nun,      "Ж",    "ж",    "Û",    "û",    "Ž",    "ž", },
            { _L_,        _l_,    "_",    "-",    "ָ ",    meem,       "Э",    "э",    "Ÿ",    "ÿ",    "Ő",    "ő", },
            { ";",        _l_,    "_",    "-",    "ָ ",    kaf,       "Э",    "э",    "Ÿ",    "ÿ",    "Ő",    "ő", },
            { "'",        _l_,    "_",    "-",    "ָ ",    tah,       "Э",    "э",    "Ÿ",    "ÿ",    "Ő",    "ő", },
        },
        -- third row
        {  --  1           2       3       4       5       6          7       8       9       10      11      12
            { label = "بَدِّل",
              icon = "resources/icons/appbar.arrow.shift.png",
              width = 1.5
            },
            { _Z_,        _z_,    "&",    "7",    "׃",    thaal,     ":",    "7",    "Á",    "á",    "Ű",    "ű", },
            { _X_,        _x_,    "*",    "8",    "׀",    hamza,    ";",    "8",    "Ø",    "ø",    "Ã",    "ã", },
            { _C_,        _c_,    "£",    "9",    "ׄ ",    wawhamza,      "'",    "9",    "Í",    "í",    "Þ",    "þ", },
            { _V_,        _v_,    "<",    com,    "ׅ ",    raa,       "Ө",    "ө",    "Ñ",    "ñ",    "Ý",    "ý", },
            { _B_,        _b_,    ">",    prd,    "־",    laa,       "Һ",    "һ",    "Ó",    "ó",    "†",    "‡", },
            { _N_,        _n_,    "‘",    "↑",    "ֿ ",    alefmaqsoura,      "Б",    "б",    "Ú",    "ú",    "–",    "—", },
            { _M_,        _m_,    "’",    "↓",    "ֽ ",    taamarbouta,   "Ю",    "ю",    "Ç",    "ç",    "…",    "¨", },
            { ",",        ",",    "’",    "↓",    "ֽ ",    waw,   "Ю",    "ю",    "Ç",    "ç",    "…",    "¨", },
            { ".",        ".",    "’",    "↓",    "ֽ ",    zay,   "Ю",    "ю",    "Ç",    "ç",    "…",    "¨", },
            { "/",        "/",    "’",    "↓",    "ֽ ",    thaa,   "Ю",    "ю",    "Ç",    "ç",    "…",    "¨", },
            { label = "مَسح",
              icon = "resources/icons/appbar.clear.reflect.horizontal.png",
              width = 1.5
            },
        },
        -- fourth row
        {
            { "Sym",     "Sym",  "ABC",  "ABC",  "Sym",  "رمز",    "رمز",  "رمز",  "Sym",  "Sym",  "ABC",  "ABC",
              width = 1.5},
            { label = "IM",
              icon = "resources/icons/appbar.globe.wire.png",
            },
            { "Äéß",     "Äéß",  "Äéß",  "Äéß",  "Äéß",  "Äéß",    "Äéß",  "Äéß",  "Äéß",  "Äéß",  "Äéß",  "Äéß", },
            { label = "space",
              " ",        " ",    " ",    " ",    " ",    " ",      " ",    " ",    " ",    " ",    " ",    " ",
              width = 3.0},
            { com,        com,    "“",    "←",    com,    taf,      "Ё",    "ё",    "Ũ",   "ũ",    com,    com, },
            { prd,        prd,    "”",    "→",    prd,    "ץ",      prd,    prd,    "Ĩ",   "ĩ",    prd,    prd, },
            { label = "أدخل",
              "\n",       "\n",   "\n",   "\n",   "\n",   "\n",    "\n",   "\n",   "\n",   "\n",   "\n",   "\n",
              icon = "resources/icons/appbar.arrow.enter.png",
              width = 1.5,
            },
        },
    },
}
