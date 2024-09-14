local en_popup = dofile("frontend/ui/data/keyboardlayouts/keypopup/en_popup.lua")
local sk_popup = dofile("frontend/ui/data/keyboardlayouts/keypopup/sk_popup.lua")

local pco = en_popup.pco
local cop = en_popup.cop
local cse = en_popup.cse
local sec = en_popup.sec
local quo = en_popup.quo

local _A_ = sk_popup._A_
local _a_ = sk_popup._a_
local _B_ = en_popup._B_
local _b_ = en_popup._b_
local _C_ = sk_popup._C_
local _c_ = sk_popup._c_
local _D_ = sk_popup._D_
local _d_ = sk_popup._d_
local _E_ = sk_popup._E_ -- add alt_label = "€" Euro symbol
local _e_ = sk_popup._e_ -- add alt_label = "€" Euro symbol
local _F_ = en_popup._F_
local _f_ = en_popup._f_
local _G_ = en_popup._G_
local _g_ = en_popup._g_
local _H_ = en_popup._H_
local _h_ = en_popup._h_
local _I_ = sk_popup._I_
local _i_ = sk_popup._i_
local _J_ = en_popup._J_
local _j_ = en_popup._j_
local _K_ = en_popup._K_
local _k_ = en_popup._k_
local _L_ = sk_popup._L_
local _l_ = sk_popup._l_
local _M_ = en_popup._M_
local _m_ = en_popup._m_
local _N_ = sk_popup._N_
local _n_ = sk_popup._n_
local _O_ = sk_popup._O_
local _o_ = sk_popup._o_
local _P_ = en_popup._P_
local _p_ = en_popup._p_
local _Q_ = en_popup._Q_
local _q_ = en_popup._q_
local _R_ = sk_popup._R_
local _r_ = sk_popup._r_
local _S_ = sk_popup._S_
local _s_ = sk_popup._s_
local _T_ = sk_popup._T_
local _t_ = sk_popup._t_
local _U_ = sk_popup._U_
local _u_ = sk_popup._u_
local _V_ = en_popup._V_
local _v_ = en_popup._v_
local _W_ = en_popup._W_
local _w_ = en_popup._w_
local _X_ = en_popup._X_
local _x_ = en_popup._x_
local _Y_ = sk_popup._Y_
local _y_ = sk_popup._y_
local _Z_ = sk_popup._Z_
local _z_ = sk_popup._z_
-- other
local _1_ = sk_popup._1_ -- numeric key 1
local _1p = sk_popup._1p -- numeric key 1, popup sibling (they have north swipe ups of each other, the rest is the same)
local _1n = en_popup._1n -- numpad key 1
local _1s = en_popup._1s -- superscript key 1
local _2_ = sk_popup._2_
local _2p = sk_popup._2p
local _2n = en_popup._2n
local _2s = en_popup._2s
local _3_ = sk_popup._3_
local _3p = sk_popup._3p
local _3n = en_popup._3n
local _3s = en_popup._3s
local _4_ = sk_popup._4_
local _4p = sk_popup._4p
local _4n = en_popup._4n
local _4s = en_popup._4s
local _5_ = sk_popup._5_
local _5p = sk_popup._5p
local _5n = en_popup._5n
local _5s = en_popup._5s
local _6_ = sk_popup._6_
local _6p = sk_popup._6p
local _6n = en_popup._6n
local _6s = en_popup._6s
local _7_ = sk_popup._7_
local _7p = sk_popup._7p
local _7n = en_popup._7n
local _7s = en_popup._7s
local _8_ = sk_popup._8_
local _8p = sk_popup._8p
local _8n = en_popup._8n
local _8s = en_popup._8s
local _9_ = sk_popup._9_
local _9p = sk_popup._9p
local _9n = en_popup._9n
local _9s = en_popup._9s
local _0_ = sk_popup._0_
local _0p = sk_popup._0p
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
    utf8mode_keys = { ["🌐"] = true }, --globe
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
            { _Z_, _z_, sl2, sla, },
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
            { _Y_, _y_, prm, "{", },
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
            { label = "medzera", " ", " ", " ", " ", width = 3.0, }, -- Spacebar
            { label = "←", }, -- Arrow left
            { label = "→", }, -- Arrow right
            { label = "⮠", "\n","\n","\n","\n", width = 1.5, }, -- Enter
        },
    },
}
