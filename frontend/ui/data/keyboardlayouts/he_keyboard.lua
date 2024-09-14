local en_popup = dofile("frontend/ui/data/keyboardlayouts/keypopup/en_popup.lua")
local he_popup = dofile("frontend/ui/data/keyboardlayouts/keypopup/he_popup.lua")
local pco = en_popup.pco
local cop = en_popup.cop
local cse = en_popup.cse
local sec = en_popup.sec
local quo = en_popup.quo
--Hebrew Letters
local aleph = he_popup.aleph
local beis = he_popup.beis
local gimmel = he_popup.gimmel
local daled = he_popup.daled
local hey = he_popup.hey
local vov = he_popup.vov
local zayin = he_popup.zayin
local tes = he_popup.tes
local yud = he_popup.yud
local chof = he_popup.chof
local lamed = he_popup.lamed
local mem = he_popup.mem
local mem_sofis = he_popup.mem_sofis
local nun = he_popup.nun
local samech = he_popup.samech
local ayin = he_popup.ayin
local pey = he_popup.pey
local pey_sofis = he_popup.pey_sofis
local tzadik = he_popup.tzadik
local kuf = he_popup.kuf
local reish = he_popup.reish
local shin = he_popup.shin
local taf = he_popup.taf
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
    shiftmode_keys = {[""] = true},
    symbolmode_keys = { ["⌥"] = true },
    utf8mode_keys = {["🌐"] = true},
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
        {  --  1           2       3       4
            { "׳", "״",       dif, "?", },
            { "֘֘֙֙ ", kuf,       int, "¿", },
            { "֘ ", reish,     mth, "~", },
            { "֗",  aleph,     mt2, "\\", },
            { "֖ ", tes,       df2, bar, },
            { "֕ ", vov,       sl2, sla, },
            { "֔ ", "ן",       _4s, _4n, },
            { "֓ ", mem_sofis, _5s, _5n, },
            { "֒ ", pey,       _6s, _6n, },
            { "֑ ", pey_sofis, pl2, pls, },
        },
        -- Third row
        {  --  1           2       3       4
            { "ּ ", shin,      ls2, ls1, },
            { "ֻ ", daled,     mr2, mr1, },
            { "ִ ", gimmel,    dgr, "(", },
            { "ֹ",  chof,      tpg, ")", },
            { "ְ ", ayin,      hs2, hsh, },
            { "ֵ ", yud,       pd2, pdc, },
            { "ֶ ", "ח",       _1s, _1n, },
            { "ַ ", lamed,     _2s, _2n, },
            { "ָ ", "ך",       _3s, _3n, },
            { sec, cse,       sec, cse, }, -- comma/semicolon with CSS popup block
        },
        -- Fourth row
        {  --  1           2       3       4
            { label = "", width = 1.5, },
            { "׃", zayin, prm, "{", },
            { "׀",    samech, "°", "}", },
            { "ׄ ", beis,      "«", "[", },
            { "ׅ ", hey,       "»", "]", },
            { "־",    nun,    _0s, _0n, },
            { "ֿ ", mem,      "↑", "↑", },
            { "ֽ ", tzadik,   "↓", "↓", },
            { label = "", width = 1.5, },
        },
        -- Fifth row
        {
            { label = "⌥", width = 1.5, bold = true, alt_label = "SYM"}, -- SYM key
            { label = "🌐", },
            { cop, pco, cop, pco, }, -- period/colon with RegEx popup block
            { label = "_", " ", " ", " ", " ", width = 3.0, }, -- Spacebar
            { "←",    taf,      "←",    "←", },
            { "→",    "ץ",      "→",    "→", },
            { label = "⮠", "\n","\n","\n","\n", width = 1.5, }, -- Enter
        },
    },
}
