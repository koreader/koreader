--[[--

Chinese stroke-based input method for Lua/KOReader.

Five basic strokes plus a wildcard stroke to input Chinese characters.
Supporting both simplified and traditional. 
Characters hardcoded on keys are uniform, no translation needed.
In-place candidates can be turned off in keyboard settings.
A Separation key 分隔 is used to finish inputting a character.
A Switch key 换字 is used to iterate candidates.
Stroke-wise deletion (input not finished) mapped to the default Del key.
Character-wise deletion mapped to north of Separation key.

rf. https://en.wikipedia.org/wiki/Stroke_count_method

--]]

local logger = require("logger")
local strokeMap = require("ui/data/keyboardlayouts/zh_keyboard_data")
local util = require("util")
local JA = require("ui/data/keyboardlayouts/ja_keyboard_keys")
local _ = require("gettext")

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

local switch_char = "换字"
local seperator = "分隔"
local local_del = ""

local H = "H" -- stroke_h 横
local I = "I" -- stroke_s 竖
local J = "J" -- stroke_p 撇
local K = "K" -- stroke_n 捺
local L = "L" -- stroke_z 折
local W = "`" -- wildcard, * is not used because it can be input from symbols

local ime_strokes = { -- keep input strokes by character for stepped deletion
    { strokes="", char="", index=1, value={} }
}

function table.binarysearch( tbl,value,fcompval,reversed )
    if not fcompval then return end
    local iStart,iEnd,iMid = 1,#tbl,0
    while iStart <= iEnd do
        iMid = math.floor( (iStart+iEnd)/2 )
        local value2 = fcompval( tbl[iMid] )
        if value == value2 then
            iEnd = iMid - 1
            while iStart <= iEnd do
                iMid = math.floor( (iStart+iEnd)/2 )
                value2 = fcompval( tbl[iMid] )
                if value2 == value then
                    if fcompval( tbl[iMid-1] ) ~= value then
                        return iMid
                    else
                        iEnd = iMid - 1
                    end
                else
                    if fcompval( tbl[iMid+1] ) == value then
                        return iMid + 1
                    else
                        iStart = iMid + 2
                    end
                end
            end
            return iMid
        elseif ( reversed and value2 < value ) or ( not reversed and value2 > value ) then
            iEnd = iMid - 1
        else
            iStart = iMid + 1
        end
    end
end

-- local helper table and functions
local sortedStrokeKeys = {}
for k,_ in pairs(strokeMap) do
    table.insert(sortedStrokeKeys, k)
end
table.sort(sortedStrokeKeys)

local function getShowCandidates()
    return G_reader_settings:nilOrTrue("keyboard_chinese_stroke_show_candidates")
end

