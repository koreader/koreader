local bn_popup = dofile("frontend/ui/data/keyboardlayouts/keypopup/bn_popup.lua")
local pco = bn_popup.pco
local cop = bn_popup.cop
local cse = bn_popup.cse
local sec = bn_popup.sec
local quo = bn_popup.quo
-- Bengali letters
local _da_ = bn_popup._da_
local _dha_ = bn_popup._dha_
local _U_kaar_ = bn_popup._U_kaar_
local _U_ = bn_popup._U_
local _I_kaar_ = bn_popup._I_kaar_
local _I_ = bn_popup._I_
local _ra_ = bn_popup._ra_
local _rda_ = bn_popup._rda_
local _Ta_ = bn_popup._Ta_
local _Tha_ = bn_popup._Tha_
local _e_ = bn_popup._e_
local _oi_ = bn_popup._oi_
local _u_kaar_ = bn_popup._u_kaar_
local _u_ = bn_popup._u_
local _i_kaar_ = bn_popup._i_kaar_
local _i_ = bn_popup._i_
local _o_ = bn_popup._o_
local _ou_ = bn_popup._ou_
local _pa_ = bn_popup._pa_
local _pha_ = bn_popup._pha_
local _e_kaar_ = bn_popup._e_kaar_
local _oi_kaar_ = bn_popup._oi_kaar_
local _o_kaar_ = bn_popup._o_kaar_
local _ou_kaar_ = bn_popup._ou_kaar_
local _aa_kaar_ = bn_popup._aa_kaar_
local _a_ = bn_popup._a_
local _sa_ = bn_popup._sa_
local _sHa_ = bn_popup._sHa_
local _Da_ = bn_popup._Da_
local _Dha_ = bn_popup._Dha_
local _ta_ = bn_popup._ta_
local _tha_ = bn_popup._tha_
local _ga_ = bn_popup._ga_
local _gha_ = bn_popup._gha_
local _ha_ = bn_popup._ha_
local _bisarga_ = bn_popup._bisarga_
local _ja_ = bn_popup._ja_
local _jha_ = bn_popup._jha_
local _ka_ = bn_popup._ka_
local _kha_ = bn_popup._kha_
local _la_ = bn_popup._la_
local _anuswara_ = bn_popup._anuswara_
local _jya_ = bn_popup._jya_
local _ya_ = bn_popup._ya_
local _sha_ = bn_popup._sha_
local _Rha_ = bn_popup._Rha_
local _cha_ = bn_popup._cha_
local _Cha_ = bn_popup._Cha_
local _aa_ = bn_popup._aa_
local _rwi_ = bn_popup._rwi_
local _ba_ = bn_popup._ba_
local _bha_ = bn_popup._bha_
local _na_ = bn_popup._na_
local _Na_ = bn_popup._Na_
local _ma_ = bn_popup._ma_
local _uma_ = bn_popup._uma_
local _rwi_kaar_ = bn_popup._rwi_kaar_
local _chandrabindu_ = bn_popup._chandrabindu_
local com2 = bn_popup.com2
local daari = bn_popup.daari
local hashanto = bn_popup.hashanto
local question2 = bn_popup.question2

