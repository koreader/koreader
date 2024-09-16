local en_popup = dofile("frontend/ui/data/keyboardlayouts/keypopup/en_popup.lua")
local pco = en_popup.pco
local cop = en_popup.cop
local cse = en_popup.cse
local sec = en_popup.sec
local quo = en_popup.quo
-- English letters
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
-- other
local _1_ = en_popup._1_ -- numeric key 1
local _1p = en_popup._1p -- numeric key 1, popup sibling (they have north swipe ups of each other, the rest is the same)
local _1n = en_popup._1n -- numpad key 1
local _1s = en_popup._1s -- superscript key 1
local _2_ = en_popup._2_
local _2p = en_popup._2p
local _2n = en_popup._2n
local _2s = en_popup._2s
local _3_ = en_popup._3_
local _3p = en_popup._3p
local _3n = en_popup._3n
local _3s = en_popup._3s
local _4_ = en_popup._4_
local _4p = en_popup._4p
local _4n = en_popup._4n
local _4s = en_popup._4s
local _5_ = en_popup._5_
local _5p = en_popup._5p
local _5n = en_popup._5n
local _5s = en_popup._5s
local _6_ = en_popup._6_
local _6p = en_popup._6p
local _6n = en_popup._6n
local _6s = en_popup._6s
local _7_ = en_popup._7_
local _7p = en_popup._7p
local _7n = en_popup._7n
local _7s = en_popup._7s
local _8_ = en_popup._8_
local _8p = en_popup._8p
local _8n = en_popup._8n
local _8s = en_popup._8s
local _9_ = en_popup._9_
local _9p = en_popup._9p
local _9n = en_popup._9n
local _9s = en_popup._9s
local _0_ = en_popup._0_
local _0p = en_popup._0p
local _0n = en_popup._0n
local _0s = en_popup._0s
local sla = en_popup.sla
local sl2 = en_popup.sl2
local eql = en_popup.eql
local eq2 = en_popup.eq2
local pls = en_popup.pls
local pl2 = en_popup.pl2
local mns = en_popup.mns
local mn2 = en_popup.mn2
local dsh = en_popup.dsh
local dgr = en_popup.dgr
local tpg = en_popup.tpg
local mth = en_popup.mth
local mt2 = en_popup.mt2
local int = en_popup.int
local dif = en_popup.dif
local df2 = en_popup.df2
local ls1 = en_popup.ls1
local ls2 = en_popup.ls2
local mr1 = en_popup.mr1
local mr2 = en_popup.mr2
local pdc = en_popup.pdc
local pd2 = en_popup.pd2
local bar = en_popup.bar
local prm = en_popup.prm
local hsh = en_popup.hsh
local hs2 = en_popup.hs2

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
            { _Q_, _q_, dif, "?", },
            { _W_, _w_, int, "¿", },
            { _E_, _e_, mth, "~", },
            { _R_, _r_, mt2, "\\", },
            { _T_, _t_, df2, bar, },
            { _Y_, _y_, sl2, sla, },
            { _U_, _u_, _4s, _4n, },
            { _I_, _i_, _5s, _5n, },
            { _O_, _o_, _6s, _6n, },
            { _P_, _p_, pl2, pls, },
        },
        -- Third row
        { --   R    r    S    s
            { _A_, _a_, ls2, ls1, },
            { _S_, _s_, mr2, mr1, },
            { _D_, _d_, dgr, "(", },
            { _F_, _f_, tpg, ")", },
            { _G_, _g_, hs2, hsh, },
            { _H_, _h_, pd2, pdc, },
            { _J_, _j_, _1s, _1n, },
            { _K_, _k_, _2s, _2n, },
            { _L_, _l_, _3s, _3n, },
            { sec, cse, sec, cse, }, -- comma/semicolon with CSS popup block
        },
        -- Fourth row
        { --   R    r    S    s
            { label = "", width = 1.5, }, -- Shift
            { _Z_, _z_, prm, "{", },
            { _X_, _x_, "°", "}", },
            { _C_, _c_, "«", "[", },
            { _V_, _v_, "»", "]", },
            { _B_, _b_, _0s, _0n, },
            { _N_, _n_, "↑", "↑", },
            { _M_, _m_, "↓", "↓", },
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
