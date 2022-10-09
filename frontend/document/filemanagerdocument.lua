local Document = require("document/document")
local util = require("util")

local FileManagerDocument = Document:new{
    _document = false,
    provider = "filemanagerdocument",
    provider_name = "File Manager",
    providers = {},
}

function FileManagerDocument:init() end
function FileManagerDocument:close() end
function FileManagerDocument:register() end

-- opens a file with the provider with highest priority for that extension
function FileManagerDocument:open(file)
    local extension = util.getFileNameSuffix(file)
    if not self.providers[extension] then return end
    local max_priority = 0
    local max_priority_index = 1
    for i, v in ipairs(self.providers[extension]) do
        if v.priority > max_priority then
            max_priority = v.priority
            max_priority_index = i
        end
    end
    self.providers[extension][max_priority_index].open_func(file)
end

function FileManagerDocument:addHandler(name, t)
    assert(type(name) == "string", "string expected")
    assert(type(t) == "table", "table expected")
    local extension, mimetype, priority, open_func
    for k, v in pairs(t) do
        if type(v) == "table" then
            if type(k) == "string" then
                extension = k
            end
            if type(v.mimetype) == "string" then
                mimetype = v.mimetype
            end
            if type(v.open_func) == "function" then
                open_func = v.open_func
            end
            priority = v.priority or 20
        end

        if extension and mimetype and open_func then
            if not self.providers[extension] then
                self.providers[extension] = {}
            end
            table.insert(self.providers[extension], v)
            require("document/documentregistry"):addProvider(extension, mimetype, self, priority)
        end
    end
end

function FileManagerDocument:changeHandler(extension, t)
    self:deleteHandler(extension)
    self:addHandler(extension, t)
end

-- todo: remove from self.providers and documentregistry
function FileManagerDocument:deleteHandler(extension)
end


function FileManagerDocument:getProps()
    local _, _, docname = self.file:find(".*/(.*)")
    docname = docname or self.file
    return {
        title = docname:match("(.*)%."),
    }
end

function FileManagerDocument:_readMetadata()
    Document._readMetadata(self)
    return true
end

function FileManagerDocument:getCoverPageImage()
    return nil
end

return FileManagerDocument
