
local util = {}

function util.stripePunctuations(word)
    if not word then return end
    -- strip ASCII punctuation characters around word
    -- and strip any generic punctuation (U+2000 - U+206F) in the word
    return word:gsub("\226[\128-\131][\128-\191]",''):gsub("^%p+",''):gsub("%p+$",'')
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

return util