local function searchStartWith(key)
    local result = table.binarysearch(sortedStrokeKeys, key, function(v) return string.sub(v or "", 1, #key) end)
    if result then
        local value = strokeMap[sortedStrokeKeys[result]]
        if value then
            logger.err("zh_kbd: got search result starting with", key, ":", value)
        end
        if type(value) == "string" then
            return { value }
        end
        return value
    end
end

local function getValueFromMap(key)
    local value = strokeMap[key]
    if value then
        logger.err("zh_kbd: got value from map with", key, ":", value)
    end
    if type(value) == "string" then
        return { value }
    end
    return value
end

local function stringReplaceAt(str, pos, r)
    return str:sub(1, pos-1) .. r .. str:sub(pos+1)
end


---- helper class
local StrokeHelper = {
    map = { -- input to stroke
        ["㇐"] = H,
        ["㇑"] = I,
        ["㇒"] = J,
        ["㇏"] = K,
        ["㇜"] = L,
        [W] = W, -- wildcard
    },
    iterMap = { -- next stroke
        H = I,
        I = J,
        J = K,
        K = L,
        L = H
    },
    lastKey = "", -- strokes
    lastIndex = 0, -- switch char
}

function StrokeHelper:getValue(key)
    return getValueFromMap(key) or searchStartWith(key) or {}
end

function StrokeHelper:resetStatus()
    self.lastIndex = 0
    self.lastKey = ""
end

function StrokeHelper:getCharWithWildcard(strokes, from_reset)
    logger.err("zh_kdb: getCharWithWildcard:", strokes, "lastKey:", self.lastKey)
    for i=#strokes, 1, -1 do
        if strokes:sub(i, i) == W then
            if self.lastKey:sub(i, i) == L then
                self.lastKey = stringReplaceAt(self.lastKey, i, H)
            else
                self.lastKey = stringReplaceAt(self.lastKey, i, self.iterMap[self.lastKey:sub(i, i)])
                self.lastValue = self:getValue(self.lastKey)
                if #self.lastValue > 0 then
                    logger.err("zh_kbd: got chars with wildchard for key", self.lastKey, ":", self.lastValue)
                    return self.lastValue
                end
                return self:getCharWithWildcard(strokes, from_reset)
            end
        end
    end
    -- all wildcard reset to H
    self.lastValue = self:getValue(self.lastKey)
    if #self.lastValue > 0 then
        logger.err("zh_kbd: got chars with wildchard for key", self.lastKey, ":", self.lastValue)
        return self.lastValue
    elseif not from_reset then
        return self:getCharWithWildcard(strokes, true)
    end
end

function StrokeHelper:getChars(strokes)
    logger.err("zh_kbd: getChars", strokes)

    local wildcard_count = select(2, string.gsub(strokes, W, ""))
    if wildcard_count > 5 then
        -- we limit the wildcard count to 5 due to performance conserns
        return
    elseif wildcard_count ~= 0 then
        if #strokes == #self.lastKey then -- only index change, no new stroke
            return self:getCharWithWildcard(strokes)
        else
            self:resetStatus()
            self.lastKey = strokes:gsub(W, L)
            return self:getCharWithWildcard(strokes)
        end
    end

    -- no wildcard
    return getValueFromMap(strokes) or searchStartWith(strokes)
end

-- Keyboard functions
local hint_char_count = 0

local function resetInputStatus()
    ime_strokes = {
        { strokes="", char="", index=1, value={} }
    }
    hint_char_count = 0
    logger.err("zh_kbd: reset", hint_char_count)
    StrokeHelper:resetStatus()
end

local function delHintChars(inputbox)
    logger.err("zh_kbd: delete hint chars of count", hint_char_count)
    for i=1, hint_char_count do
        inputbox.delChar:raw_method_call()
    end
end

local function getHintChars()
    hint_char_count = 0
    local hint_chars = ""
    for i=1, #ime_strokes do
        hint_chars = hint_chars .. ime_strokes[i].char
        if ime_strokes[i].char ~= "" then
            hint_char_count = hint_char_count + 1
        end
    end
    local ime = ime_strokes[#ime_strokes]
    if getShowCandidates() and #ime.value ~= 0 and ( #ime.value > 1 or ime.strokes:find(W) ) then
        hint_chars = hint_chars .. "["
        if #ime.value > 1 then
            for _, char in ipairs(ime.value) do
                hint_chars = hint_chars .. char
            end
            hint_char_count = hint_char_count + #ime.value
        end
        if ime.strokes:find(W) then
            hint_chars = hint_chars .. "…"
            hint_char_count = hint_char_count + 1
        end
        hint_chars = hint_chars .. "]"
        hint_char_count = hint_char_count + 2
    end
    logger.err("zh_kbd: got hint chars:", hint_chars, "with count", hint_char_count)
    return hint_chars
end

local function refreshHintChars(inpuxbox)
    delHintChars(inpuxbox)
    inpuxbox.addChars:raw_method_call(getHintChars())
end

local wrappedSeparate = function(inputbox)
    local ime = ime_strokes[#ime_strokes]
    if getShowCandidates() and ( #ime.value > 1 or ime.strokes:find(W) ) then
        ime.value = {}
        refreshHintChars(inputbox)
    end
    resetInputStatus()
end

local wrappedDelChar = function(inputbox)
    -- stepped deletion
    local ime = ime_strokes[#ime_strokes]
    if #ime.strokes > 1 then
        -- last char has over one input strokes
        ime.strokes = string.sub(ime.strokes, 1, -2)
        ime.index = 1
        ime.value = StrokeHelper:getChars(ime.strokes)
        ime.char = ime.value[1]
        refreshHintChars(inputbox)
    elseif #ime_strokes > 1 then
        -- over one chars, last char has only one stroke
        ime_strokes[#ime_strokes] = nil
        refreshHintChars(inputbox)
    elseif #ime.strokes == 1 then
        -- one char with one stroke
        delHintChars(inputbox)
        resetInputStatus()
    else
        inputbox.delChar:raw_method_call()
    end
end

local wrappedAddChars = function(inputbox, char)
    local ime = ime_strokes[#ime_strokes]
    if char == switch_char then
        ime.index = ime.index + 1
        if ime.strokes:find(W) then
            if #ime.value == 0 then
                return
            elseif ime.index - StrokeHelper.lastIndex > #ime.value then
                StrokeHelper.lastIndex = StrokeHelper.lastIndex + #ime.value
                ime.value = StrokeHelper:getChars(ime.strokes)
                ime.char = ime.value[1]
            else
                ime.char = ime.value[ime.index - StrokeHelper.lastIndex]
            end
        elseif #ime.value > 1 then
            local remainder = ime.index % #ime.value
            ime.char = ime.value[remainder==0 and #ime.value or remainder]
        else
            return
        end
        refreshHintChars(inputbox)
    elseif char == seperator then
        ime.value = {}
        refreshHintChars(inputbox)
        resetInputStatus()
        return
    elseif char == local_del then
        if #ime.strokes > 0 then
            ime.value = {}
            ime.char = ""
            refreshHintChars(inputbox)
            resetInputStatus()
        else
            inputbox.delChar:raw_method_call()
        end
    else
        local stroke = StrokeHelper.map[char]
        if stroke then
            ime.index = 1
            StrokeHelper:resetStatus()
            local new_value = StrokeHelper:getChars(ime.strokes..stroke)
            if new_value and #new_value > 0 then
                ime.strokes = ime.strokes .. stroke
                ime.char = new_value[1]
                ime.value = new_value
                refreshHintChars(inputbox)
            else
                new_value = StrokeHelper:getChars(stroke) or {} -- single stroke
                table.insert(ime_strokes, {strokes=stroke, index=1, char=new_value[1], value=new_value})
                refreshHintChars(inputbox)
            end
        else
            if #ime.value > 1 then
                ime.value = {}
                refreshHintChars(inputbox)
            end
            resetInputStatus()
            inputbox.addChars:raw_method_call(char)
        end
    end
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
        table.insert(wrappers, util.wrapMethod(inputbox, "delToStartOfLine", nil, resetInputStatus))
        table.insert(wrappers, util.wrapMethod(inputbox, "clear",            nil, resetInputStatus))
        -- -- Navigation.
        table.insert(wrappers, util.wrapMethod(inputbox, "leftChar",  nil, wrappedSeparate))
        table.insert(wrappers, util.wrapMethod(inputbox, "rightChar", nil, wrappedSeparate))
        table.insert(wrappers, util.wrapMethod(inputbox, "upLine",    nil, wrappedSeparate))
        table.insert(wrappers, util.wrapMethod(inputbox, "downLine",  nil, wrappedSeparate))
        -- -- Move to other input box.
        table.insert(wrappers, util.wrapMethod(inputbox, "unfocus",         nil, wrappedSeparate))
        table.insert(wrappers, util.wrapMethod(inputbox, "onCloseKeyboard", nil, wrappedSeparate))        
        -- -- Gestures to move cursor.
        table.insert(wrappers, util.wrapMethod(inputbox, "onTapTextBox",   nil, wrappedSeparate))
        table.insert(wrappers, util.wrapMethod(inputbox, "onHoldTextBox",  nil, wrappedSeparate))
        table.insert(wrappers, util.wrapMethod(inputbox, "onSwipeTextBox", nil, wrappedSeparate))
        -- -- Others
        table.insert(wrappers, util.wrapMethod(inputbox, "utf8modeChar",   nil, wrappedSeparate))

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

local genMenuItems = function(self)
    return {
        {
            text = _("Show character candidates"),
            checked_func = function()
                return G_reader_settings:nilOrTrue("keyboard_chinese_stroke_show_candidates")
            end,
            callback = function()
                G_reader_settings:flipNilOrTrue("keyboard_chinese_stroke_show_candidates")
            end,
        },
    }
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
            { JA.s_1, { label = "一", "㇐"} },
            { JA.s_2, { label = "丨", "㇑"} },
            { s_3,    { label = "丿", "㇒"} },
            { label = "", bold = false } -- backspace
        },
        -- second row
        {
            { label = "←" },
            { JA.s_4, { label = "丶", "㇏" } },
            { JA.s_5, { label = "𠃋", "㇜" } },
            { JA.s_6, { seperator, north=local_del, alt_label=local_del } },
            { label = "→" },
        },
        -- third row
        {
            { label = "↑" },
            { JA.s_7, { label = "＊", W } },
            { s_8,    comma_popup },
            { JA.s_9, period_popup },
            { label = "↓" },
        },
        -- fourth row
        {
            { label = "🌐" },
            { label = "空格",  " ", " ", width = 2.0 },
            { JA.s_0, switch_char },
            { label = "⮠", "\n", "\n", bold = true }, -- return
        },
    },

    wrapInputBox = wrapInputBox,
    genMenuItems = genMenuItems,
}
