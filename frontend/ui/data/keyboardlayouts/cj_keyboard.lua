--[[--

RIME-style Cangjie (倉頡) input method for KOReader.

Features:
1. Shows Cangjie radicals after cursor while typing  e.g. [手日]
2. No auto-commit; Space confirms the first/highlighted candidate
3. Candidates shown after the radical code  e.g. [手日*1明2冐3暌]
4. Number keys 1-9 select candidates directly
5. Continuous input: after confirming a character the next code starts immediately

--]]

local CangjieIME = require("ui/data/keyboardlayouts/new_cangjie_ime")
local util = require("util")
local _ = require("gettext")

-- Start with the english keyboard layout
local cj_keyboard = dofile("frontend/ui/data/keyboardlayouts/en_keyboard.lua")
local SETTING_NAME = "keyboard_cangjie_settings"

local code_map = dofile("frontend/ui/data/keyboardlayouts/cj_data.lua")
local settings = G_reader_settings:readSetting(SETTING_NAME, {show_candi=true})

-- All 25 Cangjie keys (A-Y; Z is not a standard cangjie key)
local CJ_KEY_MAP = {
    A="A", B="B", C="C", D="D", E="E", F="F", G="G", H="H", I="I",
    J="J", K="K", L="L", M="M", N="N", O="O", P="P", Q="Q", R="R",
    S="S", T="T", U="U", V="V", W="W", X="X", Y="Y",
}

local ime = CangjieIME:new{
    code_map = code_map,
    key_map = CJ_KEY_MAP,
    show_candidates = settings.show_candi,
}

-- Cangjie radical labels for QWERTY keys (standard Cangjie 5th-generation mapping)
-- Row 2: Q=手 W=田 E=水 R=口 T=廿 Y=卜 U=山 I=戈 O=人 P=心
-- Row 3: A=日 S=尸 D=木 F=火 G=土 H=竹 J=十 K=大 L=中
-- Row 4: Z=重 X=難 C=金 V=女 B=月 N=弓 M=一

-- Override layer 2 (cangjie layer) keys with radical labels
-- Row 2 (keys[2]): Q W E R T Y U I O P
cj_keyboard.keys[2][1][2] = { label = "手", "Q", alt_label = "Q" }
cj_keyboard.keys[2][2][2] = { label = "田", "W", alt_label = "W" }
cj_keyboard.keys[2][3][2] = { label = "水", "E", alt_label = "E" }
cj_keyboard.keys[2][4][2] = { label = "口", "R", alt_label = "R" }
cj_keyboard.keys[2][5][2] = { label = "廿", "T", alt_label = "T" }
cj_keyboard.keys[2][6][2] = { label = "卜", "Y", alt_label = "Y" }
cj_keyboard.keys[2][7][2] = { label = "山", "U", alt_label = "U" }
cj_keyboard.keys[2][8][2] = { label = "戈", "I", alt_label = "I" }
cj_keyboard.keys[2][9][2] = { label = "人", "O", alt_label = "O" }
cj_keyboard.keys[2][10][2] = { label = "心", "P", alt_label = "P" }

-- Row 3 (keys[3]): A S D F G H J K L
cj_keyboard.keys[3][1][2] = { label = "日", "A", alt_label = "A" }
cj_keyboard.keys[3][2][2] = { label = "尸", "S", alt_label = "S" }
cj_keyboard.keys[3][3][2] = { label = "木", "D", alt_label = "D" }
cj_keyboard.keys[3][4][2] = { label = "火", "F", alt_label = "F" }
cj_keyboard.keys[3][5][2] = { label = "土", "G", alt_label = "G" }
cj_keyboard.keys[3][6][2] = { label = "竹", "H", alt_label = "H" }
cj_keyboard.keys[3][7][2] = { label = "十", "J", alt_label = "J" }
cj_keyboard.keys[3][8][2] = { label = "大", "K", alt_label = "K" }
cj_keyboard.keys[3][9][2] = { label = "中", "L", alt_label = "L" }

-- Row 4 (keys[4]): Z X C V B N M
cj_keyboard.keys[4][2][2] = { label = "重", "Z", alt_label = "Z" }
cj_keyboard.keys[4][3][2] = { label = "難", "X", alt_label = "X" }
cj_keyboard.keys[4][4][2] = { label = "金", "C", alt_label = "C" }
cj_keyboard.keys[4][5][2] = { label = "女", "V", alt_label = "V" }
cj_keyboard.keys[4][6][2] = { label = "月", "B", alt_label = "B" }
cj_keyboard.keys[4][7][2] = { label = "弓", "N", alt_label = "N" }
cj_keyboard.keys[4][8][2] = { label = "一", "M", alt_label = "M" }

