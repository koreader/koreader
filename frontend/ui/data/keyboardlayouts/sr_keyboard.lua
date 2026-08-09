-- This is adapted en_keyboard
local sr_popup = dofile("frontend/ui/data/keyboardlayouts/keypopup/sr_popup.lua")
local pco = sr_popup.pco
local cop = sr_popup.cop
local cse = sr_popup.cse
local sec = sr_popup.sec
local quo = sr_popup.quo
-- Serbian letters
local _A_ = sr_popup._A_
local _a_ = sr_popup._a_
local _B_ = sr_popup._B_
local _b_ = sr_popup._b_
local _V_ = sr_popup._V_
local _v_ = sr_popup._v_
local _G_ = sr_popup._G_
local _g_ = sr_popup._g_
local _D_ = sr_popup._D_
local _d_ = sr_popup._d_
local _Dj_ = sr_popup._Dj_
local _dj_ = sr_popup._dj_
local _E_ = sr_popup._E_
local _e_ = sr_popup._e_
local _Zh_ = sr_popup._Zh_
local _zh_ = sr_popup._zh_
local _Z_ = sr_popup._Z_
local _z_ = sr_popup._z_
local _I_ = sr_popup._I_
local _i_ = sr_popup._i_
local _J_ = sr_popup._J_
local _j_ = sr_popup._j_
local _K_ = sr_popup._K_
local _k_ = sr_popup._k_
local _L_ = sr_popup._L_
local _l_ = sr_popup._l_
local _Lj_ = sr_popup._Lj_
local _lj_ = sr_popup._lj_
local _M_ = sr_popup._M_
local _m_ = sr_popup._m_
local _N_ = sr_popup._N_
local _n_ = sr_popup._n_
local _Nj_ = sr_popup._Nj_
local _nj_ = sr_popup._nj_
local _O_ = sr_popup._O_
local _o_ = sr_popup._o_
local _P_ = sr_popup._P_
local _p_ = sr_popup._p_
local _R_ = sr_popup._R_
local _r_ = sr_popup._r_
local _S_ = sr_popup._S_
local _s_ = sr_popup._s_
local _T_ = sr_popup._T_
local _t_ = sr_popup._t_
local _Tj_ = sr_popup._Tj_
local _tj_ = sr_popup._tj_
local _U_ = sr_popup._U_
local _u_ = sr_popup._u_
local _F_ = sr_popup._F_
local _f_ = sr_popup._f_
local _H_ = sr_popup._H_
local _h_ = sr_popup._h_
local _C_ = sr_popup._C_
local _c_ = sr_popup._c_
local _Ch_ = sr_popup._Ch_
local _ch_ = sr_popup._ch_
local _Dzh_ = sr_popup._Dzh_
local _dzh_ = sr_popup._dzh_
local _Sh_ = sr_popup._Sh_
local _sh_ = sr_popup._sh_
-- other
local _1_ = sr_popup._1_ -- numeric key 1
local _1p = sr_popup._1p -- numeric key 1, popup sibling (they have north swipe ups of each other, the rest is the same)
local _1n = sr_popup._1n -- numpad key 1
local _1s = sr_popup._1s -- superscript key 1
local _2_ = sr_popup._2_
local _2p = sr_popup._2p
local _2n = sr_popup._2n
local _2s = sr_popup._2s
local _3_ = sr_popup._3_
local _3p = sr_popup._3p
local _3n = sr_popup._3n
local _3s = sr_popup._3s
local _4_ = sr_popup._4_
local _4p = sr_popup._4p
local _4n = sr_popup._4n
local _4s = sr_popup._4s
local _5_ = sr_popup._5_
local _5p = sr_popup._5p
local _5n = sr_popup._5n
local _5s = sr_popup._5s
local _6_ = sr_popup._6_
local _6p = sr_popup._6p
local _6n = sr_popup._6n
local _6s = sr_popup._6s
local _7_ = sr_popup._7_
local _7p = sr_popup._7p
local _7n = sr_popup._7n
local _7s = sr_popup._7s
local _8_ = sr_popup._8_
local _8p = sr_popup._8p
local _8n = sr_popup._8n
local _8s = sr_popup._8s
local _9_ = sr_popup._9_
local _9p = sr_popup._9p
local _9n = sr_popup._9n
local _9s = sr_popup._9s
local _0_ = sr_popup._0_
local _0p = sr_popup._0p
local _0n = sr_popup._0n
local _0s = sr_popup._0s
local sla = sr_popup.sla
local sl2 = sr_popup.sl2
local eql = sr_popup.eql
local eq2 = sr_popup.eq2
local pls = sr_popup.pls
local pl2 = sr_popup.pl2
local mns = sr_popup.mns
local mn2 = sr_popup.mn2
local dsh = sr_popup.dsh
local dgr = sr_popup.dgr
local tpg = sr_popup.tpg
local mth = sr_popup.mth
local mt2 = sr_popup.mt2
local int = sr_popup.int
local dif = sr_popup.dif
local df2 = sr_popup.df2
local ls1 = sr_popup.ls1
local ls2 = sr_popup.ls2
local mr1 = sr_popup.mr1
local mr2 = sr_popup.mr2
local pdc = sr_popup.pdc
local pd2 = sr_popup.pd2
local bar = sr_popup.bar
local prm = sr_popup.prm
local hsh = sr_popup.hsh
local hs2 = sr_popup.hs2
local cl1 = sr_popup.cl1
local cl2 = sr_popup.cl2
local cl3 = sr_popup.cl3
local cl4 = sr_popup.cl4
local bul = sr_popup.bul
local bu2 = sr_popup.bu2

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
            { label = "",        }, -- Backspace
        },
        -- Second row
        { --   R    r    S    s
            { _Lj_, _lj_, dif, "?", },
            { _Nj_, _nj_, int, "¿", },
            { _E_, _e_, mth, "~", },
            { _R_, _r_, mt2, "\\", },
            { _T_, _t_, df2, bar, },
            { _Z_, _z_, sl2, sla, },
            { _U_, _u_, _4s, _4n, },
            { _I_, _i_, _5s, _5n, },
            { _O_, _o_, _6s, _6n, },
            { _P_, _p_, pl2, pls, },
            { _Sh_, _sh_, bul, bu2, },
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
            { _Ch_, _ch_, cl1, cl2, },
            { _Tj_, _tj_, cl3, cl4, },
        },
        -- Fourth row
        { --   R    r    S    s
            { label = "",        }, -- Shift
            { _Dzh_, _dzh_, prm, "{", },
            { _C_, _c_, "°", "}", },
            { _V_, _v_, "«", "[", },
            { _B_, _b_, "»", "]", },
            { _N_, _n_, _0s, _0n, },
            { _M_, _m_, "↑", "↑", },
            { _Dj_, _dj_, "↓", "↓", },
            { _Zh_, _zh_, _0s, _0n, },
            { sec, cse, sec, cse, }, -- comma/semicolon with CSS popup block
            { cop, pco, cop, pco, }, -- period/colon with RegEx popup block
        },
        -- Fifth row
        { --   R    r    S    s
            { label = "⌥", width = 1.5, bold = true, alt_label = "СИМ"}, -- SYM key
            { label = "🌐", width = 1.5, }, -- Globe key
            { label = "_", " ", " ", " ", " ", width = 3.0, }, -- Spacebar
            { label = "←", }, -- Arrow left
            { label = "→", }, -- Arrow right
            { label = "⮠", "\n","\n","\n","\n", width = 3.0, }, -- Enter
        },
    },
}
