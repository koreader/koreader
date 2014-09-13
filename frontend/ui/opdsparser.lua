--[[
    This code is derived from the LAPHLibs which can be found here:

    https://github.com/Wiladams/LAPHLibs
--]]
local util = require("ffi/util")
local luxl = require("luxl")
local DEBUG = require("dbg")
local ffi = require("ffi")

local OPDSParser = {}

local unescape_map  = {
    ["lt"] = "<",
    ["gt"] = ">",
    ["amp"] = "&",
    ["quot"] = '"',
    ["apos"] = "'"
}

local gsub, char = string.gsub, string.char
local function unescape(str)
    return gsub(str, '(&(#?)([%d%a]+);)', function(orig, n, s)
        return unescape_map[s] or n=="#" and util.unichar(tonumber(s)) or orig
    end)
end

function OPDSParser:createFlatXTable(xlex, currentelement)
    currentelement = currentelement or {}

    local currentattributename = nil;
    local attribute_count = 0;

    -- start reading the thing
    local txt = nil;
    for event, offset, size in xlex:Lexemes() do
        txt = ffi.string(xlex.buf + offset, size)

        if event == luxl.EVENT_START and txt ~= "xml" then
            -- does current element already have something
            -- with this name?

            -- if it does, if it's a table, add to it
            -- if it doesn't, then add a table
            local tab = self:createFlatXTable(xlex)
            if txt == "entry" or txt == "link" then
                if currentelement[txt] == nil then
                    currentelement[txt] = {}
                end
                table.insert(currentelement[txt], tab)
            elseif type(currentelement) == "table" then
                currentelement[txt] = tab
            end
        end

        if event == luxl.EVENT_ATTR_NAME then
            currentattributename = txt
        end

        if event == luxl.EVENT_ATTR_VAL then
            currentelement[currentattributename] = txt
            attribute_count = attribute_count + 1;
            currentattributename = nil
        end

        if event == luxl.EVENT_TEXT then
            --if attribute_count < 1 then
            --  return txt
            --end

            currentelement = unescape(txt)
        end

        if event == luxl.EVENT_END then
            return currentelement
        end
    end

    return currentelement
end

function OPDSParser:parse(text)
    -- luxl cannot properly handle xml comments and we need first remove them
    text = text:gsub("<!--.--->", "")
    -- luxl prefers <br />, other two forms are valid in HTML,
    -- but will kick the ass of luxl
    text = text:gsub("<br>", "<br />")
    text = text:gsub("<br/>", "<br />")
    local xlex = luxl.new(text, #text)
    return self:createFlatXTable(xlex)
end

return OPDSParser
