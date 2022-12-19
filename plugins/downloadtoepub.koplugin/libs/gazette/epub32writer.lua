local EpubError = require("libs/gazette/epuberror")
local ZipWriter = require("ffi/zipwriter")
local xml2lua = require("libs/xml2lua/xml2lua")

local Epub32Writer = ZipWriter:new {
    path = nil,
    temp_path = nil,
}

function Epub32Writer:new(o)
    o = o or {}
    self.__index = self
    setmetatable(o, self)

    return o
end

function Epub32Writer:build(epub)
    local ok, err = self:openTempPath()
    if not ok
    then
        return false, EpubError.EPUBWRITER_INVALID_PATH
    end

    self:addMimetype()
    self:addContainer()
    self:addPackage(epub:getPackageXml())
    self:addItems(epub:getManifestItems())

    self:close()
    os.rename(self.temp_path, self.path)

    return true
end

function Epub32Writer:setPath(path)
    local ok, err = self:isOutputAvailable(path)
    if not ok
    then
        return false, err
    else
        self.path = path
        return true
    end    
end

function Epub32Writer:addMimetype()
    self:add("mimetype", "application/epub+zip")
end

function Epub32Writer:addContainer()
    local container = Epub32Writer:getPart("container.xml")
    self:add("META-INF/container.xml", container)
end

function Epub32Writer:addPackage(packagio)
    self:add("OPS/package.opf", packagio)
end

function Epub32Writer:addItems(items)
    for _, item in ipairs(items) do
        local content = item:getContent()
        if content
        then
            self:add("OPS/" .. item.path, content)
        end
    end
end

function Epub32Writer:openTempPath()
    self.temp_path = self.path .. ".tmp"

    if not self:open(self.temp_path)
    then
        return false, EpubError.EPUBWRITER_INVALID_PATH
    else
        return true
    end
end

function Epub32Writer:isOutputAvailable(path)
    local test_path = path

    if not self:open(test_path)
    then
        return false, EpubError.EPUBWRITER_INVALID_PATH
    else
        self:close()
        os.remove(test_path)
        return true
    end
end

function Epub32Writer:getPart(filename)
    local file, err = xml2lua.loadFile("plugins/gazette.koplugin/libs/gazette/epub/templates/" .. filename)
    if file
    then
        return file
    else
        return false, err
    end
end

return Epub32Writer
