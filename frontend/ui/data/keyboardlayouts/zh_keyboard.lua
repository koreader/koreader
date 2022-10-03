--[[--

Chinese stroke-based input method for Lua/KOReader.

Uses five basic strokes plus a wildcard stroke to input Chinese characters.
Supports both simplified and traditional.
Characters hardcoded on keys are uniform, no translation needed.
In-place candidates can be turned off in keyboard settings.
A Separation key 分隔 is used to finish inputting a character.
A Switch key 换字 is used to iterate candidates.
Stroke-wise deletion (input not finished) mapped to the default Del key.
Character-wise deletion mapped to north of Separation key.

rf. https://en.wikipedia.org/wiki/Stroke_count_method

--]]

local IME = require("frontend/ui/data/keyboardlayouts/generic_ime")
local util = require("util")
local JA = require("ui/data/keyboardlayouts/ja_keyboard_keys")
local _ = require("gettext")

local SHOW_CANDI_KEY = "keyboard_chinese_stroke_show_candidates"
local s_3 = { alt_label = "%°#", "3", west = "%", north = "°", east = "#" }
local s_8 = { alt_label = "&-/", "8", west = "&", north = "-", east = "/" }
local comma_popup = { "，",
    north = "；",
    alt_label = "；",
    northeast = "（",
    northwest = "“",
    east = "《",
    west = "？",
    south = ",",
    southeast = "【",
    southwest = "「",
    "{",
    "[",
    ";",
}
local period_popup = {  "。",
    north = "：",
    alt_label = "：",
    northeast = "）",
    northwest = "”",
    east = "…",
    west = "！",
    south = ".",
    southeast = "】",
    southwest = "」",
    "}",
    "]",
    ":",
}

local H = "H" -- stroke_h 横
local I = "I" -- stroke_s 竖
local J = "J" -- stroke_p 撇
local K = "K" -- stroke_n 捺
local L = "L" -- stroke_z 折
local W = "`" -- wildcard, * is not used because it can be input from symbols

local genMenuItems = function(self)
    return {
        {
            text = _("Show character candidates"),
            checked_func = function()
                return G_reader_settings:nilOrTrue(SHOW_CANDI_KEY)
            end,
            callback = function()
                G_reader_settings:flipNilOrTrue(SHOW_CANDI_KEY)
            end,
        },
    }
end

local code_map = require("frontend/ui/data/keyboardlayouts/zh_stroke_data")
local ime = IME:new{
    code_map = code_map,
    key_map = {
        ["㇐"] = H,
        ["㇑"] = I,
        ["㇒"] = J,
        ["㇏"] = K,
        ["㇜"] = L,
        [W] = W, -- wildcard
    },
    iter_map = {
        H = I,
        I = J,
        J = K,
        K = L,
        L = H,
    },
    iter_map_last_key = L,
    show_candi_callback = function()
        return  G_reader_settings:nilOrTrue(SHOW_CANDI_KEY)
    end,
    W = W -- has wildcard function
}

local wrappedAddChars = function(inputbox, char)
    ime:wrappedAddChars(inputbox, char)
end

local function seperate(inputbox)
    ime:separate(inputbox)
end

local function wrappedDelChar(inputbox)
    ime:wrappedDelChar(inputbox)
end

local function clear_stack()
    ime:clear_stack()
end

local wrapInputBox = function(inputbox)
    if inputbox._zh_stroke_wrapped == nil then
        inputbox._zh_stroke_wrapped = true
        local wrappers = {}

        -- Wrap all of the navigation and non-single-character-input keys with
        -- a callback to clear the tap window, but pass through to the
        -- original function.

        -- -- Delete text.
        table.insert(wrappers, util.wrapMethod(inputbox, "delChar",          wrappedDelChar,   nil))
        table.insert(wrappers, util.wrapMethod(inputbox, "delToStartOfLine", nil, clear_stack))
        table.insert(wrappers, util.wrapMethod(inputbox, "clear",            nil, clear_stack))
        -- -- Navigation.
        table.insert(wrappers, util.wrapMethod(inputbox, "leftChar",  nil, seperate))
        table.insert(wrappers, util.wrapMethod(inputbox, "rightChar", nil, seperate))
        table.insert(wrappers, util.wrapMethod(inputbox, "upLine",    nil, seperate))
        table.insert(wrappers, util.wrapMethod(inputbox, "downLine",  nil, seperate))
        -- -- Move to other input box.
        table.insert(wrappers, util.wrapMethod(inputbox, "unfocus",         nil, seperate))
        table.insert(wrappers, util.wrapMethod(inputbox, "onCloseKeyboard", nil, seperate))
        -- -- Gestures to move cursor.
        table.insert(wrappers, util.wrapMethod(inputbox, "onTapTextBox",    nil, seperate))
        table.insert(wrappers, util.wrapMethod(inputbox, "onHoldTextBox",   nil, seperate))
        table.insert(wrappers, util.wrapMethod(inputbox, "onSwipeTextBox",  nil, seperate))
        -- -- Others
        table.insert(wrappers, util.wrapMethod(inputbox, "onSwitchingKeyboardLayout", nil, seperate))

        -- addChars is the only method we need a more complicated wrapper for.
        table.insert(wrappers, util.wrapMethod(inputbox, "addChars", wrappedAddChars, nil))

        return function()
            if inputbox._zh_stroke_wrapped then
                for _, wrapper in ipairs(wrappers) do
                    wrapper:revert()
                end
                inputbox._zh_stroke_wrapped = nil
            end
        end
    end
end

return {
    min_layer = 1,
    max_layer = 2,
    shiftmode_keys = {["123"] = false},
    symbolmode_keys = {["Sym"] = false},
    utf8mode_keys = {["🌐"] = true},
    umlautmode_keys = {["Äéß"] = false},  -- Disabled 'umlaut' keys
    keys = {
        -- first row
        {
            { label = "123" },
            { JA.s_1, { label = "一", "㇐", north="——"} },
            { JA.s_2, { label = "丨", "㇑"} },
            { s_3,    { label = "丿", "㇒"} },
            { label = "", bold = false } -- backspace
        },
        -- second row
        {
            { label = "←" },
            { JA.s_4, { label = "丶", "㇏", north="、" } },
            { JA.s_5, { label = "𠃋", "㇜" } },
            { JA.s_6, { ime.separator, north=ime.local_del, alt_label=ime.local_del } },
            { label = "→" },
        },
        -- third row
        {
            { label = "↑" },
            { JA.s_7, ime.switch_char },
            { s_8,    comma_popup },
            { JA.s_9, period_popup },
            { label = "↓" },
        },
        -- fourth row
        {
            { label = "🌐" },
            { label = "空格",  " ", " ", width = 2.0 },
            { JA.s_0, { label = "＊", W } },
            { label = "⮠", "\n", "\n", bold = true }, -- return
        },
    },

    wrapInputBox = wrapInputBox,
    genMenuItems = genMenuItems,
}
