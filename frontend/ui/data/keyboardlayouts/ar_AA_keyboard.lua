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
    max_layer = 4,
    shiftmode_keys = {["Shift"] = true, ["حرف"] = true, ["رمز"]=true},
    symbolmode_keys = {["Sym"] = true},
    utf8mode_keys = {["🌐"] = true},
    umlautmode_keys = {["Äéß"] = false},
    keys = {
        -- first row
        {  --  1        2       3       4
            { _Q_,    dhad,    "׳",    "0", },
            { _W_,    saad,    "֘֘֙֙ ",    "1", },
            { _E_,    thaa,    "֘ ",    "2", },
            { _R_,    qaf,     "֗",     "3", },
            { _T_,    fah,     "֖ ",    _eq, },
            { _Y_,    ghayn,   "֕ ",    "(", },
            { _U_,    ayin,    "֔ ",    ")", },
            { _I_,    h_aa,    "֓ ",    "ـ", },
            {  _O_,    khaa,    "֒ ",    "ّ", },
            {  _P_,    ha,      "֑ ",    "ٌ", },
            {  "[",    jeem,    "֑",     "ً", },
            {  "]",   daal,    "ֽ ",    "~", },
        },
        -- second row
        {  --  1         2       3       4
            { "",     sheen,    "ּ ",    "4", },
            { _S_,     seen,     "ֻ ",   "5", },
            { _D_,      yaa,     "ִ ",   "6", },
            { _F_,       ba,     "ֹ",    ";", },
            { _G_,      lam,     "ְ ",   "'", },
            { _H_,     alef,     "ֵ ",  "\\", },
            { _J_,      taa,     "ֶ ",    "ّ", },
            { _K_,      nun,     "ַ ",    "ْ", },
            { _L_,     meem,     "ָ ",    "ِ", },
            { ";",      kaf,     "ָ ",    "ُ", },
            { "'",      tah,     "ָ ",    "َ", },
        },
        -- third row
        {  --  1              2            3       4
            { _Z_,          thaal,        "׃",    "7", },
            { hamza,        hamza,        "׀",    "8", },
            { wawhamza,     wawhamza,     "ׄ ",    "9", },
            { raa,          raa,          "ׅ ",    com, },
            { laa,          laa,          "־",    prd, },
            { alefmaqsoura, alefmaqsoura, "ֿ ",    "[", },
            { taamarbouta,  taamarbouta,  "ֽ ",    "]", },
            { waw,          waw,          "ֽ ",    "↑", },
            { zay,          zay,          "ֽ ",    "↓", },
            { thaa,         thaa,         "ֽ ",    _at, },
            { label = "Backspace",
              icon = "resources/icons/appbar.clear.reflect.horizontal.png",
              width = 1.5
            },
        },
        -- fourth row
        {
            { "Shift",     "رمز",  "حرف",  "حرف",
              width = 1},
            { label = "🌐", },
            { "Sym",     "Sym",  "Sym",  "Sym", },
            { label = "space",
              " ",        " ",    " ",    " ",
              width = 3.0},
            { com,        arabic_comma,    "“",    "←", },
            { prd,        prd,    "”",    "→", },
            --- @fixme Diacritics should only be needed in the first layout, but one repeat of 'diacritics' won't work. Kindly see https://github.com/koreader/koreader/pull/5569#issuecomment-554114059 for details.
            { label =  "َ ُ ِ",        diacritics,    diacritics,    diacritics, },
            { label = "Enter",
              "\n",       "\n",   "\n",   "\n",
              icon = "resources/icons/appbar.arrow.enter.png",
              width = 1.5,
            },

    },
}
}
