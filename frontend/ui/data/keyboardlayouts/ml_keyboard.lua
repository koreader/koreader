local ml_popup = dofile("frontend/ui/data/keyboardlayouts/keypopup/ml_popup.lua")
local com = ml_popup.com
local prd = ml_popup.prd
local _at = ml_popup._at
local _eq = ml_popup._eq
local pco = ml_popup.pco
local cop = ml_popup.cop
local quo = ml_popup.quo
local cse = ml_popup.cse
local sec = ml_popup.sec
local zwj = ml_popup.zwj
local zwnj = ml_popup.zwnj

-- Malayalam Vowels
local _a_in_ = ml_popup._a_in_
local _aa_ = ml_popup._aa_
local _aa_in_ = ml_popup._aa_in_
local _i_ = ml_popup._i_
local _i_in_ = ml_popup._i_in_
local _ii_ = ml_popup._ii_
local _ii_in_ = ml_popup._ii_in_
local _u_ = ml_popup._u_
local _u_in_ = ml_popup._u_in_
local _uu_ = ml_popup._uu_
local _uu_in_ = ml_popup._uu_in_
local _r_ = ml_popup._r_
local _r_in_ = ml_popup._r_in_
local _e_ = ml_popup._e_
local _e_in_ = ml_popup._e_in_
local _ee_ = ml_popup._ee_
local _ee_in_ = ml_popup._ee_in_
local _o_ = ml_popup._o_
local _o_in_ = ml_popup._o_in_
local _oo_ = ml_popup._oo_
local _oo_in_ = ml_popup._oo_in_

-- Malayalam Consonants
local _ka_ = ml_popup._ka_
local _kha_ = ml_popup._kha_
local _ga_ = ml_popup._ga_
local _gha_ = ml_popup._gha_
local _nga_ = ml_popup._nga_
local _ca_ = ml_popup._ca_
local _cha_ = ml_popup._cha_
local _ja_ = ml_popup._ja_
local _jha_ = ml_popup._jha_
local _nya_ = ml_popup._nya_
local _tta_ = ml_popup._tta_
local _ttha_ = ml_popup._ttha_
local _dda_ = ml_popup._dda_
local _ddha_ = ml_popup._ddha_
local _nna_ = ml_popup._nna_
local _ta_ = ml_popup._ta_
local _tha_ = ml_popup._tha_
local _da_ = ml_popup._da_
local _dha_ = ml_popup._dha_
local _na_ = ml_popup._na_
local _pa_ = ml_popup._pa_
local _pha_ = ml_popup._pha_
local _ba_ = ml_popup._ba_
local _bha_ = ml_popup._bha_
local _ma_ = ml_popup._ma_
local _ya_ = ml_popup._ya_
local _ya_li_ = ml_popup._ya_li_
local _ra_ = ml_popup._ra_
local _ra_li_ = ml_popup._ra_li_
local _la_ = ml_popup._la_
local _va_ = ml_popup._va_
local _va_li_ = ml_popup._va_li_
local _sha_ = ml_popup._sha_
local _ssa_ = ml_popup._ssa_
local _sa_ = ml_popup._sa_
local _ha_ = ml_popup._ha_
local _lla_ = ml_popup._lla_
local _llla_ = ml_popup._llla_
local _rra_ = ml_popup._rra_
local _virama_ = ml_popup._virama_
local _visarga_ = ml_popup._visarga_
local _anusvara_ = ml_popup._anusvara_
local _chillu_l_ = ml_popup._chillu_l_
local _chillu_ll_ = ml_popup._chillu_ll_
local _chillu_rr_ = ml_popup._chillu_rr_
local _chillu_n_ = ml_popup._chillu_n_
local _chillu_nn_ = ml_popup._chillu_nn_
-- others
local _1_ = ml_popup._1_
local _1p = ml_popup._1p
local _1n = ml_popup._1n
local _1s = ml_popup._1s
local _2_ = ml_popup._2_
local _2p = ml_popup._2p
local _2n = ml_popup._2n
local _2s = ml_popup._2s
local _3_ = ml_popup._3_
local _3p = ml_popup._3p
local _3n = ml_popup._3n
local _3s = ml_popup._3s
local _4_ = ml_popup._4_
local _4p = ml_popup._4p
local _4n = ml_popup._4n
local _4s = ml_popup._4s
local _5_ = ml_popup._5_
local _5p = ml_popup._5p
local _5n = ml_popup._5n
local _5s = ml_popup._5s
local _6_ = ml_popup._6_
local _6p = ml_popup._6p
local _6n = ml_popup._6n
local _6s = ml_popup._6s
local _7_ = ml_popup._7_
local _7p = ml_popup._7p
local _7n = ml_popup._7n
local _7s = ml_popup._7s
local _8_ = ml_popup._8_
local _8p = ml_popup._8p
local _8n = ml_popup._8n
local _8s = ml_popup._8s
local _9_ = ml_popup._9_
local _9p = ml_popup._9p
local _9n = ml_popup._9n
local _9s = ml_popup._9s
local _0_ = ml_popup._0_
local _0p = ml_popup._0p
local _0n = ml_popup._0n
local _0s = ml_popup._0s
local sla = ml_popup.sla
local sl2 = ml_popup.sl2
local eql = ml_popup.eql
local eq2 = ml_popup.eq2
local pls = ml_popup.pls
local pl2 = ml_popup.pl2
local mns = ml_popup.mns
local mn2 = ml_popup.mn2
local dsh = ml_popup.dsh
local dgr = ml_popup.dgr
local tpg = ml_popup.tpg
local mth = ml_popup.mth
local mt2 = ml_popup.mt2
local int = ml_popup.int
local dif = ml_popup.dif
local df2 = ml_popup.df2
local ls1 = ml_popup.ls1
local ls2 = ml_popup.ls2
local mr1 = ml_popup.mr1
local mr2 = ml_popup.mr2
local pdc = ml_popup.pdc
local pd2 = ml_popup.pd2
local bar = ml_popup.bar
local prm = ml_popup.prm
local hsh = ml_popup.hsh
local hs2 = ml_popup.hs2

