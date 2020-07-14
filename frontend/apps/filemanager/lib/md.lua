-- From https://github.com/bakpakin/luamd revision 388ce799d93e899e4d673cdc6d522f12310822bd
local FFIUtil = require("ffi/util")

--[[
Copyright (c) 2016 Calvin Rose <calsrose@gmail.com>

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
]]

local concat = table.concat
local sub = string.sub
local match = string.match
local format = string.format
local gmatch = string.gmatch
local byte = string.byte
local find = string.find
local lower = string.lower
local tonumber = tonumber -- luacheck: no unused
local type = type
local pcall = pcall

--------------------------------------------------------------------------------
-- Stream Utils
--------------------------------------------------------------------------------

local function stringLineStream(str)
    return gmatch(str, "([^\n\r]*)\r?\n?")
end

local function tableLineStream(t)
    local index = 0
    return function()
        index = index + 1
        return t[index]
    end
end

local function bufferStream(linestream)
    local bufferedLine = linestream()
    return function()
        bufferedLine = linestream()
        return bufferedLine
    end, function()
        return bufferedLine
    end
end

--------------------------------------------------------------------------------
-- Line Level Operations
--------------------------------------------------------------------------------

local lineDelimiters = {'`', '__', '**', '_', '*', '~~'}
local function findDelim(str, start, max)
    local delim = nil
    local min = 1/0
    local finish = 1/0
    max = max or #str
    for i = 1, #lineDelimiters do
        local pos, fin = find(str, lineDelimiters[i], start, true)
        if pos and pos < min and pos <= max then
            min = pos
            finish = fin
            delim = lineDelimiters[i]
        end
    end
    return delim, min, finish
end

