--[[--
Miscellaneous helper functions for KOReader frontend.
]]

local BaseUtil = require("ffi/util")
local util = {}

--- Strip all punctuations and spaces in a string.
---- @string text the string to be stripped
---- @treturn string stripped text
function util.stripePunctuations(text)
    if not text then return end
    -- strip ASCII punctuation characters around text
    -- and strip any generic punctuation (U+2000 - U+206F) in the text
    return text:gsub("\226[\128-\131][\128-\191]", ''):gsub("^%p+", ''):gsub("%p+$", '')
end

--[[
Lua doesn't have a string.split() function and most of the time
you don't really need it because string.gmatch() is enough.
However string.gmatch() has one significant disadvantage for me:
You can't split a string while matching both the delimited
strings and the delimiters themselves without tracking positions
and substrings. The gsplit function below takes care of
this problem.
Author: Peter Odding
License: MIT/X11
Source: http://snippets.luacode.org/snippets/String_splitting_130
--]]
function util.gsplit(str, pattern, capture)
    pattern = pattern and tostring(pattern) or '%s+'
    if (''):find(pattern) then
        error('pattern matches empty string!', 2)
    end
    return coroutine.wrap(function()
        local index = 1
        repeat
            local first, last = str:find(pattern, index)
            if first and last then
                if index < first then
                    coroutine.yield(str:sub(index, first - 1))
                end
                if capture then
                    coroutine.yield(str:sub(first, last))
                end
                index = last + 1
            else
                if index <= #str then
                    coroutine.yield(str:sub(index))
                end
                break
            end
        until index > #str
    end)
end

-- https://gist.github.com/jesseadams/791673
function util.secondsToClock(seconds, withoutSeconds)
    seconds = tonumber(seconds)
    if seconds == 0 or seconds ~= seconds then
        if withoutSeconds then
            return "00:00";
        else
            return "00:00:00";
        end
    else
        local hours = string.format("%02.f", math.floor(seconds / 3600));
        local mins = string.format("%02.f", math.floor(seconds / 60 - (hours * 60)));
        if withoutSeconds then
            return hours .. ":" .. mins
        end
        local secs = string.format("%02.f", math.floor(seconds - hours * 3600 - mins * 60));
        return hours .. ":" .. mins .. ":" .. secs
    end
end

--- Returns number of keys in a table.
---- @param T Lua table
---- @treturn int number of keys in table T
function util.tableSize(T)
    local count = 0
    for _ in pairs(T) do count = count + 1 end
    return count
end

-- append all elements from t2 into t1
function util.arrayAppend(t1, t2)
    for _, v in ipairs(t2) do
        table.insert(t1, v)
    end
end

-- Returns the index within this string of the last occurrence of the specified character
-- or -1 if the character does not occur.
-- To find . you need to escape it.
function util.lastIndexOf(string, ch)
    local i = string:match(".*" .. ch .. "()")
    if i == nil then return -1 else return i - 1 end
end


--- Split string into a list of UTF-8 chars.
---- @string text the string to be splitted.
---- @treturn table list of UTF-8 chars
function util.splitToChars(text)
    local tab = {}
    if text ~= nil then
        local prevcharcode, charcode = 0
        for uchar in string.gfind(text, "([%z\1-\127\194-\244][\128-\191]*)") do
            charcode = BaseUtil.utf8charcode(uchar)
            if prevcharcode then -- utf8
                table.insert(tab, uchar)
            end
            prevcharcode = charcode
        end
    end
    return tab
end

-- Test whether c is a CJK character
function util.isCJKChar(c)
    return string.match(c, "[\228-\234][\128-\191].") == c
end

-- Test whether str contains CJK characters
function util.hasCJKChar(str)
    return string.match(str, "[\228-\234][\128-\191].") ~= nil
end

--- Split text into a list of words, spaces and punctuations.
---- @string text text to split
---- @treturn table list of words, spaces and punctuations
function util.splitToWords(text)
    local wlist = {}
    for word in util.gsplit(text, "[%s%p]+", true) do
        -- if space splitted word contains CJK characters
        if util.hasCJKChar(word) then
            -- split with CJK characters
            for char in util.gsplit(word, "[\228-\234\192-\255][\128-\191]+", true) do
                table.insert(wlist, char)
            end
        else
            table.insert(wlist, word)
        end
    end
    return wlist
end

-- We don't want to split on a space if it is followed by some
-- specific punctuation : e.g. "word :" or "word )"
-- (In french, there is a space before a colon, and it better
-- not be wrapped there.)
local non_splitable_space_tailers = ":;,.!?)]}$%=-+*/|<>»”"
-- Same if a space has some specific other punctuation before it
local non_splitable_space_leaders = "([{$=-+*/|<>«“"

-- Test whether a string could be separated by this char for multi-line rendering
-- Optional next or prev chars may be provided to help make the decision
function util.isSplitable(c, next_c, prev_c)
    if util.isCJKChar(c) then
        -- a CJKChar is a word in itself, and so is splitable
        return true
    elseif c == " " then
        -- we only split on a space (so punctuation sticks to prev word)
        -- if next_c or prev_c is provided, we can make a better decision
        if next_c and non_splitable_space_tailers:find(next_c, 1, true) then
            -- this space is followed by some punctuation that is better kept with us
            return false
        elseif prev_c and non_splitable_space_leaders:find(prev_c, 1, true) then
            -- this space is lead by some punctuation that is better kept with us
            return false
        else
            -- we can split on this space
            return true
        end
    end
    -- otherwise, non splitable
    return false
end

return util
