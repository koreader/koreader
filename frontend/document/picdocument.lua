local Document = require("document/document")
local DrawContext = require("ffi/drawcontext")
local Screen = require("device").screen
local pic = nil

local PicDocument = Document:new{
    _document = false,
    is_pic = true,
    dc_null = DrawContext.new()
}

function PicDocument:init()
    self:updateColorRendering()
    if not pic then pic = require("ffi/pic") end
    -- pic.color needs to be true before opening document to allow toggling color
    pic.color = Screen.isColorScreen()
    local ok
    ok, self._document = pcall(pic.openDocument, self.file)
    if not ok then
        error("Failed to open jpeg image")
    end

    self.info.has_pages = true
    self.info.configurable = false

    self:_readMetadata()
end

function PicDocument:getUsedBBox(pageno)
    return { x0 = 0, y0 = 0, x1 = self._document.width, y1 = self._document.height }
end

function PicDocument:getProps()
    local _, _, docname = self.file:find(".*/(.*)")
    docname = docname or self.file
    return {
        title = docname:match("(.*)%."),
    }
end

function PicDocument:getCoverPageImage()
    local f = io.open(self.file, "rb")
    if f then
        local data = f:read("*all")
        f:close()
        local Mupdf = require("ffi/mupdf")
        local ok, image = pcall(Mupdf.renderImage, data, data:len())
        if ok then
            return image
        end
    end
    return nil
end

function PicDocument:register(registry)
    registry:addProvider("jpeg", "image/jpeg", self)
    registry:addProvider("jpg", "image/jpeg", self)
    registry:addProvider("png", "image/png", self)
    registry:addProvider("gif", "image/gif", self)
end

return PicDocument
