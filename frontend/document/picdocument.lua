local Document = require("document/document")
local DrawContext = require("ffi/drawcontext")
local Screen = require("device").screen
local pic = nil

local PicDocument = Document:new{
    _document = false,
    is_pic = true,
    dc_null = DrawContext.new(),
    provider = "picdocument",
    provider_name = "Picture Document",
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
    local first_page = self._document:openPage(1)
    if first_page.image_bb then
        return first_page.image_bb
    end
    return nil
end

function PicDocument:register(registry)
    registry:addProvider("gif", "image/gif", self, 100)
    registry:addProvider("jpg", "image/jpeg", self, 100)
    registry:addProvider("jpeg", "image/jpeg", self, 100)
    registry:addProvider("png", "image/png", self, 100)
end

return PicDocument