-- other
local _1_ = bn_popup._1_ -- numeric key 1
local _1p = bn_popup._1p -- numeric key 1, popup sibling (they have north swipe ups of each other, the rest is the same)
local _1n = bn_popup._1n -- numpad key 1
local _1s = bn_popup._1s -- superscript key 1
local _2_ = bn_popup._2_
local _2p = bn_popup._2p
local _2n = bn_popup._2n
local _2s = bn_popup._2s
local _3_ = bn_popup._3_
local _3p = bn_popup._3p
local _3n = bn_popup._3n
local _3s = bn_popup._3s
local _4_ = bn_popup._4_
local _4p = bn_popup._4p
local _4n = bn_popup._4n
local _4s = bn_popup._4s
local _5_ = bn_popup._5_
local _5p = bn_popup._5p
local _5n = bn_popup._5n
local _5s = bn_popup._5s
local _6_ = bn_popup._6_
local _6p = bn_popup._6p
local _6n = bn_popup._6n
local _6s = bn_popup._6s
local _7_ = bn_popup._7_
local _7p = bn_popup._7p
local _7n = bn_popup._7n
local _7s = bn_popup._7s
local _8_ = bn_popup._8_
local _8p = bn_popup._8p
local _8n = bn_popup._8n
local _8s = bn_popup._8s
local _9_ = bn_popup._9_
local _9p = bn_popup._9p
local _9n = bn_popup._9n
local _9s = bn_popup._9s
local _0_ = bn_popup._0_
local _0p = bn_popup._0p
local _0n = bn_popup._0n
local _0s = bn_popup._0s
local sla = bn_popup.sla
local sl2 = bn_popup.sl2
local eql = bn_popup.eql
local eq2 = bn_popup.eq2
local pls = bn_popup.pls
local pl2 = bn_popup.pl2
local mns = bn_popup.mns
local mn2 = bn_popup.mn2
local dsh = bn_popup.dsh
local dgr = bn_popup.dgr
local tpg = bn_popup.tpg
local mth = bn_popup.mth
local mt2 = bn_popup.mt2
local int = bn_popup.int
local dif = bn_popup.dif
local df2 = bn_popup.df2
local ls1 = bn_popup.ls1
local ls2 = bn_popup.ls2
local mr1 = bn_popup.mr1
local mr2 = bn_popup.mr2
local pdc = bn_popup.pdc
local pd2 = bn_popup.pd2
local bar = bn_popup.bar
local prm = bn_popup.prm
local hsh = bn_popup.hsh
local hs2 = bn_popup.hs2

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
            { _dha_, _da_, dif, "?",  width = 0.833},
            { _U_, _U_kaar_, int, "¿", width = 0.833},
            { _I_, _I_kaar_, mth, "~", width = 0.833},
            { _rda_, _ra_, mt2, "\\", width = 0.833},
            { _Tha_, _Ta_, df2, bar, width = 0.833},
            { _oi_, _e_, sl2, sla, width = 0.833},
            { _u_, _u_kaar_, _4s, _4n, width = 0.833},
            { _i_, _i_kaar_, _5s, _5n, width = 0.833},
            { _ou_, _o_, _6s, _6n, width = 0.833},
            { _pha_, _pa_, pl2, pls, width = 0.833},
            { _oi_kaar_, _e_kaar_, "[", "{", width = 0.833},
            { _ou_kaar_, _o_kaar_, "]", "}", width = 0.833},
        },

        -- Third row
        { --   R    r    S    s
            { _a_, _aa_kaar_, ls2, ls1, },
            { _sHa_, _sa_, mr2, mr1, },
            { _Dha_, _Da_, dgr, "(", },
            { _tha_, _ta_, tpg, ")", },
            { _gha_, _ga_, hs2, hsh, },
            { _bisarga_, _ha_, pd2, pdc, },
            { _jha_, _ja_, _1s, _1n, },
            { _kha_, _ka_, _2s, _2n, },
            { _anuswara_, _la_, _3s, _3n, },
            { sec, cse, sec, cse, }, -- comma/semicolon with CSS popup block
        },
        -- Fourth row
        { --   R    r    S    s
            { label = "", width = 0.9 }, -- Shift
            { _ya_, _jya_, prm, "{", width = 0.82},
            { _Rha_, _sha_, "°", "}", width = 0.82},
            { _Cha_, _cha_, "«", "[", width = 0.82},
            { _rwi_, _aa_, "»", "]", width = 0.82},
            { _bha_, _ba_, _0s, _0n, width = 0.82},
            { _Na_, _na_, "↑", "↑", width = 0.82},
            { _uma_, _ma_, "↓", "↓", width = 0.82},
            { _rwi_kaar_, com2, "়", "ৄ", width = 0.82},
            { _chandrabindu_, daari, "ৠ", "ৡ", width = 0.82},
            { question2, hashanto, "ৰ", "ৱ", width = 0.82},
            { label = "", width = 0.9 }, -- Backspace
        },
        -- Fifth row
        { --   R    r    S    s
            { label = "⌥", width = 1.5, bold = true, alt_label = "SYM"}, -- SYM key
            { label = "🌐", }, -- Globe key
            { cop, pco, cop, pco, }, -- period/colon with RegEx popup block
            { label = "বাংলা", " ", " ", " ", " ", width = 3.0, }, -- Spacebar
            { label = "←", }, -- Arrow left
            { label = "→", }, -- Arrow right
            { label = "⮠", "\n","\n","\n","\n", width = 1.5, }, -- Enter
        },
    },
}
