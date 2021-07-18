--[[--
This is a debug plugin to allow opening of big epubs,
especially on low-end devices.

@module koplugin.BigEpub
--]]--


local CreDocument = require("document/credocument")
local PdfDocument = require("document/pdfdocument")
local DocSettings = require("docsettings")
local Document = require("document/document")
local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local ffi = require("ffi")
local ffiUtil = require("ffi/util")
local luxl = require("luxl")
local util = require("frontend/util")
local _ = require("gettext")


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

local function createFlatXTable(xlex, curr_element)
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
                local tab = createFlatXTable(xlex)
                if txt == "item" then
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

local function parse(text)
    -- Murder Calibre's whole "content" block, because luxl doesn't really deal well with various XHTML quirks,
    -- as the list of crappy replacements below attests to...
    -- There's also a high probability of finding orphaned tags or badly nested ones in there, which will screw everything up.
    text = text:gsub('<content type="xhtml">.-</content>', '')
    -- luxl doesn't handle XML comments, so strip them
    text = text:gsub("<!%-%-.-%-%->", "")
    -- luxl prefers <br />, the other two forms are valid in HTML, but will kick luxl's ass
    text = text:gsub("<br>", "<br />")
    text = text:gsub("<br/>", "<br />")
    -- Same deal with hr
    text = text:gsub("<hr>", "<hr />")
    text = text:gsub("<hr/>", "<hr />")
    -- It's also allergic to orphaned <em/> (As opposed to a balanced <em></em> pair)...
    text = text:gsub("<em/>", "")
    -- Let's assume it might also happen to strong...
    text = text:gsub("<strong/>", "")
    -- Some OPDS catalogs wrap text in a CDATA section, remove it as it causes parsing problems
    text = text:gsub("<!%[CDATA%[(.-)%]%]>", function (s)
        return s:gsub( "%p", {["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;" } )
    end )
    local xlex = luxl.new(text, #text)
    return assert(createFlatXTable(xlex))
end


local Epub = {
    file = nil
}

function Epub:new(from_o)
    local o = from_o or {}
    setmetatable(o, self)
    self.__index = self
    if o._init then o:_init() end
    if o.init then o:init() end
    return o
end

function Epub:getFiles()
    if self._files then return self._files end
    local unzip_list_stdout = assert(io.popen("unzip -l \"" .. self.file .. "\""))
    local epub_content = unzip_list_stdout:read("*a")
    unzip_list_stdout:close()
    local files = {}
    if epub_content then
        local acc_size = 0
        for size, name in epub_content:gmatch("(%d+)%s+[%p%w]+%s+[%p%w]+%s+([%p%/%w]+)\n") do
            size = tonumber(size)
            acc_size = acc_size + size
            files[#files + 1] = {name = name, size = size, acc_size = acc_size}
        end
    end
    self._files = files
    return files
end

function Epub:getContentOpf()
    if self._contentopf then return self._contentopf end
    local opf, dir
    for _, v in ipairs(self:getFiles()) do
        dir, opf = v.name:match("^(.*)(content.opf)")
        if opf then
            break
        end
    end
    if not opf then return nil, "No content.opf found" end
    local opf_file = assert(io.popen("unzip -p \"" .. self.file .. "\" " .. opf))
    opf = opf_file:read("*a")
    if not opf_file:close() then return nil, "Couldn't read content.opf" end
    local contentopf = parse(opf)
    self._contentopf = contentopf
    return contentopf, dir
end

function Epub:getTmpDir()
    if self._tmpdir then return self._tmpdir end
    local file_abs_path = ffiUtil.realpath(self.file)
    if file_abs_path then
        local tmpdir = DocSettings:getSidecarDir(file_abs_path) .. "/epub"
        self._tmpdir = tmpdir
        return tmpdir
    end
end

function Epub:iterItems()
    local contentopf, dir = self:getContentOpf()
    return coroutine.wrap(function()
        for _, item in ipairs(contentopf.package.manifest.item) do
            coroutine.yield(item, dir)
        end
    end)
end

function Epub:getNextItem()
    if not self._items then
        self._items = self:iterItems()
    end
    return self._items()
end

function Epub:unzip()
    local file_abs_path = ffiUtil.realpath(self.file)
    local tmpdir = self:getTmpDir()
    if tmpdir then
        local unzip = io.popen("unzip -o -d \"" .. tmpdir .. "\" \"" .. file_abs_path .. "\"")
        return unzip:close()
    end
end

function Epub:nextFile()
    local tmpdir = self:getTmpDir()
    local entrypoint, dir
    repeat
        entrypoint, dir = self:getNextItem()
    until entrypoint and entrypoint.href and entrypoint.href:match("html?$")
    return tmpdir and entrypoint and tmpdir .. "/" ..dir .. entrypoint.href
end


local BigEpub = Document:new{
    provider="bigepub", provider_name="Big EPUB",
}

function BigEpub:new(o)
    if o.file then
        self._file = self._file or o.file
        if not self._epub then
            local epub = Epub:new{file = o.file}
            epub:unzip()
            self._epub = epub
        end
        self.file = self._epub:nextFile()
        self.__index = CreDocument:new(o)
        return setmetatable(self, self)
    end
end

function BigEpub:close()
    self.file = self._file
    self.__index.close(self)
end

function BigEpub:nextItem()
    return self._epub:nextFile()
end

function BigEpub:register(registry)
    registry:addProvider("epub", "application/epub+zip", self, 10)
    registry:addProvider("epub3", "application/epub+zip", self, 10)
end

return BigEpub
