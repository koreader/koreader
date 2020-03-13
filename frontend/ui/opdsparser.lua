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

    local curr_attr_name;
    local attr_count = 0;

    -- start reading the thing
    local txt
    for event, offset, size in xlex:Lexemes() do
        txt = ffi.string(xlex.buf + offset, size)
        if event == luxl.EVENT_START then
            if txt ~= "xml" then
                -- does current element already have something
                -- with this name?

                -- if it does, if it's a table, add to it
                -- if it doesn't, then add a table
                local tab = self:createFlatXTable(xlex)
                if txt == "entry" or txt == "link" then
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
            attr_count = attr_count + 1;
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
    -- luxl cannot properly handle xml comments and we need first remove them
    text = text:gsub("<!--.--->", "")
    -- luxl prefers <br />, other two forms are valid in HTML,
    -- but will kick the ass of luxl
    text = text:gsub("<br>", "<br />")
    text = text:gsub("<br/>", "<br />")
    -- Same deal with hr
    text = text:gsub("<hr>", "<hr />")
    text = text:gsub("<hr/>", "<hr />")
    -- some OPDS catalogs wrap text in a CDATA section, remove it as it causes parsing problems
    text = text:gsub("<!%[CDATA%[(.-)%]%]>", function (s)
        return s:gsub( "%p", {["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;" } )
    end )
    local xlex = luxl.new(text, #text)
    return assert(self:createFlatXTable(xlex))
end

return OPDSParser
