local IME = require("ui/data/keyboardlayouts/generic_ime")
local util = require("util")
local _ = require("gettext")

-- Start with the english keyboard layout
local py_keyboard = dofile("frontend/ui/data/keyboardlayouts/en_keyboard.lua")
local SETTING_NAME = "keyboard_chinese_pinyin_settings"

local code_map = dofile("frontend/ui/data/keyboardlayouts/zh_pinyin_data.lua")
local settings = G_reader_settings:readSetting(SETTING_NAME, {show_candi=true})
local ime = IME:new {
    code_map = code_map,
    partial_separators = {" "},
    show_candi_callback = function()
        return settings.show_candi
    end,
    switch_char = "→",
    switch_char_prev = "←",
}

py_keyboard.keys[4][3][2].alt_label = nil
py_keyboard.keys[4][3][1].alt_label = nil
py_keyboard.keys[3][10][2] = {
    "，",
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
    ";"
}

py_keyboard.keys[5][3][2] = {
    "。",
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
    ":"
}
py_keyboard.keys[1][2][3] = { alt_label = "「", north = "「", "‘" }
py_keyboard.keys[1][3][3] = { alt_label = "」", north = "」", "’" }
py_keyboard.keys[1][1][4] = { alt_label = "!", north = "!", "！"}
py_keyboard.keys[2][1][4] = { alt_label = "?", north = "?", "？"}
py_keyboard.keys[1][2][4] = "、"
py_keyboard.keys[2][2][4] = "——"
py_keyboard.keys[1][4][3] = { alt_label = "『", north = "『", "“" }
py_keyboard.keys[1][5][3] = { alt_label = "』", north = "』", "”" }
py_keyboard.keys[1][4][4] = { alt_label = "¥", north = "¥", "_" }
py_keyboard.keys[3][3][4] = "（"
py_keyboard.keys[3][4][4] = "）"
py_keyboard.keys[4][4][3] = "《"
py_keyboard.keys[4][5][3] = "》"

local genMenuItems = function(self)
    return {
        {
            text = _("Show character candidates"),
            checked_func = function()
                return settings.show_candi
            end,
            callback = function()
                settings.show_candi = not settings.show_candi
                G_reader_settings:saveSetting(SETTING_NAME, settings)
            end
        }
    }
end

local wrappedAddChars = function(inputbox, char)
    ime:wrappedAddChars(inputbox, char)
end

local wrappedRightChar = function(inputbox)
    if ime:hasCandidates() then
        ime:wrappedAddChars(inputbox, "→")
    else
        ime:separate(inputbox)
        inputbox.rightChar:raw_method_call()
    end
end

local wrappedLeftChar = function(inputbox)
    if ime:hasCandidates() then
        ime:wrappedAddChars(inputbox, "←")
    else
        ime:separate(inputbox)
        inputbox.leftChar:raw_method_call()
    end
end

local function separate(inputbox)
    ime:separate(inputbox)
end

local function wrappedDelChar(inputbox)
    ime:wrappedDelChar(inputbox)
end

local function clear_stack()
    ime:clear_stack()
end

local wrapInputBox = function(inputbox)
    if inputbox._py_wrapped == nil then
        inputbox._py_wrapped = true
        local wrappers = {}

        -- Wrap all of the navigation and non-single-character-input keys with
        -- a callback to finish (separate) the input status, but pass through to the
        -- original function.

        -- -- Delete text.
        table.insert(wrappers, util.wrapMethod(inputbox, "delChar", wrappedDelChar, nil))
        table.insert(wrappers, util.wrapMethod(inputbox, "delToStartOfLine", nil, clear_stack))
        table.insert(wrappers, util.wrapMethod(inputbox, "clear", nil, clear_stack))
        -- -- Navigation.
        table.insert(wrappers, util.wrapMethod(inputbox, "upLine", nil, separate))
        table.insert(wrappers, util.wrapMethod(inputbox, "downLine", nil, separate))
        -- -- Move to other input box.
        table.insert(wrappers, util.wrapMethod(inputbox, "unfocus", nil, separate))
        table.insert(wrappers, util.wrapMethod(inputbox, "onCloseKeyboard", nil, separate))
        -- -- Gestures to move cursor.
        table.insert(wrappers, util.wrapMethod(inputbox, "onTapTextBox", nil, separate))
        table.insert(wrappers, util.wrapMethod(inputbox, "onHoldTextBox", nil, separate))
        table.insert(wrappers, util.wrapMethod(inputbox, "onSwipeTextBox", nil, separate))

        table.insert(wrappers, util.wrapMethod(inputbox, "addChars", wrappedAddChars, nil))
        table.insert(wrappers, util.wrapMethod(inputbox, "leftChar", wrappedLeftChar, nil))
        table.insert(wrappers, util.wrapMethod(inputbox, "rightChar", wrappedRightChar, nil))

        return function()
            if inputbox._py_wrapped then
                for _, wrapper in ipairs(wrappers) do
                    wrapper:revert()
                end
                inputbox._py_wrapped = nil
            end
        end
    end
end

py_keyboard.wrapInputBox = wrapInputBox
py_keyboard.genMenuItems = genMenuItems
py_keyboard.keys[5][4].label = "空格"
return py_keyboard
