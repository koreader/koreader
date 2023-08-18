local Document = require("document/document")
local DrawContext = require("ffi/drawcontext")
local CanvasContext = require("document/canvascontext")
local pic = nil

local PicDocument = Document:extend{
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
    pic.color = CanvasContext.is_color_rendering_enabled
    local ok
    ok, self._document = pcall(pic.openDocument, self.file)
    if not ok then
        error("Failed to open image:" .. self._document)
    end

    self.is_open = true
    self.info.has_pages = true
    self.info.configurable = false

    -- Enforce dithering in PicDocument
    if CanvasContext:hasEinkScreen() then
        if CanvasContext:canHWDither() then
            self.hw_dithering = true
        elseif CanvasContext.fb_bpp == 8 then
            self.sw_dithering = true
        end
    end

    self:_readMetadata()
end

function PicDocument:getUsedBBox(pageno)
    return { x0 = 0, y0 = 0, x1 = self._document.width, y1 = self._document.height }
end

function PicDocument:getDocumentProps()
    return {}
end

function PicDocument:getCoverPageImage()
    local first_page = self._document:openPage(1)
    if first_page.image_bb then
        return first_page.image_bb:copy()
    end
    return nil
end

function PicDocument:register(registry)
    registry:addProvider("gif", "image/gif", self, 100)
    registry:addProvider("jpg", "image/jpeg", self, 80)
    registry:addProvider("jpeg", "image/jpeg", self, 80)
    registry:addProvider("png", "image/png", self, 80)
    registry:addProvider("webp", "image/webp", self, 80)
end

return PicDocument