local function externalLinkEscape(str, t)
    local nomatches = true
    for m1, m2, m3 in gmatch(str, '(.*)%[(.*)%](.*)') do
        if nomatches then t[#t + 1] = match(m1, '^(.-)!?$'); nomatches = false end
        if byte(m1, #m1) == byte '!' then
            t[#t + 1] = {type = 'img', attributes = {alt = m2}}
        else
            t[#t + 1] = {m2, type = 'a'}
        end
        t[#t + 1] = m3
    end
    if nomatches then t[#t + 1] = str end
end

local function linkEscape(str, t)
    local nomatches = true
    for m1, m2, m3, m4 in gmatch(str, '(.*)%[(.*)%]%((.*)%)(.*)') do
        if nomatches then externalLinkEscape(match(m1, '^(.-)!?$'), t); nomatches = false end
        if byte(m1, #m1) == byte '!' then
            t[#t + 1] = {type = 'img', attributes = {
                src = m3,
                alt = m2
            }, noclose = true}
        else
            t[#t + 1] = {m2, type = 'a', attributes = {href = m3}}
        end
        externalLinkEscape(m4, t)
    end
    if nomatches then externalLinkEscape(str, t) end
end

local lineDeimiterNames = {['`'] = 'code', ['__'] = 'strong', ['**'] = 'strong', ['_'] = 'em', ['*'] = 'em', ['~~'] = 'strike' }
local function lineRead(str, start, finish)
    start, finish = start or 1, finish or #str
    local searchIndex = start
    local tree = {}
    while true do
        local delim, dstart, dfinish = findDelim(str, searchIndex, finish)
        if not delim then
            linkEscape(sub(str, searchIndex, finish), tree)
            break
        end
        if dstart > searchIndex then
            linkEscape(sub(str, searchIndex, dstart - 1), tree)
        end
        local nextdstart, nextdfinish = find(str, delim, dfinish + 1, true)
        if nextdstart then
            if delim == '`' then
                tree[#tree + 1]  = {
                    sub(str, dfinish + 1, nextdstart - 1),
                    type = 'code'
                }
            else
                local subtree = lineRead(str, dfinish + 1, nextdstart - 1)
                subtree.type = lineDeimiterNames[delim]
                tree[#tree + 1] = subtree
            end
            searchIndex = nextdfinish + 1
        else
            tree[#tree + 1]  = {
                delim,
            }
            searchIndex = dfinish + 1
        end
    end
    return tree
end

local function getIndentLevel(line)
    local level = 0
    for i = 1, #line do
        local b = byte(line, i)
        if b == byte(' ') or b == byte('>') then
            level = level + 1
        elseif b == byte('\t') then
            level = level + 4
        else
            break
        end
    end
    return level
end

local function stripIndent(line, level, ignorepattern) -- luacheck: no unused args
    local currentLevel = -1
    for i = 1, #line do
        if byte(line, i) == byte("\t") then
            currentLevel = currentLevel + 4
        elseif byte(line, i) == byte(" ") or byte(line, i) == byte(">") then
            currentLevel = currentLevel + 1
        else
            return sub(line, i, -1)
        end
        if currentLevel == level then
            return sub(line, i, -1)
        elseif currentLevel > level then
            local front = ""
            for j = 1, currentLevel - level do front = front .. " " end -- luacheck: no unused args
            return front .. sub(line, i, -1)
        end
    end
end

--------------------------------------------------------------------------------
-- Useful variables
--------------------------------------------------------------------------------
local NEWLINE = '\n'

--------------------------------------------------------------------------------
-- Patterns
--------------------------------------------------------------------------------

local PATTERN_EMPTY = "^%s*$"
local PATTERN_COMMENT = "^%s*<>"
local PATTERN_HEADER = "^%s*(%#+)%s*(.*)%#*$"
local PATTERN_RULE1 = "^%s?%s?%s?(-%s*-%s*-[%s-]*)$"
local PATTERN_RULE2 = "^%s?%s?%s?(*%s**%s**[%s*]*)$"
local PATTERN_RULE3 = "^%s?%s?%s?(_%s*_%s*_[%s_]*)$"
local PATTERN_CODEBLOCK = "^%s*%`%`%`(.*)"
local PATTERN_BLOCKQUOTE = "^%s*> (.*)$"
local PATTERN_ULIST = "^%s*[%*%-] (.+)$"
local PATTERN_OLIST = "^%s*%d+%. (.+)$"
local PATTERN_LINKDEF = "^%s*%[(.*)%]%s*%:%s*(.*)"

-- List of patterns
local PATTERNS = {
    PATTERN_EMPTY,
    PATTERN_COMMENT,
    PATTERN_HEADER,
    PATTERN_RULE1,
    PATTERN_RULE2,
    PATTERN_RULE3,
    PATTERN_CODEBLOCK,
    PATTERN_BLOCKQUOTE,
    PATTERN_ULIST,
    PATTERN_OLIST,
    PATTERN_LINKDEF
}

local function isSpecialLine(line)
    for i = 1, #PATTERNS do
        if match(line, PATTERNS[i]) then return PATTERNS[i] end
    end
end

--------------------------------------------------------------------------------
-- Simple Reading - Non Recursive
--------------------------------------------------------------------------------

local function readSimple(pop, peek, tree, links)

    local line = peek()
    if not line then return end

    -- Test for Empty or Comment
    if match(line, PATTERN_EMPTY) or match(line, PATTERN_COMMENT) then
        return pop()
    end

    -- Test for Header
    local m, rest = match(line, PATTERN_HEADER)
    if m then
        tree[#tree + 1] = {
            lineRead(rest),
            type = "h" .. #m
        }
        tree[#tree + 1] = NEWLINE
        return pop()
    end

    -- Test for Horizontal Rule
    if match(line, PATTERN_RULE1) or
       match(line, PATTERN_RULE2) or
       match(line, PATTERN_RULE3) then
        tree[#tree + 1] = { type = "hr", noclose = true }
        tree[#tree + 1] = NEWLINE
        return pop()
    end

    -- Test for Code Block
    local syntax = match(line, PATTERN_CODEBLOCK)
    if syntax then
        local indent = getIndentLevel(line)
        local code = {
            type = "code"
        }
        if #syntax > 0 then
            code.attributes = {
                class = format('language-%s', lower(syntax))
            }
        end
        local pre = {
            type = "pre",
            [1] = code
        }
        tree[#tree + 1] = pre
        while not (match(pop(), PATTERN_CODEBLOCK) and getIndentLevel(peek()) == indent) do
            code[#code + 1] = peek()
            code[#code + 1] = '\r\n'
        end
        return pop()
    end

    -- Test for link definition
    local linkname, location = match(line, PATTERN_LINKDEF)
    if linkname then
        links[lower(linkname)] = location
        return pop()
    end

    -- Test for header type two
    local nextLine = pop()
    if nextLine and match(nextLine, "^%s*%=+$") then
        tree[#tree + 1] = { lineRead(line), type = "h1" }
        return pop()
    elseif nextLine and match(nextLine, "^%s*%-+$") then
        tree[#tree + 1] = { lineRead(line), type = "h2" }
        return pop()
    end

    -- Do Paragraph
    local p = {
        lineRead(line), NEWLINE,
        type = "p"
    }
    tree[#tree + 1] = p
    while nextLine and not isSpecialLine(nextLine) do
        p[#p + 1] = lineRead(nextLine)
        p[#p + 1] = NEWLINE
        nextLine = pop()
    end
    p[#p] = nil
    tree[#tree + 1] = NEWLINE
    return peek()

end

--------------------------------------------------------------------------------
-- Main Reading - Potentially Recursive
--------------------------------------------------------------------------------

local readLineStream

local function readFragment(pop, peek, links, stop, ...)
    local accum2 = {}
    local line = peek()
    local indent = getIndentLevel(line)
    while true do
        accum2[#accum2 + 1] = stripIndent(line, indent)
        line = pop()
        if not line then break end
        if stop(line, ...) then break end
    end
    local tree = {}
    readLineStream(tableLineStream(accum2), tree, links)
    return tree
end

local function readBlockQuote(pop, peek, tree, links)
    local line = peek()
    if match(line, PATTERN_BLOCKQUOTE) then
        local bq = readFragment(pop, peek, links, function(l)
            local tp = isSpecialLine(l)
            return tp and tp ~= PATTERN_BLOCKQUOTE
        end)
        bq.type = 'blockquote'
        tree[#tree + 1] = bq
        return peek()
    end
end

local function readList(pop, peek, tree, links, expectedIndent)
    if not peek() then return end
    if expectedIndent and getIndentLevel(peek()) ~= expectedIndent then return end
    local listPattern = (match(peek(), PATTERN_ULIST) and PATTERN_ULIST) or
                        (match(peek(), PATTERN_OLIST) and PATTERN_OLIST)
    if not listPattern then return end
    local lineType = listPattern
    local line = peek()
    local indent = getIndentLevel(line)
    local list = {
        type = (listPattern == PATTERN_ULIST and "ul" or "ol")
    }
    tree[#tree + 1] = list
    list[1] = NEWLINE
    while lineType == listPattern do
        list[#list + 1] = {
            lineRead(match(line, lineType)),
            type = "li"
        }
        line = pop()
        if not line then break end
        lineType = isSpecialLine(line)
        if lineType ~= PATTERN_EMPTY then
            list[#list + 1] = NEWLINE
            local i = getIndentLevel(line)
            if i < indent then break end
            if i > indent then
                local subtree = readFragment(pop, peek, links, function(l)
                    if not l then return true end
                    local tp = isSpecialLine(l)
                    return tp ~= PATTERN_EMPTY and getIndentLevel(l) < i
                end)
                list[#list + 1] = subtree
                line = peek()
                if not line then break end
                lineType = isSpecialLine(line)
            end
        end
    end
    list[#list + 1] = NEWLINE
    tree[#tree + 1] = NEWLINE
    return peek()
end

function readLineStream(stream, tree, links)
    local pop, peek = bufferStream(stream)
    tree = tree or {}
    links = links or {}
    while peek() do
        if not readBlockQuote(pop, peek, tree, links) then
            if not readList(pop, peek, tree, links) then
                readSimple(pop, peek, tree, links)
            end
        end
    end
    return tree, links
end

local function read(str) -- luacheck: no unused
    return readLineStream(stringLineStream(str))
end

--------------------------------------------------------------------------------
-- Rendering
--------------------------------------------------------------------------------

local function renderAttributes(attributes)
    local accum = {}
    -- KOReader: oderedPairs instead of pairs
    for k, v in FFIUtil.orderedPairs(attributes) do
        accum[#accum + 1] = format("%s=\"%s\"", k, v)
    end
    return concat(accum, ' ')
end

local function renderTree(tree, links, accum)
    if tree.type then
        local attribs = tree.attributes or {}
        if tree.type == 'a' and not attribs.href then attribs.href = links[lower(tree[1] or '')] or '' end
        if tree.type == 'img' and not attribs.src then attribs.src = links[lower(attribs.alt or '')] or '' end
        local attribstr = renderAttributes(attribs)
        if #attribstr > 0 then
            accum[#accum + 1] = format("<%s %s>", tree.type, attribstr)
        else
            accum[#accum + 1] = format("<%s>", tree.type)
        end
    end
    for i = 1, #tree do
        local line = tree[i]
        if type(line) == "string" then
            accum[#accum + 1] = line
        elseif type(line) == "table" then
            renderTree(line, links, accum)
        else
            error "Unexpected node while rendering tree."
        end
    end
    if not tree.noclose and tree.type then
        accum[#accum + 1] = format("</%s>", tree.type)
    end
end

local function renderLinesRaw(stream, options)
    local tree, links = readLineStream(stream)
    local accum = {}
    local head, tail, insertHead, insertTail, prependHead, appendTail = nil, nil, nil, nil, nil, nil
    if options then
        assert(type(options) == 'table', "Options argument should be a table.")
        if options.tag then
            tail = format('</%s>', options.tag)
            if options.attributes then
                head = format('<%s %s>', options.tag, renderAttributes(options.attributes))
            else
                head = format('<%s>', options.tag)
            end
        end
        insertHead = options.insertHead
        insertTail = options.insertTail
        prependHead = options.prependHead
        appendTail = options.appendTail
    end
    accum[#accum + 1] = prependHead
    accum[#accum + 1] = head
    accum[#accum + 1] = insertHead
    renderTree(tree, links, accum)
    if accum[#accum] == NEWLINE then accum[#accum] = nil end
    accum[#accum + 1] = insertTail
    accum[#accum + 1] = tail
    accum[#accum + 1] = appendTail
    return concat(accum)
end

--------------------------------------------------------------------------------
-- Module
--------------------------------------------------------------------------------

local function pwrap(...)
    local status, value = pcall(...)
    if status then
        return value
    else
        return nil, value
    end
end

local function renderLineIterator(stream, options)
    return pwrap(renderLinesRaw, stream, options)
end

local function renderTable(t, options)
    return pwrap(renderLinesRaw, tableLineStream(t), options)
end

local function renderString(str, options)
    return pwrap(renderLinesRaw, stringLineStream(str), options)
end

local renderers = {
    ['string'] = renderString,
    ['table'] = renderTable,
    ['function'] = renderLineIterator
}

local function render(source, options)
    local renderer = renderers[type(source)]
    if not renderer then return nil, "Source must be a string, table, or function." end
    return renderer(source, options)
end

return setmetatable({
    render = render,
    renderString = renderString,
    renderLineIterator = renderLineIterator,
    renderTable = renderTable
}, {
    __call = function(self, ...) -- luacheck: no unused args
        return render(...)
    end
})
