local en_popup = require("ui/data/keyboardlayouts/keypopup/en_popup")
local prd = en_popup.prd
local com = en_popup.com
local apo = en_popup.apo
local quo = en_popup.quo
local smc = en_popup.smc
local sla = en_popup.sla
local cri = en_popup.cri
local cro = en_popup.cro
local sud = en_popup.sud
local _eq = en_popup._eq
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
local _1_ = en_popup._1_
local _2_ = en_popup._2_
local _3_ = en_popup._3_
local _4_ = en_popup._4_
local _5_ = en_popup._5_
local _6_ = en_popup._6_
local _7_ = en_popup._7_
local _8_ = en_popup._8_
local _9_ = en_popup._9_
local _0_ = en_popup._0_

return {
    min_layer = 1,
    max_layer = 4,
    shiftmode_keys = { [""] = true },
    symbolmode_keys = { ["⌥"] = true },
    utf8mode_keys = { ["🌐"] = true },
    keys = {
        -- First row
        { --   R    r    S    s
            { "!", _1_, "!", _1_, },
            { "@", _2_, "@", _2_, },
            { "#", _3_, "#", _3_, },
            { "$", _4_, "$", _4_, },
            { "%", _5_, "%", _5_, },
            { "^", _6_, "^", _6_, },
            { "&", _7_, "&", _7_, },
            { "*", _8_, "*", _8_, },
            { "(", _9_, "(", _9_, },
            { ")", _0_, ")", _0_, },
            { "_", _eq, "_", _eq, },
        },
        -- Second row
        { --   R    r    S    s
            { _Q_, _q_, "´", "`", },
            { _W_, _w_, "¨", "~", },
            { _E_, _e_, "†", "‡", },
            { _R_, _r_, "ª", "°", },
            { _T_, _t_, "℉", "℃", },
            { _Y_, _y_, "€", "£", },
            { _U_, _u_, "÷", "×", },
            { _I_, _i_, "¯", "—", },
            { _O_, _o_, "±", "≠", },
            { _P_, _p_, "+", "-", },
            { label = "" },
        },
        -- Third row
        { --   R    r    S    s
            { _A_, _a_, "▓", "█", },
            { _S_, _s_, "░", "▒", },
            { _D_, _d_, sud, sud, },
            { _F_, _f_, cro, cri, },
            { _G_, _g_, "☆", "✓", },
            { _H_, _h_, "‼️", "✗", },
            { _J_, _j_, "¼", "½", },
            { _K_, _k_, "²", "√", },
            { _L_, _l_, "|","\\", },
            { ":", smc, ":", smc, },
            { quo, apo, quo, apo, },
        },
        -- Fourth row
        { --   R    r    S    s
            { label = "",
              width = 1.5, },
            { _Z_, _z_, "🌐", "🌐", },
            { _X_, _x_, "ツ", "◕", },
            { _C_, _c_, "ඞ", "✿", },
            { _V_, _v_, "↻", "⇒", },
            { _B_, _b_, "⋅", "‰", },
            { _N_, _n_, { "{", north = "[", west = "「", }, { "[", north = "{", west = "【", }, },
            { _M_, _m_, { "}", north = "]", west = "」", }, { "]", north = "}", west = "】", }, },
            { label = "↑", },
            { label = "⮠",
             "\n","\n","\n","\n",
              width = 1.5, },
        },
        -- Fifth row
        { --   R    r    S    s
            { label = "⌥",
              width = 1.5,
              bold = true, },
            { "?", sla, "?", sla, },
            { label = "_",
              " ", " ", " ", " ",
              width = 3.5, },
            { "<", com, "<", com, },
            { ">", prd, ">", prd, },
            { label = "←", },
            { label = "↓", },
            { label = "→", },
        },
    },
}
