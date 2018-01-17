--[[--
This module contains miscellaneous helper functions for the KOReader frontend.
]]

local BaseUtil = require("ffi/util")
local util = {}

--- Strips all punctuation and spaces from a string.
---- @string text the string to be stripped
---- @treturn string stripped text
function util.stripePunctuations(text)
    if not text then return end
    -- strip ASCII punctuation characters around text
    -- and strip any generic punctuation (U+2000 - U+206F) in the text
    return text:gsub("\226[\128-\131][\128-\191]", ''):gsub("^%p+", ''):gsub("%p+$", '')
end

--[[--
Splits a string by a pattern

Lua doesn't have a string.split() function and most of the time
you don't really need it because string.gmatch() is enough.
However string.gmatch() has one significant disadvantage for me:
You can't split a string while matching both the delimited
strings and the delimiters themselves without tracking positions
and substrings. The gsplit function below takes care of
this problem.

Author: Peter Odding

License: MIT/X11

Source: <a href="http://snippets.luacode.org/snippets/String_splitting_130">http://snippets.luacode.org/snippets/String_splitting_130</a>
]]
----@string str string to split
----@param pattern the pattern to split against
----@bool capture
----@bool capture_empty_entity
function util.gsplit(str, pattern, capture, capture_empty_entity)
    pattern = pattern and tostring(pattern) or '%s+'
    if (''):find(pattern) then
        error('pattern matches empty string!', 2)
    end
    return coroutine.wrap(function()
        local index = 1
        repeat
            local first, last = str:find(pattern, index)
            if first and last then
                if index < first or (index == first and capture_empty_entity) then
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

--[[--
Converts seconds to a clock string.

Source: <a href="https://gist.github.com/jesseadams/791673">https://gist.github.com/jesseadams/791673</a>
]]
---- @int seconds number of seconds
---- @bool withoutSeconds if true 00:00, if false 00:00:00
---- @treturn string clock string in the form of 00:00 or 00:00:00
function util.secondsToClock(seconds, withoutSeconds)
    seconds = tonumber(seconds)
    if seconds == 0 or seconds ~= seconds then
        if withoutSeconds then
            return "00:00"
        else
            return "00:00:00"
        end
    else
        local round = withoutSeconds and require("optmath").round or math.floor
        local hours = string.format("%02.f", math.floor(seconds / 3600))
        local mins = string.format("%02.f", round(seconds / 60 - (hours * 60)))
        if mins == "60" then
            mins = string.format("%02.f", 0)
            hours = string.format("%02.f", hours + 1)
        end
        if withoutSeconds then
            return hours .. ":" .. mins
        end
        local secs = string.format("%02.f", math.floor(seconds - hours * 3600 - mins * 60))
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

--- Append all elements from t2 into t1.
---- @param t1 Lua table
---- @param t2 Lua table
function util.arrayAppend(t1, t2)
    for _, v in ipairs(t2) do
        table.insert(t1, v)
    end
end

--[[--
Gets last index of string in character

Returns the index within this string of the last occurrence of the specified character
or -1 if the character does not occur.

To find . you need to escape it.
]]
---- @string string
---- @string ch
---- @treturn int last occurrence or -1 if not found
function util.lastIndexOf(string, ch)
    local i = string:match(".*" .. ch .. "()")
    if i == nil then return -1 else return i - 1 end
end

--- Reverse the individual greater-than-single-byte characters
-- @string string to reverse
-- Taken from https://github.com/blitmap/lua-utf8-simple#utf8reverses
function util.utf8Reverse(text)
    text = text:gsub('[%z\1-\127\194-\244][\128-\191]*', function (c) return #c > 1 and c:reverse() end)
    return text:reverse()
end

--- Splits string into a list of UTF-8 characters.
---- @string text the string to be split.
---- @treturn table list of UTF-8 chars
function util.splitToChars(text)
    local tab = {}
    if text ~= nil then
        local prevcharcode, charcode = 0
        for uchar in string.gmatch(text, "([%z\1-\127\194-\244][\128-\191]*)") do
            charcode = BaseUtil.utf8charcode(uchar)
            if prevcharcode then -- utf8
                table.insert(tab, uchar)
            end
            prevcharcode = charcode
        end
    end
    return tab
end

--- Tests whether c is a CJK character
---- @string c
---- @treturn boolean true if CJK
function util.isCJKChar(c)
    return string.match(c, "[\228-\234][\128-\191].") == c
end

--- Tests whether str contains CJK characters
---- @string str
---- @treturn boolean true if CJK
function util.hasCJKChar(str)
    return string.match(str, "[\228-\234][\128-\191].") ~= nil
end

--- Split texts into a list of words, spaces and punctuation.
---- @string text text to split
---- @treturn table list of words, spaces and punctuation
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
local non_splittable_space_tailers = ":;,.!?)]}$%=-+*/|<>»”"
-- Same if a space has some specific other punctuation before it
local non_splittable_space_leaders = "([{$=-+*/|<>«“"


-- Similar rules exist for CJK text. Taken from :
-- https://en.wikipedia.org/wiki/Line_breaking_rules_in_East_Asian_languages

local cjk_non_splittable_tailers = table.concat( {
    -- Simplified Chinese
    "!%),.:;?]}¢°·’\"†‡›℃∶、。〃〆〕〗〞﹚﹜！＂％＇），．：；？！］｝～",
    -- Traditional Chinese
    "!),.:;?]}¢·–—’\"•、。〆〞〕〉》」︰︱︲︳﹐﹑﹒﹓﹔﹕﹖﹘﹚﹜！），．：；？︶︸︺︼︾﹀﹂﹗］｜｝､",
    -- Japanese
    ")]｝〕〉》」』】〙〗〟’\"｠»ヽヾーァィゥェォッャュョヮヵヶぁぃぅぇぉっゃゅょゎゕゖㇰㇱㇲㇳㇴㇵㇶㇷㇸㇹㇺㇻㇼㇽㇾㇿ々〻‐゠–〜?!‼⁇⁈⁉・、:;,。.",
    -- Korean
    "!%),.:;?]}¢°’\"†‡℃〆〈《「『〕！％），．：；？］｝",
})

local cjk_non_splittable_leaders = table.concat( {
    -- Simplified Chinese
    "$(£¥·‘\"〈《「『【〔〖〝﹙﹛＄（．［｛￡￥",
    -- Traditional Chinese
    "([{£¥‘\"‵〈《「『〔〝︴﹙﹛（｛︵︷︹︻︽︿﹁﹃﹏",
    -- Japanese
    "([｛〔〈《「『【〘〖〝‘\"｟«",
    -- Korean
    "$([{£¥‘\"々〇〉》」〔＄（［｛｠￥￦#",
})

local cjk_non_splittable = table.concat( {
    -- Japanese
    "—…‥〳〴〵",
})

--- Test whether a string can be separated by this char for multi-line rendering.
-- Optional next or prev chars may be provided to help make the decision
---- @string c
---- @string next_c
---- @string prev_c
---- @treturn boolean true if splittable, false if not
function util.isSplittable(c, next_c, prev_c)
    if util.isCJKChar(c) then
        -- a CJKChar is a word in itself, and so is splittable
        if cjk_non_splittable:find(c, 1, true) then
            -- except a few of them
            return false
        elseif next_c and cjk_non_splittable_tailers:find(next_c, 1, true) then
            -- but followed by a char that is not permitted at start of line
            return false
        elseif prev_c and cjk_non_splittable_leaders:find(prev_c, 1, true) then
            -- but preceded by a char that is not permitted at end of line
            return false
        else
            -- we can split on this CJKchar
            return true
        end
    elseif c == " " then
        -- we only split on a space (so punctuation sticks to prev word)
        -- if next_c or prev_c is provided, we can make a better decision
        if next_c and non_splittable_space_tailers:find(next_c, 1, true) then
            -- this space is followed by some punctuation that is better kept with us
            return false
        elseif prev_c and non_splittable_space_leaders:find(prev_c, 1, true) then
            -- this space is lead by some punctuation that is better kept with us
            return false
        else
            -- we can split on this space
            return true
        end
    end
    -- otherwise, non splittable
    return false
end

--- Gets filesystem type of a path.
--
-- Checks if the path occurs in <code>/proc/mounts</code>
---- @string path an absolute path
---- @treturn string filesystem type
function util.getFilesystemType(path)
    local mounts = io.open("/proc/mounts", "r")
    if not mounts then return nil end
    local type
    while true do
        local line
        local mount = {}
        line = mounts:read()
        if line == nil then
            break
        end
        for param in line:gmatch("%S+") do table.insert(mount, param) end
        if string.match(path, mount[2]) then
            type = mount[3]
            if mount[2] ~= '/' then
                break
            end
        end
    end
    mounts:close()
    return type
end

--- Checks if directory is empty.
---- @string path
---- @treturn bool
function util.isEmptyDir(path)
    local lfs = require("libs/libkoreader-lfs")
    -- lfs.dir will crash rather than return nil if directory doesn't exist O_o
    local ok, iter, dir_obj = pcall(lfs.dir, path)
    if not ok then return end
    for filename in iter, dir_obj do
        if filename ~= '.' and filename ~= '..' then
            return false
        end
    end
    return true
end

--- Checks if the given path exists. Doesn't care if it's a file or directory.
---- @string path
---- @treturn bool
function util.pathExists(path)
    local lfs = require("libs/libkoreader-lfs")
    return lfs.attributes(path, "mode") ~= nil
end

--- As `mkdir -p`.
--- Unlike lfs.mkdir(), does not error if the directory already exists, and
--- creates intermediate directories as needed.
---- @string path the directory to create
---- @treturn bool true on success; nil, err_message on error
function util.makePath(path)
    path = path:gsub("/+$", "")
    if util.pathExists(path) then return true end

    local success, err = util.makePath((util.splitFilePathName(path)))
    if not success then
        return nil, err.." (creating "..path..")"
    end

    local lfs = require("libs/libkoreader-lfs")
    return lfs.mkdir(path)
end

--- Replaces characters that are invalid filenames.
--
-- Replaces the characters <code>\/:*?"<>|</code> with an <code>_</code>.
-- These characters are problematic on Windows filesystems. On Linux only
-- <code>/</code> poses a problem.
---- @string str filename
---- @treturn string sanitized filename
function util.replaceInvalidChars(str)
    if str then
        return str:gsub('[\\,%/,:,%*,%?,%",%<,%>,%|]','_')
    end
end

--- Replaces slash with an underscore.
---- @string str
---- @treturn string
function util.replaceSlashChar(str)
    if str then
        return str:gsub('%/','_')
    end
end

--- Splits a file into its directory path and file name.
--- If the given path has a trailing /, returns the entire path as the directory
--- path and "" as the file name.
---- @string file
---- @treturn string path, filename
function util.splitFilePathName(file)
    if file == nil or file == "" then return "", "" end
    if string.find(file, "/") == nil then return "", file end
    return string.gsub(file, "(.*/)(.*)", "%1"), string.gsub(file, ".*/", "")
end

--- Splits a file name into its pure file name and suffix
---- @string file
---- @treturn string path, extension
function util.splitFileNameSuffix(file)
    if file == nil or file == "" then return "", "" end
    if string.find(file, "%.") == nil then return file, "" end
    return string.gsub(file, "(.*)%.(.*)", "%1"), string.gsub(file, ".*%.", "")
end

--- Gets file extension
---- @string filename
---- @treturn string extension
function util.getFileNameSuffix(file)
    local _, suffix = util.splitFileNameSuffix(file)
    return suffix
end

--- Gets human friendly size as string
---- @int size (bytes)
---- @treturn string
function util.getFriendlySize(size)
    local s
    if size > 1024*1024*1024 then
        s = string.format("%4.1f GB", size/1024/1024/1024)
    elseif size > 1024*1024 then
        s = string.format("%4.1f MB", size/1024/1024)
    elseif size > 1024 then
        s = string.format("%4.1f KB", size/1024)
    else
        s = string.format("%d B", size)
    end
    return s
end

--- Gets formatted size as string (1273334 => "1,273,334")
---- @int size (bytes)
---- @treturn string
function util.getFormattedSize(size)
    local s = tostring(size)
    s = s:reverse():gsub("(%d%d%d)", "%1,")
    s = s:reverse():gsub("^,", "")
    return s
end

--- Adds > to touch menu items with a submenu
function util.getMenuText(item)
    local text
    if item.text_func then
        text = item.text_func()
    else
        text = item.text
    end
    if item.sub_item_table ~= nil then
        text = text .. " \226\150\184"
    end
    return text
end

--- Replaces invalid UTF-8 characters with a replacement string.
--
-- Based on <a href="http://notebook.kulchenko.com/programming/fixing-malformed-utf8-in-lua">http://notebook.kulchenko.com/programming/fixing-malformed-utf8-in-lua</a>
---- @string str the string to be checked for invalid characters
---- @string replacement the string to replace invalid characters with
---- @treturn string valid UTF-8
function util.fixUtf8(str, replacement)
    local pos = 1
    local len = #str
    while pos <= len do
        if     pos == str:find("[%z\1-\127]", pos) then pos = pos + 1
        elseif pos == str:find("[\194-\223][\128-\191]", pos) then pos = pos + 2
        elseif pos == str:find(       "\224[\160-\191][\128-\191]", pos)
            or pos == str:find("[\225-\236][\128-\191][\128-\191]", pos)
            or pos == str:find(       "\237[\128-\159][\128-\191]", pos)
            or pos == str:find("[\238-\239][\128-\191][\128-\191]", pos) then pos = pos + 3
        elseif pos == str:find(       "\240[\144-\191][\128-\191][\128-\191]", pos)
            or pos == str:find("[\241-\243][\128-\191][\128-\191][\128-\191]", pos)
            or pos == str:find(       "\244[\128-\143][\128-\191][\128-\191]", pos) then pos = pos + 4
        else
            str = str:sub(1, pos - 1) .. replacement .. str:sub(pos + 1)
            pos = pos + #replacement
            len = len + #replacement - 1
        end
    end
    return str
end

--- Splits input string with the splitter into a table. This function ignores the last empty entity.
--
--- @string str the string to be split
--- @string splitter
--- @bool capture_empty_entity
--- @treturn an array-like table
function util.splitToArray(str, splitter, capture_empty_entity)
    local result = {}
    for word in util.gsplit(str, splitter, false, capture_empty_entity) do
        table.insert(result, word)
    end
    return result
end

--- Convert a Unicode codepoint (number) to UTF8 char
--
--- @int c Unicode codepoint
--- @treturn string UTF8 char
function util.unicodeCodepointToUtf8(c)
    if c < 128 then
        return string.char(c)
    elseif c < 2048 then
        return string.char(192 + c/64, 128 + c%64)
    elseif c < 55296 or 57343 < c and c < 65536 then
        return string.char(224 + c/4096, 128 + c/64%64, 128 + c%64)
    elseif c < 1114112 then
        return string.char(240 + c/262144, 128 + c/4096%64, 128 + c/64%64, 128 + c%64)
    else
        return util.unicodeCodepointToUtf8(65533) -- U+FFFD REPLACEMENT CHARACTER
    end
end

local HTML_ENTITIES_TO_UTF8 = {
    ["&lt;"] = "<",
    ["&gt;"] = ">",
    ["&quot;"] = '"',
    ["&apos;"] = "'",
    ["&nbsp;"] = "\xC2\xA0",
    ["&#(%d+);"] = function(x) return util.unicodeCodepointToUtf8(tonumber(x)) end,
    ["&#x(%x+);"] = function(x) return util.unicodeCodepointToUtf8(tonumber(x,16)) end,
    ["&amp;"] = "&", -- must be last
}
--- Replace HTML entities with their UTF8 equivalent in text
--
-- Supports only basic ones and those with numbers (no support
-- for named entities like &eacute;)
--- @int string text with HTML entities
--- @treturn string UTF8 text
function util.htmlEntitiesToUtf8(text)
    for k,v in pairs(HTML_ENTITIES_TO_UTF8) do
        text = text:gsub(k, v)
    end
    return text
end

--- Convert simple HTML to plain text
-- This may fail on complex HTML (with styles, scripts, comments), but should
-- be fine enough with simple HTML as found in EPUB's <dc:description>.
--
--- @string text HTML text
--- @treturn string plain text
function util.htmlToPlainText(text)
    -- Replace <br> and <p> with \n
    text = text:gsub("%s*<%s*br%s*/?>%s*", "\n") -- <br> and <br/>
    text = text:gsub("%s*<%s*p%s*>%s*", "\n") -- <p>
    text = text:gsub("%s*</%s*p%s*>%s*", "\n") -- </p>
    text = text:gsub("%s*<%s*p%s*/>%s*", "\n") -- standalone <p/>
    -- Remove all HTML tags
    text = text:gsub("<[^>]*>", "")
    -- Convert HTML entities
    text = util.htmlEntitiesToUtf8(text)
    -- Trim spaces and new lines at start and end
    text = text:gsub("^[\n%s]*", "")
    text = text:gsub("[\n%s]*$", "")
    return text
end

--- Convert HTML to plain text if text seems to be HTML
-- Detection of HTML is simple and may raise false positives
-- or negatives, but seems quite good at guessing content type
-- of text found in EPUB's <dc:description>.
--
--- @string text the string with possibly some HTML
--- @treturn string cleaned text
function util.htmlToPlainTextIfHtml(text)
    local is_html = false
    -- Quick way to check if text is some HTML:
    -- look for html tags
    local _, nb_tags
    _, nb_tags = text:gsub("<%w+.->", "")
    if nb_tags > 0 then
        is_html = true
    else
        -- no <tag> found
        -- but we may meet some text badly twicely encoded html containing "&lt;br&gt;"
        local nb_encoded_tags
        _, nb_encoded_tags = text:gsub("&lt;%a+&gt;", "")
        if nb_encoded_tags > 0 then
            is_html = true
            -- decode one of the two encodes
            text = util.htmlEntitiesToUtf8(text)
        end
    end

    if is_html then
        text = util.htmlToPlainText(text)
    else
        -- if text ends with ]]>, it probably comes from <![CDATA[ .. ]]> that
        -- crengine has extracted correctly, but let the ending tag in, so
        -- let's remove it
        text = text:gsub("]]>%s*$", "")
    end
    return text
end

--- Encode the HTML entities in a string
--- @string text the string to escape
-- Taken from https://github.com/kernelsauce/turbo/blob/e4a35c2e3fb63f07464f8f8e17252bea3a029685/turbo/escape.lua#L58-L70
function util.htmlEscape(text)
    return text:gsub("[}{\">/<'&]", {
        ["&"] = "&amp;",
        ["<"] = "&lt;",
        [">"] = "&gt;",
        ['"'] = "&quot;",
        ["'"] = "&#39;",
        ["/"] = "&#47;",
    })
end

--- Escape list for shell usage
--- @table args the list of arguments to escape
--- @treturn string the escaped and concatenated arguments
function util.shell_escape(args)
    local escaped_args = {}
    for _, arg in ipairs(args) do
        arg = "'" .. arg:gsub("'", "'\\''") .. "'"
        table.insert(escaped_args, arg)
    end
    return table.concat(escaped_args, " ")
end

--- Clear all the elements from a table without reassignment.
--- @table t the table to be cleared
function util.clearTable(t)
    local c = #t
    for i = 0, c do t[i] = nil end
end

return util
