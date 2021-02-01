local en_popup = require("ui/data/keyboardlayouts/keypopup/en_popup")
local ka_popup = require("ui/data/keyboardlayouts/keypopup/ka_popup")
local com = en_popup.com -- comma (,)
local prd = en_popup.prd -- period (.)
local _at = en_popup._at
local _eq = en_popup._eq -- equals sign (=)
local _A_ = en_popup._A_
local _a_ = ka_popup._a_
local _B_ = en_popup._B_
local _b_ = ka_popup._b_
local _C_ = ka_popup._C_
local _c_ = ka_popup._c_
local _D_ = en_popup._D_
local _d_ = ka_popup._d_
local _E_ = en_popup._E_
local _e_ = ka_popup._e_
local _F_ = en_popup._F_
local _f_ = ka_popup._f_
local _G_ = en_popup._G_
local _g_ = ka_popup._g_
local _H_ = en_popup._H_
local _h_ = ka_popup._h_
local _I_ = en_popup._I_
local _i_ = ka_popup._i_
local _J_ = ka_popup._J_
local _j_ = ka_popup._j_
local _K_ = en_popup._K_
local _k_ = ka_popup._k_
local _L_ = en_popup._L_
local _l_ = ka_popup._l_
local _M_ = en_popup._M_
local _m_ = ka_popup._m_
local _N_ = en_popup._N_
local _n_ = ka_popup._n_
local _O_ = en_popup._O_
local _o_ = ka_popup._o_
local _P_ = en_popup._P_
local _p_ = ka_popup._p_
local _Q_ = en_popup._Q_
local _q_ = ka_popup._q_
local _R_ = ka_popup._R_
local _r_ = ka_popup._r_
local _S_ = ka_popup._S_
local _s_ = ka_popup._s_
local _T_ = ka_popup._T_
local _t_ = ka_popup._t_
local _U_ = en_popup._U_
local _u_ = ka_popup._u_
local _V_ = en_popup._V_
local _v_ = ka_popup._v_
local _W_ = ka_popup._W_
local _w_ = ka_popup._w_
local _X_ = en_popup._X_
local _x_ = ka_popup._x_
local _Y_ = en_popup._Y_
local _y_ = ka_popup._y_
local _Z_ = ka_popup._Z_
local _z_ = ka_popup._z_

return {
    min_layer = 1,
    max_layer = 8,
    shiftmode_keys = {[""] = true, ["1/2"] = true, ["2/2"] = true,},
    symbolmode_keys = {["123"] = true, ["აბგ"] = true},
    utf8mode_keys = {["🌐"] = true},
    umlautmode_keys = {["Äéß"] = true},
    keys = {
        -- first row
        {  --  1       2       3       4       5       6       7       8
            { _Q_,    _q_,    "„",    "0",    "Å",    "å",    "1",    "ª", },
            { _W_,    _w_,    "!",    "1",    "Ä",    "ä",    "2",    "º", },
            { _E_,    _e_,    _at,    "2",    "Ö",    "ö",    "3",    "¡", },
            { _R_,    _r_,    "#",    "3",    "ß",    "ß",    "4",    "¿", },
            { _T_,    _t_,    "+",    _eq,    "À",    "à",    "5",    "¼", },
            { _Y_,    _y_,    "€",    "(",    "Â",    "â",    "6",    "½", },
            { _U_,    _u_,    "‰",    ")",    "Æ",    "æ",    "7",    "¾", },
            { _I_,    _i_,    "|",   "\\",    "Ü",    "ü",    "8",    "©", },
            { _O_,    _o_,    "?",    "/",    "È",    "è",    "9",    "®", },
            { _P_,    _p_,    "~",    "`",    "É",    "é",    "0",    "™", },
        },
        -- second row
        {  --  1       2       3       4       5       6       7       8
            { _A_,    _a_,    "…",    _at,    "Ê",    "ê",    "Ş",    "ş", },
            { _S_,    _s_,    "$",    "4",    "Ë",    "ë",    "İ",    "ı", },
            { _D_,    _d_,    "%",    "5",    "Î",    "î",    "Ğ",    "ğ", },
            { _F_,    _f_,    "^",    "6",    "Ï",    "ï",    "Ć",    "ć", },
            { _G_,    _g_,    ":",    ";",    "Ô",    "ô",    "Č",    "č", },
            { _H_,    _h_,    '"',    "'",    "Œ",    "œ",    "Đ",    "đ", },
            { _J_,    _j_,    "{",    "[",    "Ù",    "ù",    "Š",    "š", },
            { _K_,    _k_,    "}",    "]",    "Û",    "û",    "Ž",    "ž", },
            { _L_,    _l_,    "_",    "-",    "Ÿ",    "ÿ",    "Ő",    "ő", },
        },
        -- third row
        {  --  1       2       3       4       5       6       7       8
            { "",   "",   "2/2",  "1/2",   "",   "",   "",    "",
              width = 1.5
            },
            { _Z_,    _z_,    "&",    "7",    "Á",    "á",    "Ű",    "ű", },
            { _X_,    _x_,    "*",    "8",    "Ø",    "ø",    "Ã",    "ã", },
            { _C_,    _c_,    "£",    "9",    "Í",    "í",    "Þ",    "þ", },
            { _V_,    _v_,    "<",    com,    "Ñ",    "ñ",    "Ý",    "ý", },
            { _B_,    _b_,    ">",    prd,    "Ó",    "ó",    "†",    "‡", },
            { _N_,    _n_,    "‘",    "↑",    "Ú",    "ú",    "–",    "—", },
            { _M_,    _m_,    "’",    "↓",    "Ç",    "ç",    "…",    "¨", },
            { label = "",
              width = 1.5,
              bold = false
            },
        },
        -- fourth row
        {
            { "123",  "123",  "აბგ",  "აბგ",  "123",  "123",  "აბგ",  "აბგ",
              width = 1.5},
            { label = "🌐", },
            { "Äéß",  "Äéß",  "Äéß",  "Äéß",  "Äéß",  "Äéß",  "Äéß",  "Äéß", },
            { label = "გამოტოვება",
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
