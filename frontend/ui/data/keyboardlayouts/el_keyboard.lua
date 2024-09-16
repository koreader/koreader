local el_popup = dofile("frontend/ui/data/keyboardlayouts/keypopup/el_popup.lua")
local pco = el_popup.pco
local cop = el_popup.cop
local cse = el_popup.cse
local sec = el_popup.sec
local quo = el_popup.quo
-- Greek letters
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
local _Q_el = el_popup._Q_el
local _q_el = el_popup._q_el
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
local _W_el = el_popup._W_el
local _w_el = el_popup._w_el
local _X_el = el_popup._X_el
local _x_el = el_popup._x_el
local _Y_el = el_popup._Y_el
local _y_el = el_popup._y_el
local _Z_el = el_popup._Z_el
local _z_el = el_popup._z_el
-- other
local _1_ = el_popup._1_ -- numeric key 1
local _1p = el_popup._1p -- numeric key 1, popup sibling (they have north swipe ups of each other, the rest is the same)
local _1n = el_popup._1n -- numpad key 1
local _1s = el_popup._1s -- superscript key 1
local _2_ = el_popup._2_
local _2p = el_popup._2p
local _2n = el_popup._2n
local _2s = el_popup._2s
local _3_ = el_popup._3_
local _3p = el_popup._3p
local _3n = el_popup._3n
local _3s = el_popup._3s
local _4_ = el_popup._4_
local _4p = el_popup._4p
local _4n = el_popup._4n
local _4s = el_popup._4s
local _5_ = el_popup._5_
local _5p = el_popup._5p
local _5n = el_popup._5n
local _5s = el_popup._5s
local _6_ = el_popup._6_
local _6p = el_popup._6p
local _6n = el_popup._6n
local _6s = el_popup._6s
local _7_ = el_popup._7_
local _7p = el_popup._7p
local _7n = el_popup._7n
local _7s = el_popup._7s
local _8_ = el_popup._8_
local _8p = el_popup._8p
local _8n = el_popup._8n
local _8s = el_popup._8s
local _9_ = el_popup._9_
local _9p = el_popup._9p
local _9n = el_popup._9n
local _9s = el_popup._9s
local _0_ = el_popup._0_
local _0p = el_popup._0p
local _0n = el_popup._0n
local _0s = el_popup._0s
local sla = el_popup.sla
local sl2 = el_popup.sl2
local eql = el_popup.eql
local eq2 = el_popup.eq2
local pls = el_popup.pls
local pl2 = el_popup.pl2
local mns = el_popup.mns
local mn2 = el_popup.mn2
local dsh = el_popup.dsh
local dgr = el_popup.dgr
local tpg = el_popup.tpg
local mth = el_popup.mth
local mt2 = el_popup.mt2
local int = el_popup.int
local dif = el_popup.dif
local df2 = el_popup.df2
local ls1 = el_popup.ls1
local ls2 = el_popup.ls2
local mr1 = el_popup.mr1
local mr2 = el_popup.mr2
local pdc = el_popup.pdc
local pd2 = el_popup.pd2
local bar = el_popup.bar
local prm = el_popup.prm
local hsh = el_popup.hsh
local hs2 = el_popup.hs2

return {
    min_layer = 1,
    max_layer = 4,
    shiftmode_keys = { [""] = true },
    symbolmode_keys = { ["⌥"] = true },
    utf8mode_keys = { ["🌐"] = true },
    -- Width of any key can be modified by adding "width = 1.0, " in the list.
    keys = {
        -- First row
        { --   R    r    S    s
            { _1p, _1_, "`", "!", },
            { _2p, _2_, "‘", "¡", },
            { _3p, _3_, "’", dsh, },
            { _4p, _4_, "“", "_", },
            { _5p, _5_, "”", quo, },
            { _6p, _6_, eq2, eql, },
            { _7p, _7_, _7s, _7n, },
            { _8p, _8_, _8s, _8n, },
            { _9p, _9_, _9s, _9n, },
            { _0p, _0_, mn2, mns, },
        },
        -- Second row
        { --   R    r    S    s
            { _Q_el, _q_el, dif, "?", },
            { _W_el, _w_el, int, "¿", },
            { _E_el, _e_el, mth, "~", },
            { _R_el, _r_el, mt2, "\\", },
            { _T_el, _t_el, df2, bar, },
            { _Y_el, _y_el, sl2, sla, },
            { _U_el, _u_el, _4s, _4n, },
            { _I_el, _i_el, _5s, _5n, },
            { _O_el, _o_el, _6s, _6n, },
            { _P_el, _p_el, pl2, pls, },
        },
        -- Third row
        { --   R    r    S    s
            { _A_el, _a_el, ls2, ls1, },
            { _S_el, _s_el, mr2, mr1, },
            { _D_el, _d_el, dgr, "(", },
            { _F_el, _f_el, tpg, ")", },
            { _G_el, _g_el, hs2, hsh, },
            { _H_el, _h_el, pd2, pdc, },
            { _J_el, _j_el, _1s, _1n, },
            { _K_el, _k_el, _2s, _2n, },
            { _L_el, _l_el, _3s, _3n, },
            { sec, cse, sec, cse, }, -- comma/semicolon with CSS popup block
        },
        -- Fourth row
        { --   R    r    S    s
            { label = "", width = 1.5, }, -- Shift
            { _Z_el, _z_el, prm, "{", },
            { _X_el, _x_el, "°", "}", },
            { _C_el, _c_el, "«", "[", },
            { _V_el, _v_el, "»", "]", },
            { _B_el, _b_el, _0s, _0n, },
            { _N_el, _n_el, "↑", "↑", },
            { _M_el, _m_el, "↓", "↓", },
            { label = "", width = 1.5, }, -- Backspace
        },
        -- Fifth row
        { --   R    r    S    s
            { label = "⌥", width = 1.5, bold = true, alt_label = "SYM"}, -- SYM key
            { label = "🌐", }, -- Globe key
            { cop, pco, cop, pco, }, -- period/colon with RegEx popup block
            { label = "_", " ", " ", " ", " ", width = 3.0, }, -- Spacebar
            { label = "←", }, -- Arrow left
            { label = "→", }, -- Arrow right
            { label = "⮠", "\n","\n","\n","\n", width = 1.5, }, -- Enter
        },
    },
}
