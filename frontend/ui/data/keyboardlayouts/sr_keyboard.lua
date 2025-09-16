-- This is adapted en_keyboard
local sr_popup = dofile("frontend/ui/data/keyboardlayouts/keypopup/sr_popup.lua")
local pco = sr_popup.pco
local cop = sr_popup.cop
local cse = sr_popup.cse
local sec = sr_popup.sec
local quo = sr_popup.quo
-- Serbian letters
local _А_ = sr_popup._А_
local _а_ = sr_popup._а_
local _Б_ = sr_popup._Б_
local _б_ = sr_popup._б_
local _В_ = sr_popup._В_
local _в_ = sr_popup._в_
local _Г_ = sr_popup._Г_
local _г_ = sr_popup._г_
local _Д_ = sr_popup._Д_
local _д_ = sr_popup._д_
local _Ђ_ = sr_popup._Ђ_
local _ђ_ = sr_popup._ђ_
local _Е_ = sr_popup._Е_
local _е_ = sr_popup._е_
local _Ж_ = sr_popup._Ж_
local _ж_ = sr_popup._ж_
local _З_ = sr_popup._З_
local _з_ = sr_popup._з_
local _И_ = sr_popup._И_
local _и_ = sr_popup._и_
local _Ј_ = sr_popup._Ј_
local _ј_ = sr_popup._ј_
local _К_ = sr_popup._К_
local _к_ = sr_popup._к_
local _Л_ = sr_popup._Л_
local _л_ = sr_popup._л_
local _Љ_ = sr_popup._Љ_
local _љ_ = sr_popup._љ_
local _М_ = sr_popup._М_
local _м_ = sr_popup._м_
local _Н_ = sr_popup._Н_
local _н_ = sr_popup._н_
local _Њ_ = sr_popup._Њ_
local _њ_ = sr_popup._њ_
local _О_ = sr_popup._О_
local _о_ = sr_popup._о_
local _П_ = sr_popup._П_
local _п_ = sr_popup._п_
local _Р_ = sr_popup._Р_
local _р_ = sr_popup._р_
local _С_ = sr_popup._С_
local _с_ = sr_popup._с_
local _Т_ = sr_popup._Т_
local _т_ = sr_popup._т_
local _Ћ_ = sr_popup._Ћ_
local _ћ_ = sr_popup._ћ_
local _У_ = sr_popup._У_
local _у_ = sr_popup._у_
local _Ф_ = sr_popup._Ф_
local _ф_ = sr_popup._ф_
local _Х_ = sr_popup._Х_
local _х_ = sr_popup._х_
local _Ц_ = sr_popup._Ц_
local _ц_ = sr_popup._ц_
local _Ч_ = sr_popup._Ч_
local _ч_ = sr_popup._ч_
local _Џ_ = sr_popup._Џ_
local _џ_ = sr_popup._џ_
local _Ш_ = sr_popup._Ш_
local _ш_ = sr_popup._ш_
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
            { _Љ_, _љ_, dif, "?", },
            { _Њ_, _њ_, int, "¿", },
            { _Е_, _е_, mth, "~", },
            { _Р_, _р_, mt2, "\\", },
            { _Т_, _т_, df2, bar, },
            { _З_, _з_, sl2, sla, },
            { _У_, _у_, _4s, _4n, },
            { _И_, _и_, _5s, _5n, },
            { _О_, _о_, _6s, _6n, },
            { _П_, _п_, pl2, pls, },
            { _Ш_, _ш_, bul, bu2, },
        },
        -- Third row
        { --   R    r    S    s
            { _А_, _а_, ls2, ls1, },
            { _С_, _с_, mr2, mr1, },
            { _Д_, _д_, dgr, "(", },
            { _Ф_, _ф_, tpg, ")", },
            { _Г_, _г_, hs2, hsh, },
            { _Х_, _х_, pd2, pdc, },
            { _Ј_, _ј_, _1s, _1n, },
            { _К_, _к_, _2s, _2n, },
            { _Л_, _л_, _3s, _3n, },
            { _Ч_, _ч_, cl1, cl2, },
            { _Ћ_, _ћ_, cl3, cl4, },
        },
        -- Fourth row
        { --   R    r    S    s
            { label = "",        }, -- Shift
            { _Џ_, _џ_, prm, "{", },
            { _Ц_, _ц_, "°", "}", },
            { _В_, _в_, "«", "[", },
            { _Б_, _б_, "»", "]", },
            { _Н_, _н_, _0s, _0n, },
            { _М_, _м_, "↑", "↑", },
            { _Ђ_, _ђ_, "↓", "↓", },
            { _Ж_, _ж_, _0s, _0n, },
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
