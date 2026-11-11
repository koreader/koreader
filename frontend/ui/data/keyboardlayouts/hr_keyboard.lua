-- Croatian (hr) keyboard, adapted from en_keyboard.lua.
-- Differences from the English layout:
--   1. Z and Y swapped (QWERTZ).
--   2. Shifted number row is Croatian:  ! " # $ % & / ( ) =
-- Popups follow the displayed character (taken from en_popup.lua); only the
-- north swipe is adapted so swiping up gives the key's other-layer character.
-- "@", "^" and the 10 combining accents (English Shift+2/Shift+6) are kept
-- reachable through free popup slots only (no key moved, no alternative removed).
-- Č Ć Đ Š Ž are on the c, d, s, z letter popups, as in English.

local en_popup = dofile("frontend/ui/data/keyboardlayouts/keypopup/en_popup.lua")
local hr_keyboard = dofile("frontend/ui/data/keyboardlayouts/en_keyboard.lua") -- fresh copy, en is untouched
local keys = hr_keyboard.keys

-- Copy of an English popup with overrides.
local function derive(base, overrides)
    local t = {}
    for k, v in pairs(base or {}) do t[k] = v end
    for k, v in pairs(overrides) do t[k] = v end
    return t
end

-- 1. Swap Z and Y (layers: Shift, normal, Sym+Shift, Sym).
--    Only the letter layers move; the Sym layers stay in their English positions.
local row2_y, row4_z = keys[2][6], keys[4][2]
row2_y[1], row2_y[2], row4_z[1], row4_z[2] = row4_z[1], row4_z[2], row2_y[1], row2_y[2]

-- 2. Croatian shifted number row. Index = column; [1] = Shift layer, [2] = normal layer.
--    Columns 1, 3, 4, 5 (! # $ %) are the same as English and stay unchanged.
-- 2 → '"' : English quote popup (quo) + Croatian „ ” ; ‹ › stay on the Sym quote key.
-- Extras: ' ‚ @  ("@" replaces "`", which stays on the Sym layer, first key).
local _2p = derive(en_popup.quo, { '"', "'", "‚", "@", north = "2", alt_label = "2", south = "„", })
local _2_ = derive(_2p, { [1] = "2", north = '"', alt_label = '"', })
-- 6 → "&" : English "&" popup (_7p).
local _6p = derive(en_popup._7p, { north = "6", alt_label = "6", })
local _6_ = derive(en_popup._7_, { [1] = "6", })
-- 7 → "/" : English slash popup (sla); its north "÷" moves to west; "^" in the free northwest slot.
local _7p = derive(en_popup.sla, { north = "7", alt_label = "7", west = "÷", northwest = "^", })
local _7_ = derive(_7p, { [1] = "7", north = "/", alt_label = "/", })
-- 8 → "(" : English "(" popup (_9p).
local _8p = derive(en_popup._9p, { north = "8", alt_label = "8", })
local _8_ = derive(en_popup._9_, { [1] = "8", })
-- 9 → ")" : English ")" popup (_0p).
local _9p = derive(en_popup._0p, { north = "9", alt_label = "9", })
local _9_ = derive(en_popup._0_, { [1] = "9", })
-- 0 → "=" : English "=" popup (eql); its north "≠" moves to northeast.
local _0p = derive(en_popup.eql, { north = "0", alt_label = "0", northeast = "≠", })
local _0_ = derive(_0p, { [1] = "0", north = "=", alt_label = "=", })

-- "@" also on swipe-down of V/v (free slot; Croatian hardware keyboards use AltGr+V for @).
local row4_v = keys[4][5]
row4_v[1] = derive(row4_v[1], { south = "@", })
row4_v[2] = derive(row4_v[2], { south = "@", })

-- English combining accents (from en_popup._6_; each is { label = "◌x", key = "x" }).
local acc = en_popup._6_ or {}
local acute, grave, circ, tilde = acc.northeast, acc.northwest, acc.east, acc.west
local cedil, diaer, dot = acc.south, acc.southeast, acc.southwest
local macron, caron, ogonek = acc[2], acc[3], acc[4]
-- 7 / "/": S acute, SW grave, SE caron; extras circumflex, tilde, diaeresis.
for _, t in ipairs({ _7p, _7_ }) do
    t.south, t.southwest, t.southeast = acute, grave, caron
    t[2], t[3], t[4] = circ, tilde, diaer
end
-- 0 / "=": E cedilla, SE ogonek; extras dot above, macron.
for _, t in ipairs({ _0p, _0_ }) do
    t.east, t.southeast = cedil, ogonek
    t[2], t[3] = dot, macron
end

local row1 = keys[1]
row1[2][1], row1[2][2] = _2p, _2_
row1[6][1], row1[6][2] = _6p, _6_
row1[7][1], row1[7][2] = _7p, _7_
row1[8][1], row1[8][2] = _8p, _8_
row1[9][1], row1[9][2] = _9p, _9_
row1[10][1], row1[10][2] = _0p, _0_

return hr_keyboard
