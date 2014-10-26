local Cache = require("cache")
local CacheItem = require("cacheitem")
local KoptOptions = require("ui/data/koptoptions")
local Document = require("document/document")
local Configurable = require("configurable")
local DrawContext = require("ffi/drawcontext")
local DEBUG = require("dbg")

local PdfDocument = Document:new{
    _document = false,
    dc_null = DrawContext.new(),
    options = KoptOptions,
    koptinterface = nil,
}

function PdfDocument:init()
    local pdf = require("ffi/mupdf")
    self.koptinterface = require("document/koptinterface")
    self.configurable:loadDefaults(self.options)
    local ok
    ok, self._document = pcall(pdf.openDocument, self.file)
    if not ok then
        error(self._document)  -- will contain error message
    end
    self.is_open = true
    self.info.has_pages = true
    self.info.configurable = true
    if self._document:needsPassword() then
        self.is_locked = true
    else
        self:_readMetadata()
    end
    if not (self.info.number_of_pages > 0) then
        error("No page found in PDF file")
    end
end

function PdfDocument:unlock(password)
    if not self._document:authenticatePassword(password) then
        self._document:close()
        return false, "wrong password"
    end
    self.is_locked = false
    return self:_readMetadata()
end

function PdfDocument:getPageTextBoxes(pageno)
    local page = self._document:openPage(pageno)
    local text = page:getPageText()
    page:close()
    return text
end

function PdfDocument:getWordFromPosition(spos)
    return self.koptinterface:getWordFromPosition(self, spos)
end

function PdfDocument:getTextFromPositions(spos0, spos1)
    return self.koptinterface:getTextFromPositions(self, spos0, spos1)
end

function PdfDocument:getPageBoxesFromPositions(pageno, ppos0, ppos1)
    return self.koptinterface:getPageBoxesFromPositions(self, pageno, ppos0, ppos1)
end

function PdfDocument:nativeToPageRectTransform(pageno, rect)
    return self.koptinterface:nativeToPageRectTransform(self, pageno, rect)
end

function PdfDocument:getOCRWord(pageno, wbox)
    return self.koptinterface:getOCRWord(self, pageno, wbox)
end

function PdfDocument:getOCRText(pageno, tboxes)
    return self.koptinterface:getOCRText(self, pageno, tboxes)
end

function PdfDocument:getPageRegions(pageno)
    return self.koptinterface:getPageRegions(self, pageno)
end

function PdfDocument:getUsedBBox(pageno)
    local hash = "pgubbox|"..self.file.."|"..pageno
    local cached = Cache:check(hash)
    if cached then
        return cached.ubbox
    end
    local page = self._document:openPage(pageno)
    local used = {}
    used.x0, used.y0, used.x1, used.y1 = page:getUsedBBox()
    local pwidth, pheight = page:getSize(self.dc_null)
    -- clamp to page BBox
    if used.x0 < 0 then used.x0 = 0 end
    if used.x1 > pwidth then used.x1 = pwidth end
    if used.y0 < 0 then used.y0 = 0 end
    if used.y1 > pheight then used.y1 = pheight end
    --@TODO give size for cacheitem?  02.12 2012 (houqp)
    Cache:insert(hash, CacheItem:new{
        ubbox = used,
    })
    page:close()
    return used
end

function PdfDocument:getPageLinks(pageno)
    local hash = "pglinks|"..self.file.."|"..pageno
    local cached = Cache:check(hash)
    if cached then
        return cached.links
    end
    local page = self._document:openPage(pageno)
    local links = page:getPageLinks()
    Cache:insert(hash, CacheItem:new{
        links = links,
    })
    page:close()
    return links
end

function PdfDocument:saveHighlight(pageno, item)
    self.is_edited = true
    local ffi = require("ffi")
    -- will also need mupdf_h.lua to be evaluated once
    -- but this is guaranteed at this point
    local n = #item.pboxes
    local quadpoints = ffi.new("fz_point[?]", 4*n)
    for i=1, n do
        quadpoints[4*i-4].x = item.pboxes[i].x
        quadpoints[4*i-4].y = item.pboxes[i].y + item.pboxes[i].h
        quadpoints[4*i-3].x = item.pboxes[i].x + item.pboxes[i].w
        quadpoints[4*i-3].y = item.pboxes[i].y + item.pboxes[i].h
        quadpoints[4*i-2].x = item.pboxes[i].x + item.pboxes[i].w
        quadpoints[4*i-2].y = item.pboxes[i].y
        quadpoints[4*i-1].x = item.pboxes[i].x
        quadpoints[4*i-1].y = item.pboxes[i].y
    end
    local page = self._document:openPage(pageno)
    local annot_type = ffi.C.FZ_ANNOT_HIGHLIGHT
    if item.drawer == "lighten" then
        annot_type = ffi.C.FZ_ANNOT_HIGHLIGHT
    elseif item.drawer == "underscore" then
        annot_type = ffi.C.FZ_ANNOT_UNDERLINE
    elseif item.drawer == "strikeout" then
        annot_type = ffi.C.FZ_ANNOT_STRIKEOUT
    end
    page:addMarkupAnnotation(quadpoints, 4*n, annot_type)
    page:close()
end

function PdfDocument:writeDocument()
    DEBUG("writing document to", self.file)
    self._document:writeDocument(self.file)
end

function PdfDocument:close()
    if self.is_edited then
        self:writeDocument()
    end
    Document.close(self)
end

function PdfDocument:getLinkFromPosition(pageno, pos)
    return self.koptinterface:getLinkFromPosition(self, pageno, pos)
end

function PdfDocument:clipPagePNGFile(pos0, pos1, pboxes, drawer, filename)
    return self.koptinterface:clipPagePNGFile(self, pos0, pos1, pboxes, drawer, filename)
end

function PdfDocument:clipPagePNGString(pos0, pos1, pboxes, drawer)
    return self.koptinterface:clipPagePNGString(self, pos0, pos1, pboxes, drawer)
end

function PdfDocument:getPageBBox(pageno)
    return self.koptinterface:getPageBBox(self, pageno)
end

function PdfDocument:getPageDimensions(pageno, zoom, rotation)
    return self.koptinterface:getPageDimensions(self, pageno, zoom, rotation)
end

function PdfDocument:getCoverPageImage()
    return self.koptinterface:getCoverPageImage(self)
end

function PdfDocument:renderPage(pageno, rect, zoom, rotation, gamma, render_mode)
    return self.koptinterface:renderPage(self, pageno, rect, zoom, rotation, gamma, render_mode)
end

function PdfDocument:hintPage(pageno, zoom, rotation, gamma, render_mode)
    return self.koptinterface:hintPage(self, pageno, zoom, rotation, gamma, render_mode)
end

function PdfDocument:drawPage(target, x, y, rect, pageno, zoom, rotation, gamma, render_mode)
    return self.koptinterface:drawPage(self, target, x, y, rect, pageno, zoom, rotation, gamma, render_mode)
end

function PdfDocument:register(registry)
    registry:addProvider("pdf", "application/pdf", self)
    registry:addProvider("cbz", "application/cbz", self)
    registry:addProvider("zip", "application/zip", self)
    registry:addProvider("xps", "application/xps", self)
end

return PdfDocument