return {
    min_layer = 1,
    max_layer = 4,
    shiftmode_keys = { [""] = true },
    symbolmode_keys = { ["⌥"] = true },
    utf8mode_keys = { ["🌐"] = true },
    keys = {
        -- First row
        { --   R    r    S    s
            { zwj, zwj, "ഽ", "൹", },
            { _1p, _1_, "`", "!", },
            { _2p, _2_, "‘", "¡", },
            { _3p, _3_, "’", dsh, },
            { _4p, _4_, "“", "_", },
            { _5p, _5_, "”", quo, },
            { _6p, _6_, eq2, eql, },
            { _7p, _7_, _7s, _7n, },
            { _8p, _8_, _8s, _8n, },
            { _9p, _9_, _9s, _9n, },
            { _0p, _0_, _0s, _0n, },
            { zwnj, zwnj, mn2, mns, },
        },
        -- Second row
        { --   R       r          S    s
            { _a_in_, _virama_, dif, "?", },
            { _aa_in_, _aa_, int, "¿", },
            { _i_in_, _i_, mth, "~", },
            { _ii_in_, _ii_, mt2, "\\", },
            { _u_in_, _u_, df2, bar, },
            { _uu_in_, _uu_, "ൄ", "ൠ", },
            { _r_in_, _r_, "ൣ", "ൡ", },
            { _e_in_, _e_, _4s, _4n, },
            { _ee_in_, _ee_, _5s, _5n, },
            { _o_in_, _o_, _6s, _6n, },
            { _oo_in_, _oo_, pl2, pls, },
            { _chillu_rr_, _rra_, cse, sec, },
        },
        -- Third row
        { --   R        r      S    s
            { _kha_, _ka_, ls2, ls1, },
            { _gha_, _ga_, mr2, mr1, },
            { _nya_, _nga_, dgr, "(", },
            { _cha_, _ca_, tpg, ")", },
            { _jha_, _ja_, hs2, hsh, },
            { _ttha_, _tta_, "൱", "൰", },
            { _ddha_, _dda_, "ൢ", "ഌ", },
            { _chillu_nn_, _nna_, _1s, _1n, },
            { _tha_, _ta_, _2s, _2n, },
            { _dha_, _da_, _3s, _3n, },
            { _chillu_n_, _na_, pd2, pdc, },
            { _llla_, _llla_, sec, cse, },
        },
        -- Fourth row
        { --   R        r      S    s
            { _pha_, _pa_, prm, "{", },
            { _bha_, _ba_, "°", "}", },
            { _anusvara_, _ma_, "«", "[", },
            { _ya_li_, _ya_, "»", "]", },
            { _ra_li_, _ra_, sl2, sla, },
            { _chillu_l_, _la_, "൲", "ഄ", },
            { _va_li_, _va_, "഻", "഼", },
            { _ssa_, _sha_, "ഁ", "ഀ", },
            { _sa_, _sa_, "↑", "↑", },
            { _visarga_, _ha_, "↓", "↓", },
            { _chillu_ll_, _lla_, sla, sl2, },
            { label = "", }, -- Backspace
        },
        -- Fifth row
        { --   R    r    S    s
            { label = "", width = 2.0, }, -- Shift
            { label = "⌥", bold = true, alt_label = "SYM"},
            { label = "🌐", },
            { cop, pco, cop, pco, }, -- period/colon
            { label = "മലയാളം", " ", " ", " ", " ", width = 3.0, }, -- Spacebar
            { label = "←", }, -- Arrow left
            { label = "→", }, -- Arrow right
            { label = "⮠", "\n","\n","\n","\n", width = 2.0, }, -- Enter
        },
    },
}
