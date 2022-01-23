-- A parser for metadata.calibre
local util = require("util")

-- removes leading and closing characters and converts hex-unicodes
local function replaceHexChars(s, n, j)
    local l = string.len(s)
    if string.sub(s, l, l) == "\"" then
        s = string.sub(s, n, string.len(s)-1)
    else
        s = string.sub(s, n, string.len(s)-j)
    end
    s = string.gsub(s, "\\u([a-f0-9][a-f0-9][a-f0-9][a-f0-9])", function(w)
        return util.unicodeCodepointToUtf8(tonumber(w, 16))
    end)
    return s
end

-- a couple of string helper functions for dealing with raw json strings
local function isEqual(str, key)
    if str:sub(1, key:len() + 6) == string.format("    \"%s\"", key) then
        return true
    end
    return false
end

local function getValue(str, key)
    if str == string.format("    \"%s\": null, ", key) then
        return nil
    else
        return replaceHexChars(str, key:len() + 10, key == "series_index" and 2 or 3)
    end
end

local jsonStr = getmetatable("")
jsonStr.__index["equals"] = isEqual
jsonStr.__index["value"] = getValue


local parser = {}

-- read metadata from file, line by line, and keep just the data we need
function parser.parseFile(file)
    assert(type(file) == "string", "wrong type (expected a string")
    local f, err = io.open(file, "rb")
    if not f then
        return nil, string.format("error parsing %s: %s", file, err)
    end
    f:close()
    local add = function(t, line)
        if type(t) ~= "table" or type(line) ~= "string" then
            return {}
        end
        line = replaceHexChars(line, 8, 3)
        table.insert(t, #t + 1, line)
        return t
    end
    local books, book = {}, {}
    local is_author, is_tag = false, false
    for line in io.lines(file) do
        if line == "  }, " or line == "  }" then
            if type(book) == "table" then
                table.insert(books, #books + 1, book)
            end
            book = {}
        elseif line == "    \"authors\": [" then
            is_author = true
        elseif line == "    \"tags\": [" then
            is_tag = true
        elseif line == "    ], " or line == "    ]" then
            is_author, is_tag = false, false
        else
            for _, key in ipairs({"title", "uuid", "lpath", "size",
                "last_modified", "series", "series_index"})
            do
                if line:equals(key) then
                    book[key] = line:value(key)
                    break
                end
            end
        end
        if is_author then
            book.authors = add(book.authors, line)
        elseif is_tag then
            book.tags = add(book.tags, line)
        end
    end
    return books
end

return parser
