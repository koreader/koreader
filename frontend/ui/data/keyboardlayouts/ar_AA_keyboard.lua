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
--local diacritic_fat_ha = ar_popup.diacritic_fat_ha
--local diacritic_damma = ar_popup.diacritic_damma
--local diacritic_kasra = ar_popup.diacritic_kasra
--local diacritic_sukoon = ar_popup.diacritic_sukoon
--local diacritic_shadda = ar_popup.diacritic_shadda
--local diacritic_tanween_fath = ar_popup.diacritic_tanween_fath
--local diacritic_tanween_damm = ar_popup.diacritic_tanween_damm
--local diacritic_tanween_kasr = ar_popup.diacritic_tanween_kasr
local arabic_comma = ar_popup.arabic_comma


return {
    min_layer = 1,
    max_layer = 12,
    shiftmode_keys = {["Shift"] = false},
    symbolmode_keys = {["Sym"] = true, ["حرف"] = true, ["رمز"]=true},
    utf8mode_keys = {["IM"] = true},
    umlautmode_keys = {["Äéß"] = true},
    keys = {
        -- first row
        {  --  1           2       3       4       5       6           7       8       9       10      11      12
            { dhad,       dhad,    "„",    "0",    "׳",    _Q_,        "?",    "!",    "Å",    "å",    "1",    "ª", },
            { saad,       saad,    "!",    "1",    "֘֘֙֙ ",    _W_,        "(",    "1",    "Ä",    "ä",    "2",    "º", },
            { thaa,       thaa,    _at,    "2",    "֘ ",    _E_,      ")",    "2",    "Ö",    "ö",    "3",    "¡", },
            { qaf,        qaf,    "#",    "3",    "֗",     _R_,      "~",    "3",    "ß",    "ß",    "4",    "¿", },
            { fah,        fah,    "+",    _eq,    "֖ ",    _T_,        "Ә",    "ә",    "À",    "à",    "5",    "¼", },
            { ghayn,      ghayn,    "€",    "(",    "֕ ",    _Y_,        "І",    "і",    "Â",    "â",    "6",    "½", },
            { ayin,       ayin,    "‰",    ")",    "֔ ",    _U_,         "Ң",    "ң",    "Æ",    "æ",    "7",    "¾", },
            { h_aa,       h_aa,    "|",   "ـ",    "֓ ",    _I_,  "Ғ",    "ғ",    "Ü",    "ü",    "8",    "©", },
            { khaa,       khaa,    "?",    "ّ",    "֒ ",    _O_,       "Х",    "х",    "È",    "è",    "9",    "®", },
            { ha,         ha,    "~",    "ٌ",    "֑ ",    _P_, "Ъ",    "ъ",    "É",    "é",    "0",    "™", },
            { jeem,       jeem,    "",     "ً",     "֑",     "[", "",    "",    "",    "",    "0",    "™", },
            { daal,       daal,    "’",    "~",    "ֽ ",    "]",   "Ю",    "ю",    "Ç",    "ç",    "…",    "¨", },
        },
        -- second row
        {  --  1           2       3       4       5       6          7       8       9       10      11      12
            { "",        sheen,    "…",    "4",    "ּ ",    nil,      "*",    "0",    "Ê",    "ê",    "Ş",    "ş", },
            { "",        seen,    "$",    "5",    "ֻ ",    _S_,     "+",    "4",    "Ë",    "ë",    "İ",    "ı", },
            { "",        yaa,    "%",    "6",    "ִ ",    _D_,    "-",    "5",    "Î",    "î",    "Ğ",    "ğ", },
            { "",        ba,    "^",    ";",    "ֹ",     _F_,      _eq,    "6",    "Ï",    "ï",    "Ć",    "ć", },
            { "",        lam,    ":",    "'",    "ְ ",    _G_,      "Ү",    "ү",    "Ô",    "ô",    "Č",    "č", },
            { "",        alef,    '"',    "\\",    "ֵ ",    _H_,        "Ұ",    "ұ",    "Œ",    "œ",    "Đ",    "đ", },
            { "",        taa,    "{",    "ّ",    "ֶ ",    _J_,       "Қ",    "қ",    "Ù",    "ù",    "Š",    "š", },
            { "",        nun,    "}",    "ْ",    "ַ ",    _K_,      "Ж",    "ж",    "Û",    "û",    "Ž",    "ž", },
            { "",        meem,    "_",   "ِ",    "ָ ",    _L_,       "Э",    "э",    "Ÿ",    "ÿ",    "Ő",    "ő", },
            { "",        kaf,    "_",    "ُ",    "ָ ",    ";",       "Э",    "э",    "Ÿ",    "ÿ",    "Ő",    "ő", },
            { "",        tah,    "_",    "َ",    "ָ ",    "'",       "Э",    "э",    "Ÿ",    "ÿ",    "Ő",    "ő", },
        },
        -- third row
        {  --  1           2       3       4       5       6          7       8       9       10      11      12
            { "",        thaal,    "&",    "7",    "׃",    _Z_,     ":",    "7",    "Á",    "á",    "Ű",    "ű", },
            { "",        hamza,    "*",    "8",    "׀",    hamza,    ";",    "8",    "Ø",    "ø",    "Ã",    "ã", },
            { "",        wawhamza,    "£",    "9",    "ׄ ",    wawhamza,      "'",    "9",    "Í",    "í",    "Þ",    "þ", },
            { "",        raa,    "<",    com,    "ׅ ",    raa,       "Ө",    "ө",    "Ñ",    "ñ",    "Ý",    "ý", },
            { "",        laa,    ">",    prd,    "־",    laa,       "Һ",    "һ",    "Ó",    "ó",    "†",    "‡", },
            { "",        alefmaqsoura,    "‘",    "[",    "ֿ ",    alefmaqsoura,      "Б",    "б",    "Ú",    "ú",    "–",    "—", },
            { "",        taamarbouta,    "’",    "]",    "ֽ ",    taamarbouta,   "Ю",    "ю",    "Ç",    "ç",    "…",    "¨", },
            { "",        waw,    "’",    "↑",    "ֽ ",    waw,   "Ю",    "ю",    "Ç",    "ç",    "…",    "¨", },
            { "",        zay,    "’",    "↓",    "ֽ ",    zay,   "Ю",    "ю",    "Ç",    "ç",    "…",    "¨", },
            { "",        thaa,    "’",    _at,    "ֽ ",    thaa,   "Ю",    "ю",    "Ç",    "ç",    "…",    "¨", },
            { label = "Backspace",
              icon = "resources/icons/appbar.clear.reflect.horizontal.png",
              width = 1.5
            },
        },
        -- fourth row
        {
            { "Sym",     "رمز",  "حرف",  "حرف",  "Sym",  "رمز",    "رمز",  "رمز",  "Sym",  "Sym",  "ABC",  "ABC",
              width = 1},
            { label = "IM",
              icon = "resources/icons/appbar.globe.wire.png",
            },
            { "Äéß",     "Äéß",  "Äéß",  "Äéß",  "Äéß",  "Äéß",    "Äéß",  "Äéß",  "Äéß",  "Äéß",  "Äéß",  "Äéß", },
            { label = "space",
              " ",        " ",    " ",    " ",    " ",    " ",      " ",    " ",    " ",    " ",    " ",    " ",
              width = 3.0},
            { com,        arabic_comma,    "“",    "←",    com,    arabic_comma,      "Ё",    "ё",    "Ũ",   "ũ",    com,    com, },
            { prd,        prd,    "”",    "→",    prd,    prd,      prd,    prd,    "Ĩ",   "ĩ",    prd,    prd, },
            -- @fixme Diacritics should only be needed in the first layout, but one repeat of 'diacritics' won't work. Kindly see https://github.com/koreader/koreader/pull/5569#issuecomment-554114059 for details.
            { label =  "َ ُ ِ",        diacritics,    diacritics,    diacritics,    diacritics,    diacritics,      diacritics,    diacritics,    diacritics,   diacritics,    diacritics,    diacritics, },
            { label = "Enter",
              "\n",       "\n",   "\n",   "\n",   "\n",   "\n",    "\n",   "\n",   "\n",   "\n",   "\n",   "\n",
              icon = "resources/icons/appbar.arrow.enter.png",
              width = 1.5,
            },

    },
}
}
