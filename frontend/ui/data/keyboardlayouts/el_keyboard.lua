local en_popup = require("ui/data/keyboardlayouts/keypopup/en_popup")
local com = en_popup.com -- comma (,)
local prd = en_popup.prd -- period (.)
local _at = en_popup._at
local _eq = en_popup._eq -- equals sign (=)

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
    min_layer = 1,
    max_layer = 8,
    shiftmode_keys = {[""] = true},
    symbolmode_keys = {["Sym"] = true, ["ABC"] = true},
    utf8mode_keys = {["🌐"] = true},
    umlautmode_keys = {["Äéß"] = true},
    keys = {
        -- first row
        {  --  1       2       3       4       5       6       7       8
            { ":",    ";",    "„",    "0",    "Ä",    "ᾷ",    "1",    "ª", },
            { "|",    "ς",    "!",    "1",    "Ö",    "ᾇ",    "2",    "º", },
            { _E_el,  _e_el,  _at,    "2",    "Έ",    "έ",    "3",    "¡", },
            { _R_el,  _r_el,  "#",    "3",    "ß",    "ß",    "4",    "¿", },
            { _T_el,  _t_el,  "+",    _eq,    "À",    "ὒ",    "5",    "¼", },
            { _Y_el,  _y_el,  "€",    "(",    "Ύ",    "ύ",    "6",    "½", },
            { _U_el,  _u_el,  "‰",    ")",    "Æ",    "ὓ",    "7",    "¾", },
            { _I_el,  _i_el,  "|",    "\\",   "Ί",    "ί",    "8",    "©", },
            { _O_el,  _o_el,  "?",    "/",    "Ό",    "ό",    "9",    "®", },
            { _P_el,  _p_el,  "~",    "`",    "É",    "é",    "0",    "™", },
        },
        -- second row
        {  --  1       2       3       4       5       6       7       8
            { _A_el,  _a_el,  "…",    _at,    "Ά",    "ά",    "Ş",    "ş", },
            { _S_el,  _s_el,  "$",    "4",    "ᾏ",    "ᾆ",    "İ",    "ı", },
            { _D_el,  _d_el,  "%",    "5",    "Ἃ",    "ἃ",    "Ğ",    "ğ", },
            { _F_el,  _f_el,  "^",    "6",    "Ï",    "ï",    "Ć",    "ć", },
            { _G_el,  _g_el,  ":",    ";",    "Ô",    "ῇ",    "Č",    "č", },
            { _H_el,  _h_el,  '"',    "'",    "Ή",    "ή",    "Đ",    "đ", },
            { _J_el,  _j_el,  "{",    "[",    "Ί",    "ί",    "Š",    "š", },
            { _K_el,  _k_el,  "}",    "]",    "Û",    "ὖ",    "Ž",    "ž", },
            { _L_el,  _l_el,  "_",    "-",    "Ÿ",    "ὗ",    "Ő",    "ő", },
        },
        -- third row
        {  --  1       2       3       4       5       6       7       8
            { label = "",
              width = 1.5
            },
            { _Z_el,  _z_el,  "&",    "7",    "Á",    "ᾦ",    "Ű",    "ű", },
            { _X_el,  _x_el,  "*",    "8",    "É",    "ᾧ",    "Ø",    "ø", },
            { _C_el,  _c_el,  "£",    "9",    "ᾮ",    "ῷ",    "Þ",    "þ", },
            { _V_el,  _v_el,  "<",    com,    "Ώ",    "ώ",    "Ý",    "ý", },
            { _B_el,  _b_el,  ">",    prd,    "ᾞ",    "ᾖ",    "†",    "‡", },
            { _N_el,  _n_el,  "‘",    "↑",    "Ú",    "ᾗ",    "–",    "—", },
            { _M_el,  _m_el,  "’",    "↓",    "Ç",    "ç",    "…",    "¨", },
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
            { label = "κενό",
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
