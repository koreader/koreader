local IME = require("ui/data/keyboardlayouts/generic_ime")
local util = require("util")
local _ = require("gettext")

-- Start with the english keyboard layout
local py_keyboard = dofile("frontend/ui/data/keyboardlayouts/en_keyboard.lua")
local SETTING_NAME = "keyboard_chinese_pinyin_settings"

local code_map = dofile("frontend/ui/data/keyboardlayouts/zh_pinyin_data.lua")
local settings = G_reader_settings:readSetting(SETTING_NAME, {show_candi=true})
local active_inputbox
local ime = IME:new {
    code_map = code_map,
    partial_separators = {" "},
    show_candi_callback = function()
        local keyboard = active_inputbox and active_inputbox.keyboard
        return settings.show_candi and not (keyboard and keyboard.candidate_row)
    end,
    candidate_callback = function(inputbox, candidates, index)
        local keyboard = inputbox and inputbox.keyboard
        if keyboard and keyboard.setCandidates then
            local selected_index
            if #candidates > 0 then
                selected_index = ((index or 1) - 1) % #candidates + 1
            end
            local page = inputbox._pinyin_candidate_page or 1
            if not inputbox._pinyin_manual_page and selected_index then
                page = math.ceil(selected_index / keyboard.candidate_page_size)
                inputbox._pinyin_candidate_page = page
            end
            inputbox._pinyin_manual_page = false
            keyboard:setCandidates(settings.show_candi and candidates or {}, page, selected_index)
        end
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
                if active_inputbox then
                    ime:notifyCandidates(active_inputbox)
                end
            end
        }
    }
end

local wrappedAddChars = function(inputbox, char)
    if char == "\1candidate_prev" then
        inputbox._pinyin_candidate_page = math.max(1, (inputbox._pinyin_candidate_page or 1) - 1)
        inputbox._pinyin_manual_page = true
        ime:notifyCandidates(inputbox)
        return
    elseif char == "\1candidate_next" then
        inputbox._pinyin_candidate_page = (inputbox._pinyin_candidate_page or 1) + 1
        inputbox._pinyin_manual_page = true
        ime:notifyCandidates(inputbox)
        return
    end
    local candidate_index = type(char) == "string" and tonumber(char:match("^\1candidate_(%d+)$"))
    if candidate_index then
        if ime:selectCandidate(inputbox, candidate_index) then
            inputbox._pinyin_candidate_page = 1
        end
        return
    end
    inputbox._pinyin_candidate_page = 1
    inputbox._pinyin_manual_page = false
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
    inputbox._pinyin_candidate_page = 1
    inputbox._pinyin_manual_page = false
    ime:wrappedDelChar(inputbox)
end

local function clear_stack()
    ime:clear_stack()
    if active_inputbox then
        active_inputbox._pinyin_candidate_page = 1
        active_inputbox._pinyin_manual_page = false
        ime:notifyCandidates(active_inputbox)
    end
end

local wrapInputBox = function(inputbox)
    if inputbox._py_wrapped == nil then
        inputbox._py_wrapped = true
        inputbox._pinyin_candidate_page = 1
        inputbox._pinyin_manual_page = false
        active_inputbox = inputbox
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
                inputbox._pinyin_candidate_page = nil
                inputbox._pinyin_manual_page = nil
                if active_inputbox == inputbox then
                    active_inputbox = nil
                end
            end
        end
    end
end

py_keyboard.wrapInputBox = wrapInputBox
py_keyboard.genMenuItems = genMenuItems
py_keyboard.candidate_row = true
py_keyboard.candidate_page_size = 6
py_keyboard.keys[5][4].label = "空格"
return py_keyboard