-- Chinese punctuation overrides on the , and . keys
cj_keyboard.keys[3][10][2] = {
    "、",
    north = "；",
    alt_label = "；",
    northeast = "（",
    northwest = "\u{201c}",
    east = "《",
    southeast = "「",
    south = "、",
    southwest = "」",
    west = "》",
}
cj_keyboard.keys[3][10][3] = {
    "。",
    north = "：",
    alt_label = "：",
    northeast = "）",
    northwest = "\u{201d}",
    east = "〉",
    southeast = "『",
    south = "·",
    southwest = "』",
    west = "〈",
}

-- ── Wrapped input handlers ─────────────────────────────────────────────────

-- All key presses are routed through the IME
local function wrappedAddChars(inputbox, char, orig_char)
    ime:handle_input(inputbox, char)
end

-- Backspace: pop last radical, or pass through when no preedit
local function wrappedDelChar(inputbox)
    ime:handle_del(inputbox)
end

-- Arrow keys: cycle candidates while composing, otherwise move cursor normally
local function wrappedRightChar(inputbox)
    if ime.buf ~= "" then
        ime:handle_next_cand(inputbox)
    else
        inputbox.rightChar:raw_method_call()
    end
end

local function wrappedLeftChar(inputbox)
    if ime.buf ~= "" then
        ime:handle_prev_cand(inputbox)
    else
        inputbox.leftChar:raw_method_call()
    end
end

-- Discard current preedit on navigation (cursor moved externally)
local function separate(inputbox)
    ime:separate(inputbox)
end

local function clear_stack()
    ime:clear_stack()
end

-- ── wrapInputBox ───────────────────────────────────────────────────────────
-- Called by VirtualKeyboard when this keyboard layout is activated.
-- Returns an unwrap closure that restores the original methods.

local function wrapInputBox(inputbox)
    if inputbox._cj_wrapped then return end
    inputbox._cj_wrapped = true

    ime:clear()

    local wrappers = {}

    table.insert(wrappers, util.wrapMethod(inputbox, "addChars",         wrappedAddChars,  nil))
    table.insert(wrappers, util.wrapMethod(inputbox, "delChar",          wrappedDelChar,   nil))
    table.insert(wrappers, util.wrapMethod(inputbox, "rightChar",        wrappedRightChar, nil))
    table.insert(wrappers, util.wrapMethod(inputbox, "leftChar",         wrappedLeftChar,  nil))

    -- Flush preedit on any event that repositions the cursor
    table.insert(wrappers, util.wrapMethod(inputbox, "delToStartOfLine", nil, separate))
    table.insert(wrappers, util.wrapMethod(inputbox, "clear",            nil, clear_stack))
    table.insert(wrappers, util.wrapMethod(inputbox, "upLine",           nil, separate))
    table.insert(wrappers, util.wrapMethod(inputbox, "downLine",         nil, separate))
    table.insert(wrappers, util.wrapMethod(inputbox, "onTapTextBox",     nil, separate))
    table.insert(wrappers, util.wrapMethod(inputbox, "onHoldTextBox",    nil, separate))
    table.insert(wrappers, util.wrapMethod(inputbox, "onSwipeTextBox",   nil, separate))
    table.insert(wrappers, util.wrapMethod(inputbox, "unfocus",          nil, separate))
    table.insert(wrappers, util.wrapMethod(inputbox, "onCloseKeyboard",  nil, separate))

    return function()
        if inputbox._cj_wrapped then
            for _, w in ipairs(wrappers) do
                w:revert()
            end
            inputbox._cj_wrapped = nil
        end
    end
end

cj_keyboard.wrapInputBox = wrapInputBox

-- ── Settings menu ──────────────────────────────────────────────────────────

local function genMenuItems()
    return {
        {
            text = _("Show character candidates"),
            checked_func = function()
                return settings.show_candi
            end,
            callback = function()
                settings.show_candi = not settings.show_candi
                ime.show_candidates = settings.show_candi
            end,
        },
    }
end

cj_keyboard.genMenuItems = genMenuItems

return cj_keyboard
