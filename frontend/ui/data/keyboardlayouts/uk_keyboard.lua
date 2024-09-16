local uk_popup = dofile("frontend/ui/data/keyboardlayouts/keypopup/uk_popup.lua")
local pco = uk_popup.pco
local cop = uk_popup.cop
local cse = uk_popup.cse
local sec = uk_popup.sec
local quo = uk_popup.quo
local Apo = uk_popup.Apo
local apo = uk_popup.apo
-- Ukrainian letters
local _A_ = uk_popup._A_
local _a_ = uk_popup._a_
local _B_ = uk_popup._B_
local _b_ = uk_popup._b_
local _V_ = uk_popup._V_
local _v_ = uk_popup._v_
local _H_ = uk_popup._H_
local _h_ = uk_popup._h_
local _G_ = uk_popup._G_
local _g_ = uk_popup._g_
local _D_ = uk_popup._D_
local _d_ = uk_popup._d_
local _E_ = uk_popup._E_
local _e_ = uk_popup._e_
local _Ye_ = uk_popup._Ye_
local _ye_ = uk_popup._ye_
local _Zh_ = uk_popup._Zh_
local _zh_ = uk_popup._zh_
local _Z_ = uk_popup._Z_
local _z_ = uk_popup._z_
local _Y_ = uk_popup._Y_
local _y_ = uk_popup._y_
local _I_ = uk_popup._I_
local _i_ = uk_popup._i_
local _Yi_ = uk_popup._Yi_
local _yi_ = uk_popup._yi_
local _Yot_ = uk_popup._Yot_
local _yot_ = uk_popup._yot_
local _K_ = uk_popup._K_
local _k_ = uk_popup._k_
local _L_ = uk_popup._L_
local _l_ = uk_popup._l_
local _M_ = uk_popup._M_
local _m_ = uk_popup._m_
local _N_ = uk_popup._N_
local _n_ = uk_popup._n_
local _O_ = uk_popup._O_
local _o_ = uk_popup._o_
local _P_ = uk_popup._P_
local _p_ = uk_popup._p_
local _R_ = uk_popup._R_
local _r_ = uk_popup._r_
local _S_ = uk_popup._S_
local _s_ = uk_popup._s_
local _T_ = uk_popup._T_
local _t_ = uk_popup._t_
local _U_ = uk_popup._U_
local _u_ = uk_popup._u_
local _F_ = uk_popup._F_
local _f_ = uk_popup._f_
local _Kh_ = uk_popup._Kh_
local _kh_ = uk_popup._kh_
local _Ts_ = uk_popup._Ts_
local _ts_ = uk_popup._ts_
local _Ch_ = uk_popup._Ch_
local _ch_ = uk_popup._ch_
local _Sh_ = uk_popup._Sh_
local _sh_ = uk_popup._sh_
local _Shch_ = uk_popup._Shch_
local _shch_ = uk_popup._shch_
local _Ssn_ = uk_popup._Ssn_
local _ssn_ = uk_popup._ssn_
local _Yu_ = uk_popup._Yu_
local _yu_ = uk_popup._yu_
local _Ya_ = uk_popup._Ya_
local _ya_ = uk_popup._ya_
-- other
local _1_ = uk_popup._1_ -- numeric key 1
local _1p = uk_popup._1p -- numeric key 1, popup sibling (they have north swipe ups of each other, the rest is the same)
local _1n = uk_popup._1n -- numpad key 1
local _1s = uk_popup._1s -- superscript key 1
local _2_ = uk_popup._2_
local _2p = uk_popup._2p
local _2n = uk_popup._2n
local _2s = uk_popup._2s
local _3_ = uk_popup._3_
local _3p = uk_popup._3p
local _3n = uk_popup._3n
local _3s = uk_popup._3s
local _4_ = uk_popup._4_
local _4p = uk_popup._4p
local _4n = uk_popup._4n
local _4s = uk_popup._4s
local _5_ = uk_popup._5_
local _5p = uk_popup._5p
local _5n = uk_popup._5n
local _5s = uk_popup._5s
local _6_ = uk_popup._6_
local _6p = uk_popup._6p
local _6n = uk_popup._6n
local _6s = uk_popup._6s
local _7_ = uk_popup._7_
local _7p = uk_popup._7p
local _7n = uk_popup._7n
local _7s = uk_popup._7s
local _8_ = uk_popup._8_
local _8p = uk_popup._8p
local _8n = uk_popup._8n
local _8s = uk_popup._8s
local _9_ = uk_popup._9_
local _9p = uk_popup._9p
local _9n = uk_popup._9n
local _9s = uk_popup._9s
local _0_ = uk_popup._0_
local _0p = uk_popup._0p
local _0n = uk_popup._0n
local _0s = uk_popup._0s
local sla = uk_popup.sla
local sl2 = uk_popup.sl2
local eql = uk_popup.eql
local eq2 = uk_popup.eq2
local pls = uk_popup.pls
local pl2 = uk_popup.pl2
local mns = uk_popup.mns
local mn2 = uk_popup.mn2
local dsh = uk_popup.dsh
local dgr = uk_popup.dgr
local tpg = uk_popup.tpg
local mth = uk_popup.mth
local mt2 = uk_popup.mt2
local int = uk_popup.int
local dif = uk_popup.dif
local df2 = uk_popup.df2
local ls1 = uk_popup.ls1
local ls2 = uk_popup.ls2
local mr1 = uk_popup.mr1
local mr2 = uk_popup.mr2
local pdc = uk_popup.pdc
local pd2 = uk_popup.pd2
local bar = uk_popup.bar
local prm = uk_popup.prm
local hsh = uk_popup.hsh
local hs2 = uk_popup.hs2

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
            { _0p, _0_, sec, cse, },
            { Apo, apo, Apo, apo, },
        },
        -- Second row
        { --   R    r    S    s
            { _Yot_, _yot_, dif, "?", },
            { _Ts_, _ts_, int, "¿", },
            { _U_, _u_, mth, "~", },
            { _K_, _k_, mt2, "\\", },
            { _E_, _e_, df2, bar, },
            { _N_, _n_, sl2, sla, },
            { _H_, _h_, _4s, _4n, },
            { _Sh_, _sh_, _5s, _5n, },
            { _Shch_, _shch_, _6s, _6n, },
            { _Z_, _z_, mn2, mns, },
            { _Kh_, _kh_, _Yi_, _yi_, },
        },
        -- Third row
        { --   R    r    S    s
            { _F_, _f_, ls2, ls1, },
            { _I_, _i_, mr2, mr1, },
            { _V_, _v_, dgr, "(", },
            { _A_, _a_, tpg, ")", },
            { _P_, _p_, hs2, hsh, },
            { _R_, _r_, pd2, pdc, },
            { _O_, _o_, _1s, _1n, },
            { _L_, _l_, _2s, _2n, },
            { _D_, _d_, _3s, _3n, },
            { _Zh_, _zh_, pl2, pls, },
            { _Ye_, _ye_, _G_, _g_, },
        },
        -- Fourth row
        { --   R    r    S    s
            { label = "", width = 1.0, }, -- Shift
            { _Ya_, _ya_, prm, "{", },
            { _Ch_, _ch_, "°", "}", },
            { _S_, _s_, "«", "«", },
            { _M_, _m_, "»", "»", },
            { _Y_, _y_, "„", "[", },
            { _T_, _t_, "”", "]", },
            { _Ssn_, _ssn_, _0s, _0n, },
            { _B_, _b_, "↑", "↑", },
            { _Yu_, _yu_, "↓", "↓", },
            { label = "", width = 1.0, }, -- Backspace
        },
        -- Fifth row
        { --   R    r    S    s
            { label = "⌥", width = 1.5, bold = true, }, -- SYM key
            { label = "🌐", }, -- Globe key
            { pco, cop, pco, cop, }, -- period/colon with RegEx popup block
            { label = "_", " ", " ", " ", " ", width = 4.0, }, -- Spacebar
            { label = "←", }, -- Arrow left
            { label = "→", }, -- Arrow right
            { label = "⮠", "\n","\n","\n","\n", width = 1.5, }, -- Enter
        },
    },
}
