local Document = require("document/document")
local DrawContext = require("ffi/drawcontext")
local pic = nil

local PicDocument = Document:new{
    _document = false,
    dc_null = DrawContext.new()
}

function PicDocument:init()
    if not pic then pic = require("ffi/pic") end
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

function PicDocument:register(registry)
    registry:addProvider("jpeg", "image/jpeg", self)
    registry:addProvider("jpg", "image/jpeg", self)
    registry:addProvider("png", "image/png", self)
    registry:addProvider("gif", "image/gif", self)
end

return PicDocument
