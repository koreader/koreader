local en_popup = require("ui/data/keyboardlayouts/keypopup/en_popup")
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
    min_layer = 1,
    max_layer = 8,
    shiftmode_keys = { [""] = true },
    symbolmode_keys = { ["⌘"] = true },
    umlautmode_keys = { ["⌥"] = true },
    utf8mode_keys = { ["🌐"] = true },
    keys = {
        -- First row
        { --           S   S   A   A   AS  AS
            { "!", "1", "!", "1", "¡", "１", "¡", "１", },
            { "@", "2", "@", "2", "©", "２", "©", "２", },
            { "#", "3", "#", "3", "¢", "３", "¢", "３", },
            { "$", "4", "$", "4", "€", "４", "€", "４", },
            { "%", "5", "%", "5", "‰", "５", "‰", "５", },
            { "^", "6", "^", "6", "¨", "６", "¨", "６", },
            { "&", "7", "&", "7", "£", "７", "£", "７", },
            { "*", "8", "*", "8", "×", "８", "×", "８", },
            { "(", "9", "(", "9", "【", "９", "【", "９", },
            { ")", "0", ")", "0", "】", "０", "】", "０", },
        },
        -- Second row
        { --           S   S   A   A   AS  AS
            { _Q_, _q_, "~", "`", "Ｑ", "ｑ", "≈", "´", },
            { _W_, _w_, " ", " ", "Ｗ", "ｗ", " ", " ", },
            { _E_, _e_, " ", " ", "Ｅ", "ｅ", " ", " ", },
            { _R_, _r_, " ", " ", "Ｒ", "ｒ", " ", " ", },
            { _T_, _t_, " ", " ", "Ｔ", "ｔ", " ", " ", },
            { _Y_, _y_, " ", " ", "Ｙ", "ｙ", " ", " ", },
            { _U_, _u_, " ", " ", "Ｕ", "ｕ", " ", " ", },
            { _I_, _i_, " ", " ", "Ｉ", "ｉ", " ", " ", },
            { _O_, _o_, "_", "-", "Ｏ", "ｏ", "¯", "—", },
            { _P_, _p_, "+", "=", "Ｐ", "ｐ", "±", "≠", },
        },
        -- Third row
        { --           S   S   A   A   AS  AS
            { _A_, _a_, " ", " ", "Ａ", "ａ", " ", " ", },
            { _S_, _s_, " ", " ", "Ｓ", "ｓ", " ", " ", },
            { _D_, _d_, " ", " ", "Ｄ", "ｄ", " ", " ", },
            { _F_, _f_, " ", " ", "Ｆ", "ｆ", " ", " ", },
            { _G_, _g_, " ", " ", "Ｇ", "ｇ", " ", " ", },
            { _H_, _h_, " ", " ", "Ｈ", "ｈ", " ", " ", },
            { _J_, _j_, ":", ";", "Ｊ", "ｊ", "：", "；", },
            { _K_, _k_, '"', "'", "Ｋ", "ｋ", "＂", "＇", },
            { _L_, _l_,"\\", "/", "Ｌ", "ｌ", "＼", "÷", },
            { label = "" },
        },
        -- Fourth row
        { --           S   S   A   A   AS  AS
            { label = "",
              width = 1.5, },
            { _Z_, _z_, " ", " ", "Ｚ", "ｚ", " ", " ", },
            { _X_, _x_, " ", " ", "Ｘ", "ｘ", " ", " ", },
            { _C_, _c_, " ", " ", "Ｃ", "ｃ", " ", " ", },
            { _V_, _v_, "<", "<", "Ｖ", "ｖ", "≤", "≤", },
            { _B_, _b_, ">", ">", "Ｂ", "ｂ", "≥", "≥", },
            { _N_, _n_, "{", "[", "Ｎ", "ｎ", "〈", "「", },
            { _M_, _m_, "}", "]", "Ｍ", "ｍ", "〉", "」", },
            { label = "⮠",
              "\n", "\n", "\n", "\n", "\n", "\n", "\n", "\n",
              width = 1.5, },
        },
        -- Fifth row
        { --           S   S   A   A   AS  AS
            { label = "⌘",
              width = 1.5,
              bold = true, },
            { label = "⌥",
              bold = true, },
            { label = "🌐" },
            { label = "_",
              " ", " ", " ", " ", " ", " ", " ", " ",
              width = 2.5, },
            { "?", ",", "?", ",", "¿", "„", "¿", "„", },
            { "|", ".", "|", ".", "¦", "…", "¦", "…", },
            { label = "←" },
            { label = "→" },
        },
    },
}
