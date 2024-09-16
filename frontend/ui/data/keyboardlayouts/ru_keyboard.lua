local ru_popup = dofile("frontend/ui/data/keyboardlayouts/keypopup/ru_popup.lua")
local pco = ru_popup.pco
local cop = ru_popup.cop
local cse = ru_popup.cse
local sec = ru_popup.sec
local quo = ru_popup.quo
-- Russian layout, top row of letters
local _YK = ru_popup._YK
local _yk = ru_popup._yk
local _TS = ru_popup._TS
local _ts = ru_popup._ts
local _UU = ru_popup._UU
local _uu = ru_popup._uu
local _KK = ru_popup._KK
local _kk = ru_popup._kk
local _YE = ru_popup._YE
local _ye = ru_popup._ye
local _EN = ru_popup._EN
local _en = ru_popup._en
local _GG = ru_popup._GG
local _gg = ru_popup._gg
local _WA = ru_popup._WA
local _wa = ru_popup._wa
local _WE = ru_popup._WE
local _we = ru_popup._we
local _ZE = ru_popup._ZE
local _ze = ru_popup._ze
local _HA = ru_popup._HA
local _ha = ru_popup._ha
-- Russian layout, middle row of letters
local _EF = ru_popup._EF
local _ef = ru_popup._ef
local _YY = ru_popup._YY
local _yy = ru_popup._yy
local _VE = ru_popup._VE
local _ve = ru_popup._ve
local _AA = ru_popup._AA
local _aa = ru_popup._aa
local _PE = ru_popup._PE
local _pe = ru_popup._pe
local _ER = ru_popup._ER
local _er = ru_popup._er
local _OO = ru_popup._OO
local _oo = ru_popup._oo
local _EL = ru_popup._EL
local _el = ru_popup._el
local _DE = ru_popup._DE
local _de = ru_popup._de
local _JE = ru_popup._JE
local _je = ru_popup._je
local _EE = ru_popup._EE
local _ee = ru_popup._ee
-- Russian layout, bottom row of letters
local _YA = ru_popup._YA
local _ya = ru_popup._ya
local _CH = ru_popup._CH
local _ch = ru_popup._ch
local _ES = ru_popup._ES
local _es = ru_popup._es
local _EM = ru_popup._EM
local _em = ru_popup._em
local _II = ru_popup._II
local _ii = ru_popup._ii
local _TE = ru_popup._TE
local _te = ru_popup._te
local _SH = ru_popup._SH
local _sh = ru_popup._sh -- the Russian soft/hard sign
local _BE = ru_popup._BE
local _be = ru_popup._be
local _YU = ru_popup._YU
local _yu = ru_popup._yu
-- other
local _1_ = ru_popup._1_ -- numeric key 1
local _1p = ru_popup._1p -- numeric key 1, popup sibling (they have north swipe ups of each other, the rest is the same)
local _1n = ru_popup._1n -- numpad key 1
local _1s = ru_popup._1s -- superscript key 1
local _2_ = ru_popup._2_
local _2p = ru_popup._2p
local _2n = ru_popup._2n
local _2s = ru_popup._2s
local _3_ = ru_popup._3_
local _3p = ru_popup._3p
local _3n = ru_popup._3n
local _3s = ru_popup._3s
local _4_ = ru_popup._4_
local _4p = ru_popup._4p
local _4n = ru_popup._4n
local _4s = ru_popup._4s
local _5_ = ru_popup._5_
local _5p = ru_popup._5p
local _5n = ru_popup._5n
local _5s = ru_popup._5s
local _6_ = ru_popup._6_
local _6p = ru_popup._6p
local _6n = ru_popup._6n
local _6s = ru_popup._6s
local _7_ = ru_popup._7_
local _7p = ru_popup._7p
local _7n = ru_popup._7n
local _7s = ru_popup._7s
local _8_ = ru_popup._8_
local _8p = ru_popup._8p
local _8n = ru_popup._8n
local _8s = ru_popup._8s
local _9_ = ru_popup._9_
local _9p = ru_popup._9p
local _9n = ru_popup._9n
local _9s = ru_popup._9s
local _0_ = ru_popup._0_
local _0p = ru_popup._0p
local _0n = ru_popup._0n
local _0s = ru_popup._0s
local sla = ru_popup.sla
local sl2 = ru_popup.sl2
local eql = ru_popup.eql
local eq2 = ru_popup.eq2
local pls = ru_popup.pls
local pl2 = ru_popup.pl2
local mns = ru_popup.mns
local mn2 = ru_popup.mn2
local dsh = ru_popup.dsh
local dgr = ru_popup.dgr
local tpg = ru_popup.tpg
local mth = ru_popup.mth
local mt2 = ru_popup.mt2
local int = ru_popup.int
local dif = ru_popup.dif
local df2 = ru_popup.df2
local ls1 = ru_popup.ls1
local ls2 = ru_popup.ls2
local mr1 = ru_popup.mr1
local mr2 = ru_popup.mr2
local pdc = ru_popup.pdc
local pd2 = ru_popup.pd2
local bar = ru_popup.bar
local prm = ru_popup.prm
local hsh = ru_popup.hsh
local hs2 = ru_popup.hs2

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
            { sec, cse, "Ѣ", "ѣ", }, -- comma/semicolon with CSS popup block, plus Russian old letter yat (ять)
        },
        -- Second row
        { --   R    r    S    s
            { _YK, _yk, dif, "?",  },
            { _TS, _ts, int, "¿",  },
            { _UU, _uu, mth, "~",  },
            { _KK, _kk, mt2, "\\", },
            { _YE, _ye, df2, bar,  },
            { _EN, _en, sl2, sla,  },
            { _GG, _gg, _4s, _4n,  },
            { _WA, _wa, _5s, _5n,  },
            { _WE, _we, _6s, _6n,  },
            { _ZE, _ze, mn2, mns,  },
            { _HA, _ha, "Ѳ", "ѳ",  }, -- Russian old letter fita (фита)
        },
        -- Third row
        { --   R    r    S    s
            { _EF, _ef, ls2, ls1, },
            { _YY, _yy, mr2, mr1, },
            { _VE, _ve, dgr, "(", },
            { _AA, _aa, tpg, ")", },
            { _PE, _pe, hs2, hsh, },
            { _ER, _er, pd2, pdc, },
            { _OO, _oo, _1s, _1n, },
            { _EL, _el, _2s, _2n, },
            { _DE, _de, _3s, _3n, },
            { _JE, _je, pl2, pls, },
            { _EE, _ee, "Ѵ", "ѵ", }, -- Russian old letter izhitsa (ижица)
        },
        -- Fourth row
        { --   R    r    S    s
            { label = "", width = 1.0, }, -- Shift
            { _YA, _ya, prm, "{", },
            { _CH, _ch, "°", "}", },
            { _ES, _es, "«", "«", },
            { _EM, _em, "»", "»", },
            { _II, _ii, "„", "[", },
            { _TE, _te, "”", "]", },
            { _SH, _sh, _0s, _0n, },
            { _BE, _be, "↑", "↑", },
            { _YU, _yu, "↓", "↓", },
            { label = "", width = 1.0, }, -- Backspace
        },
        -- Fifth row
        { --   R    r    S    s
            { label = "⌥", width = 1.5, bold = true, }, -- SYM key
            { label = "🌐", }, -- Globe key
            { cop, pco, cop, pco, }, -- period/colon with RegEx popup block
            { label = "_", " ", " ", " ", " ", width = 4.0, }, -- Spacebar
            { label = "←", }, -- Arrow left
            { label = "→", }, -- Arrow right
            { label = "⮠", "\n","\n","\n","\n", width = 1.5, }, -- Enter
        },
    },
}
