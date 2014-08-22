local Cache = require("cache")
local CacheItem = require("cacheitem")
local KoptOptions = require("ui/data/koptoptions")
local Document = require("document/document")
local Configurable = require("configurable")
local DrawContext = require("ffi/drawcontext")
local ffi = require("ffi")
ffi.cdef[[
typedef struct fz_point_s fz_point;
struct fz_point_s {
    float x, y;
};
typedef enum {
    FZ_ANNOT_TEXT,
    FZ_ANNOT_LINK,
    FZ_ANNOT_FREETEXT,
    FZ_ANNOT_LINE,
    FZ_ANNOT_SQUARE,
    FZ_ANNOT_CIRCLE,
    FZ_ANNOT_POLYGON,
    FZ_ANNOT_POLYLINE,
    FZ_ANNOT_HIGHLIGHT,
    FZ_ANNOT_UNDERLINE,
    FZ_ANNOT_SQUIGGLY,
    FZ_ANNOT_STRIKEOUT,
    FZ_ANNOT_STAMP,
    FZ_ANNOT_CARET,
    FZ_ANNOT_INK,
    FZ_ANNOT_POPUP,
    FZ_ANNOT_FILEATTACHMENT,
    FZ_ANNOT_SOUND,
    FZ_ANNOT_MOVIE,
    FZ_ANNOT_WIDGET,
    FZ_ANNOT_SCREEN,
    FZ_ANNOT_PRINTERMARK,
    FZ_ANNOT_TRAPNET,
    FZ_ANNOT_WATERMARK,
    FZ_ANNOT_3D
} fz_annot_type;
]]

local PdfDocument = Document:new{
    _document = false,
    -- muPDF manages its own additional cache
    mupdf_cache_size = 5 * 1024 * 1024,
    dc_null = DrawContext.new(),
    options = KoptOptions,
    koptinterface = nil,
    annot_revision = 0,
}

function PdfDocument:init()
    local pdf = require("libs/libkoreader-pdf")
    self.koptinterface = require("document/koptinterface")
    self.configurable:loadDefaults(self.options)
    local ok
    ok, self._document = pcall(pdf.openDocument, self.file, self.mupdf_cache_size)
    if not ok then
        self.error_message = self._document -- will contain error message
        return
    end
    self.is_open = true
    self.info.has_pages = true
    self.info.configurable = true
    if self._document:needsPassword() then
        self.is_locked = true
    else
        self:_readMetadata()
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
    self.annot_revision = self.annot_revision + 1
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
    self._document:writeDocument(self.file)
end

function PdfDocument:close()
    if self.annot_revision ~= 0 then
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
