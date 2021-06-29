--[[
    This code is derived from the LAPHLibs which can be found here:

    https://github.com/Wiladams/LAPHLibs
--]]
local util = require("util")
local luxl = require("luxl")
local ffi = require("ffi")

local OPDSParser = {}

local unescape_map  = {
    ["lt"] = "<",
    ["gt"] = ">",
    ["amp"] = "&",
    ["quot"] = '"',
    ["apos"] = "'"
}

local gsub = string.gsub
local function unescape(str)
    return gsub(str, '(&(#?)([%d%a]+);)', function(orig, n, s)
        if unescape_map[s] then
            return unescape_map[s]
        elseif n == "#" then  -- unescape unicode
            return util.unicodeCodepointToUtf8(tonumber(s))
        else
            return orig
        end
    end)
end

function OPDSParser:createFlatXTable(xlex, curr_element)
    curr_element = curr_element or {}

    local curr_attr_name
    local attr_count = 0

    -- start reading the thing
    for event, offset, size in xlex:Lexemes() do
        local txt = ffi.string(xlex.buf + offset, size)
        if event == luxl.EVENT_START then
            if txt ~= "xml" then
                -- does current element already have something
                -- with this name?

                -- if it does, if it's a table, add to it
                -- if it doesn't, then add a table
                local tab = self:createFlatXTable(xlex)
                if txt == "entry" or txt == "link" or txt == "Url" then
                    if curr_element[txt] == nil then
                        curr_element[txt] = {}
                    end
                    table.insert(curr_element[txt], tab)
                elseif type(curr_element) == "table" then
                    curr_element[txt] = tab
                end
            end
        elseif event == luxl.EVENT_ATTR_NAME then
            curr_attr_name = unescape(txt)
        elseif event == luxl.EVENT_ATTR_VAL then
            curr_element[curr_attr_name] = unescape(txt)
            attr_count = attr_count + 1
            curr_attr_name = nil
        elseif event == luxl.EVENT_TEXT then
            curr_element = unescape(txt)
        elseif event == luxl.EVENT_END then
            return curr_element
        end
    end
    return curr_element
end

function OPDSParser:parse(text)
    -- luxl doesn't handle XML comments, so strip them
    text = text:gsub("<!%-%-.-%-%->", "")
    -- luxl is also particular about the syntax for self-closing, empty & orphaned tags...
    text = text:gsub("<([%l:]+)/>", "<%1 />")
    -- We also need to handle the slash-less variants for br & hr...
    text = text:gsub("<([bh]r)>", "<%1 />")
    -- Some OPDS catalogs wrap text in a CDATA section, remove it as it causes parsing problems
    text = text:gsub("<!%[CDATA%[(.-)%]%]>", function (s)
        return s:gsub("%p", {["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;"})
    end )

    -- NOTE: OPDS content tags are likely to contain a bunch of HTML or XHTML. We do *NOT* want to let luxl parse that,
    --       because it doesn't really deal well with various XHTML quirks, as the list of crappy replacements above attests to...
    --       There's also a high probability of finding orphaned tags or badly nested ones in there, which would screw everything up.
    --       In any case, we just want to treat the whole thing as a single text node anyway, so, just mangle the markup to force luxl's hand.
    text = text:gsub('<content type=".-">', "<content>")
    text = text:gsub("<content>(.-)</content>", function (s)
        return '<content type="text">' .. s:gsub("%p", {["<"] = "&lt;", [">"] = "&gt;", ['"'] = "&quot;", ["'"] = "&apos;"}) .. "</content>"
    end )

    local xlex = luxl.new(text, #text)
    return assert(self:createFlatXTable(xlex))
end

return OPDSParser
