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

local el_popup = require("ui/data/keyboardlayouts/keypopup/el_popup")
local _A_el = el_popup._A_el
local _a_el = el_popup._a_el
local _B_el = el_popup._B_el
local _b_el = el_popup._b_el
local _C_el = el_popup._C_el
local _c_el = el_popup._c_el
local _D_el = el_popup._D_el
local _d_el = el_popup._d_el
local _E_el = el_popup._E_el
local _e_el = el_popup._e_el
local _F_el = el_popup._F_el
local _f_el = el_popup._f_el
local _G_el = el_popup._G_el
local _g_el = el_popup._g_el
local _H_el = el_popup._H_el
local _h_el = el_popup._h_el
local _I_el = el_popup._I_el
local _i_el = el_popup._i_el
local _J_el = el_popup._J_el
local _j_el = el_popup._j_el
local _K_el = el_popup._K_el
local _k_el = el_popup._k_el
local _L_el = el_popup._L_el
local _l_el = el_popup._l_el
local _M_el = el_popup._M_el
local _m_el = el_popup._m_el
local _N_el = el_popup._N_el
local _n_el = el_popup._n_el
local _O_el = el_popup._O_el
local _o_el = el_popup._o_el
local _P_el = el_popup._P_el
local _p_el = el_popup._p_el
--local _Q_el = el_popup._Q_el
--local _q_el = el_popup._q_el
local _R_el = el_popup._R_el
local _r_el = el_popup._r_el
local _S_el = el_popup._S_el
local _s_el = el_popup._s_el
local _T_el = el_popup._T_el
local _t_el = el_popup._t_el
local _U_el = el_popup._U_el
local _u_el = el_popup._u_el
local _V_el = el_popup._V_el
local _v_el = el_popup._v_el
--local _W_el = el_popup._W_el
--local _w_el = el_popup._w_el
local _X_el = el_popup._X_el
local _x_el = el_popup._x_el
local _Y_el = el_popup._Y_el
local _y_el = el_popup._y_el
local _Z_el = el_popup._Z_el
local _z_el = el_popup._z_el

return {
    shiftmode_keys = {["Shift"] = true},
    symbolmode_keys = {["Sym"] = true, ["ABC"] = true},
    utf8mode_keys = {["IM"] = true},
    umlautmode_keys = {["Äéß"] = true},
    keys = {
        -- first row
        {  --  1       2       3       4       5       6       7       8       9       10      11      12
            { ":",    ";",    "„",    "0",    _Q_,    _q_,    "1",    "!",    "Ä",    "ä",    "1",    "ª", },
            { "|",    "ς",    "!",    "1",    _W_,    _w_,    "2",    "?",    "Ö",    "ö",    "2",    "º", },
            { _E_el,  _e_el,  _at,    "2",    _E_,    _e_,    "Έ",    "έ",    "Ü",    "ü",    "3",    "¡", },
            { _R_el,  _r_el,  "#",    "3",    _R_,    _r_,    "4",    ";",    "ß",    "ß",    "4",    "¿", },
            { _T_el,  _t_el,  "+",    _eq,    _T_,    _t_,    "5",    ":",    "À",    "à",    "5",    "¼", },
            { _Y_el,  _y_el,  "€",    "(",    _Y_,    _y_,    "Ύ",    "ύ",    "Â",    "â",    "6",    "½", },
            { _U_el,  _u_el,  "‰",    ")",    _U_,    _u_,    "7",    "(",    "Æ",    "æ",    "7",    "¾", },
            { _I_el,  _i_el,  "|",    "\\",   _I_,    _i_,    "Ί",    "ί",    "Ç",    "ç",    "8",    "©", },
            { _O_el,  _o_el,  "?",    "/",    _O_,    _o_,    "9",    "ό",    "È",    "è",    "9",    "®", },
            { _P_el,  _p_el,  "~",    "`",    _P_,    _p_,    "Ό",    ")",    "É",    "é",    "0",    "™", },
        },
        -- second row
        {  --  1       2       3       4       5       6       7       8       9       10      11      12
            { _A_el,  _a_el,  "…",    _at,    _A_,    _a_,    "Ά",    "ά",    "Ê",    "ê",    "Ş",    "ş", },
            { _S_el,  _s_el,  "$",    "4",    _S_,    _s_,    "Ѕ",    "ѕ",    "Ë",    "ë",    "İ",    "ı", },
            { _D_el,  _d_el,  "%",    "5",    _D_,    _d_,    "Э",    "«",    "Î",    "î",    "Ğ",    "ğ", },
            { _F_el,  _f_el,  "^",    "6",    _F_,    _f_,    _eq,    "»",    "Ï",    "ï",    "Ć",    "ć", },
            { _G_el,  _g_el,  ":",    ";",    _G_,    _g_,    "Ґ",    "ґ",    "Ô",    "ô",    "Č",    "č", },
            { _H_el,  _h_el,  '"',    "'",    _H_,    _h_,    "Ή",    "ή",    "Œ",    "œ",    "Đ",    "đ", },
            { _J_el,  _j_el,  "{",    "[",    _J_,    _j_,    "Ί",    "ί",    "Ù",    "ù",    "Š",    "š", },
            { _K_el,  _k_el,  "}",    "]",    _K_,    _k_,    "Ќ",    "ќ",    "Û",    "û",    "Ž",    "ž", },
            { _L_el,  _l_el,  "_",    "-",    _L_,    _l_,    "Љ",    "љ",    "Ÿ",    "ÿ",    "Ő",    "ő", },
        },
        -- third row
        {  --  1       2       3       4       5       6       7       8       9       10      11      12
            { label = "Shift",
              icon = "resources/icons/appbar.arrow.shift.png",
              width = 1.5
            },
            { _Z_el,  _z_el,  "&",    "7",    _Z_,    _z_,    "Щ",    "щ",    "Á",    "á",    "Ű",    "ű", },
            { _X_el,  _x_el,  "*",    "8",    _X_,    _x_,    "№",    "@",    "É",    "é",    "Ø",    "ø", },
            { _C_el,  _c_el,  "£",    "9",    _C_,    _c_,    "Џ",    "џ",    "Í",    "í",    "Þ",    "þ", },
            { _V_el,  _v_el,  "<",    com,    _V_,    _v_,    "Ώ",    "ώ",    "Ñ",    "ñ",    "Ý",    "ý", },
            { _B_el,  _b_el,  ">",    prd,    _B_,    _b_,    "Ћ",    "ћ",    "Ó",    "ó",    "†",    "‡", },
            { _N_el,  _n_el,  "‘",    "↑",    _N_,    _n_,    "Њ",    "њ",    "Ú",    "ú",    "–",    "—", },
            { _M_el,  _m_el,  "’",    "↓",    _M_,    _m_,    "Ї",    "ї",    "Ç",    "ç",    "…",    "¨", },
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
