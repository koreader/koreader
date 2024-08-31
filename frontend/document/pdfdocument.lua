local BlitBuffer = require("ffi/blitbuffer")
local CacheItem = require("cacheitem")
local CanvasContext = require("document/canvascontext")
local DocCache = require("document/doccache")
local DocSettings = require("docsettings")
local Document = require("document/document")
local DrawContext = require("ffi/drawcontext")
local logger = require("logger")
local util = require("util")
local ffi = require("ffi")
local C = ffi.C
local pdf = nil

local PdfDocument = Document:extend{
    _document = false,
    is_pdf = true,
    dc_null = DrawContext.new(),
    koptinterface = nil,
    provider = "mupdf",
    provider_name = "MuPDF",
}

function PdfDocument:init()
    if not pdf then pdf = require("ffi/mupdf") end
    self.koptinterface = require("document/koptinterface")
    self.koptinterface:setDefaultConfigurable(self.configurable)
    local ok
    ok, self._document = pcall(pdf.openDocument, self.file)
    if not ok then
        error(self._document)  -- will contain error message
    end
    self:updateColorRendering()
    self.is_reflowable = self._document:isDocumentReflowable()
    self.reflowable_font_size = self:convertKoptToReflowableFontSize()
    -- no-op on PDF
    self:layoutDocument()
    self.is_open = true
    self.info.has_pages = true
    self.info.configurable = true
    self.render_mode = 0
    if self._document:needsPassword() then
        self.is_locked = true
    else
        self:_readMetadata()
    end
end

function PdfDocument:updateColorRendering()
    Document.updateColorRendering(self) -- will set self.render_color
    if self._document then
        self._document:setColorRendering(self.render_color)
    end
end

function PdfDocument:layoutDocument(font_size)
    if font_size then
        self.reflowable_font_size = font_size
    end
    self._document:layoutDocument(
        CanvasContext:getWidth(),
        CanvasContext:getHeight(),
        CanvasContext:scaleBySize(self.reflowable_font_size))
end

local default_font_size = 22
-- the koptreader config goes from 0.1 to 3.0, but we want a regular font size
function PdfDocument:convertKoptToReflowableFontSize(font_size)
    if font_size then
        return font_size * default_font_size
    end

    local size
    if DocSettings:hasSidecarFile(self.file) then
        local doc_settings = DocSettings:open(self.file)
        size = doc_settings:readSetting("kopt_font_size")
    end
    if size then
        return size * default_font_size
    elseif G_reader_settings:readSetting("kopt_font_size") then
        return G_reader_settings:readSetting("kopt_font_size") * default_font_size
    elseif G_defaults:readSetting("DKOPTREADER_CONFIG_FONT_SIZE") then
        return G_defaults:readSetting("DKOPTREADER_CONFIG_FONT_SIZE") * default_font_size
    else
        return default_font_size
    end
end

function PdfDocument:unlock(password)
    if not self._document:authenticatePassword(password) then
        return false
    end
    self.is_locked = false
    self:_readMetadata()
    return true
end

function PdfDocument:comparePositions(pos1, pos2)
    return self.koptinterface:comparePositions(self, pos1, pos2)
end

function PdfDocument:getPageTextBoxes(pageno)
    local hash = "textbox|"..self.file.."|"..pageno
    local cached = DocCache:check(hash)
    if not cached then
        local page = self._document:openPage(pageno)
        local text = page:getPageText()
        page:close()
        DocCache:insert(hash, CacheItem:new{text=text, size=text.size})
        return text
    else
        return cached.text
    end
end

function PdfDocument:getPanelFromPage(pageno, pos)
    return self.koptinterface:getPanelFromPage(self, pageno, pos)
end

function PdfDocument:getWordFromPosition(spos)
    return self.koptinterface:getWordFromPosition(self, spos)
end

function PdfDocument:getTextFromPositions(spos0, spos1)
    return self.koptinterface:getTextFromPositions(self, spos0, spos1)
end

function PdfDocument:getTextBoxes(pageno)
    return self.koptinterface:getTextBoxes(self, pageno)
end

function PdfDocument:getPageBoxesFromPositions(pageno, ppos0, ppos1)
    return self.koptinterface:getPageBoxesFromPositions(self, pageno, ppos0, ppos1)
end

function PdfDocument:nativeToPageRectTransform(pageno, rect)
    return self.koptinterface:nativeToPageRectTransform(self, pageno, rect)
end

function PdfDocument:getSelectedWordContext(word, nb_words, pos)
    return self.koptinterface:getSelectedWordContext(word, nb_words, pos)
end

function PdfDocument:getOCRWord(pageno, wbox)
    return self.koptinterface:getOCRWord(self, pageno, wbox)
end

function PdfDocument:getOCRText(pageno, tboxes)
    return self.koptinterface:getOCRText(self, pageno, tboxes)
end

function PdfDocument:getPageBlock(pageno, x, y)
    return self.koptinterface:getPageBlock(self, pageno, x, y)
end

function PdfDocument:getUsedBBox(pageno)
    local hash = "pgubbox|"..self.file.."|"..self.reflowable_font_size.."|"..pageno
    local cached = DocCache:check(hash)
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
    DocCache:insert(hash, CacheItem:new{
        ubbox = used,
        size = 256, -- might be closer to 160
    })
    page:close()
    return used
end

function PdfDocument:getPageLinks(pageno)
    local hash = "pglinks|"..self.file.."|"..self.reflowable_font_size.."|"..pageno
    local cached = DocCache:check(hash)
    if cached then
        return cached.links
    end
    local page = self._document:openPage(pageno)
    local links = page:getPageLinks()
    DocCache:insert(hash, CacheItem:new{
        links = links,
        size = 64 + (8 * 32 * #links),
    })
    page:close()
    return links
end

-- returns nil if file is not a pdf, true if document is a writable pdf, false else
function PdfDocument:_checkIfWritable()
    local suffix = util.getFileNameSuffix(self.file)
    if string.lower(suffix) ~= "pdf" then return nil end
    if self.is_writable == nil then
        local handle = io.open(self.file, 'r+b')
        self.is_writable = handle ~= nil
        if handle then handle:close() end
    end
    return self.is_writable
end

local function _quadpointsFromPboxes(pboxes)
    -- will also need mupdf_h.lua to be evaluated once
    -- but this is guaranteed at this point
    local n = #pboxes
    local quadpoints = ffi.new("fz_quad[?]", n)
    for i=1, n do
        -- The order must be left bottom, right bottom, left top, right top.
        -- https://bugs.ghostscript.com/show_bug.cgi?id=695130
        quadpoints[i-1].ll.x = pboxes[i].x
        quadpoints[i-1].ll.y = pboxes[i].y + pboxes[i].h - 1
        quadpoints[i-1].lr.x = pboxes[i].x + pboxes[i].w - 1
        quadpoints[i-1].lr.y = pboxes[i].y + pboxes[i].h - 1
        quadpoints[i-1].ul.x = pboxes[i].x
        quadpoints[i-1].ul.y = pboxes[i].y
        quadpoints[i-1].ur.x = pboxes[i].x + pboxes[i].w - 1
        quadpoints[i-1].ur.y = pboxes[i].y
    end
    return quadpoints, n
end

local function _quadpointsToPboxes(quadpoints, n)
    -- reverse of previous function
    local pboxes = {}
    for i=1, n do
        table.insert(pboxes, {
            x = quadpoints[i-1].ul.x,
            y = quadpoints[i-1].ul.y,
            w = quadpoints[i-1].lr.x - quadpoints[i-1].ul.x + 1,
            h = quadpoints[i-1].lr.y - quadpoints[i-1].ul.y + 1,
        })
    end
    return pboxes
end

function PdfDocument:saveHighlight(pageno, item)
    local can_write = self:_checkIfWritable()
    if can_write ~= true then return can_write end

    self.is_edited = true
    local quadpoints, n = _quadpointsFromPboxes(item.pboxes)
    local page = self._document:openPage(pageno)
    local annot_type = C.PDF_ANNOT_HIGHLIGHT
    local annot_color = item.color and BlitBuffer.colorFromName(item.color)
    if item.drawer == "lighten" then
        annot_type = C.PDF_ANNOT_HIGHLIGHT
    elseif item.drawer == "underscore" then
        annot_type = C.PDF_ANNOT_UNDERLINE
    elseif item.drawer == "strikeout" then
        annot_type = C.PDF_ANNOT_STRIKE_OUT
    end
    -- NOTE: For highlights, display style may differ compared to ReaderView:drawHighlightRect...
    --       (e.g., we do a MUL blend, MuPDF currently appears to do an OVER blend).
    page:addMarkupAnnotation(quadpoints, n, annot_type, annot_color) -- may update/adjust quadpoints
    -- Update pboxes with the possibly adjusted coordinates (this will have it updated
    -- in self.view.highlight.saved[page])
    item.pboxes = _quadpointsToPboxes(quadpoints, n)
    page:close()
    self:resetTileCacheValidity()
end

function PdfDocument:deleteHighlight(pageno, item)
    local can_write = self:_checkIfWritable()
    if can_write ~= true then return can_write end

    self.is_edited = true
    local quadpoints, n = _quadpointsFromPboxes(item.pboxes)
    local page = self._document:openPage(pageno)
    local annot = page:getMarkupAnnotation(quadpoints, n)
    if annot ~= nil then
        page:deleteMarkupAnnotation(annot)
        self:resetTileCacheValidity()
    end
    page:close()
end

function PdfDocument:updateHighlightContents(pageno, item, contents)
    local can_write = self:_checkIfWritable()
    if can_write ~= true then return can_write end

    self.is_edited = true
    local quadpoints, n = _quadpointsFromPboxes(item.pboxes)
    local page = self._document:openPage(pageno)
    local annot = page:getMarkupAnnotation(quadpoints, n)
    if annot ~= nil then
        page:updateMarkupAnnotation(annot, contents)
        self:resetTileCacheValidity()
    end
    page:close()
end

function PdfDocument:writeDocument()
    logger.info("writing document to", self.file)
    self._document:writeDocument(self.file)
end

function PdfDocument:close()
    -- NOTE: We can't just rely on Document:close's return code for that, as we need self._document
    --       in :writeDocument, and it would have been destroyed.
    local DocumentRegistry = require("document/documentregistry")
    if DocumentRegistry:getReferenceCount(self.file) == 1 then
        -- We're the final reference to this Document instance.
        if self.is_edited then
            self:writeDocument()
        end
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

function PdfDocument:findText(pattern, origin, reverse, case_insensitive, page)
    return self.koptinterface:findText(self, pattern, origin, reverse, case_insensitive, page)
end

function PdfDocument:findAllText(pattern, case_insensitive, nb_context_words, max_hits)
    return self.koptinterface:findAllText(self, pattern, case_insensitive, nb_context_words, max_hits)
end

function PdfDocument:renderPage(pageno, rect, zoom, rotation, gamma, hinting)
    return self.koptinterface:renderPage(self, pageno, rect, zoom, rotation, gamma, hinting)
end

function PdfDocument:hintPage(pageno, zoom, rotation, gamma)
    return self.koptinterface:hintPage(self, pageno, zoom, rotation, gamma)
end

function PdfDocument:drawPage(target, x, y, rect, pageno, zoom, rotation, gamma)
    return self.koptinterface:drawPage(self, target, x, y, rect, pageno, zoom, rotation, gamma)
end

function PdfDocument:register(registry)
    --- Document types ---
    registry:addProvider("cbt", "application/vnd.comicbook+tar", self, 100)
    registry:addProvider("cbz", "application/vnd.comicbook+zip", self, 100)
    registry:addProvider("cbz", "application/x-cbz", self, 100) -- Alternative mimetype for OPDS.
    registry:addProvider("cfb", "application/octet-stream", self, 80) -- Compound File Binary, a Microsoft general-purpose file with a file-system-like structure.
    registry:addProvider("docx", "application/vnd.openxmlformats-officedocument.wordprocessingml.document", self, 80)
    registry:addProvider("epub", "application/epub+zip", self, 50)
    registry:addProvider("epub3", "application/epub+zip", self, 50)
    registry:addProvider("fb2", "application/fb2", self, 80)
    registry:addProvider("htm", "text/html", self, 90)
    registry:addProvider("html", "text/html", self, 90)
    registry:addProvider("mobi", "application/x-mobipocket-ebook", self, 80)
    registry:addProvider("pdf", "application/pdf", self, 100)
    registry:addProvider("pptx", "application/vnd.openxmlformats-officedocument.presentationml.presentation", self, 80)
    registry:addProvider("tar", "application/x-tar", self, 10)
    registry:addProvider("txt", "text/plain", self, 80)
    registry:addProvider("xhtml", "application/xhtml+xml", self, 90)
    registry:addProvider("xml", "application/xml", self, 10)
    registry:addProvider("xps", "application/oxps", self, 100)
    registry:addProvider("xlsx", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", self, 80)
    registry:addProvider("zip", "application/zip", self, 20)

    --- Picture types ---
    registry:addProvider("gif", "image/gif", self, 90)
    -- MS HD Photo == JPEG XR
    registry:addProvider("hdp", "image/vnd.ms-photo", self, 90)
    registry:addProvider("j2k", "image/jp2", self, 90)
    registry:addProvider("jp2", "image/jp2", self, 90)
    registry:addProvider("jpeg", "image/jpeg", self, 90)
    registry:addProvider("jpg", "image/jpeg", self, 90)
    -- JPEG XR
    registry:addProvider("jxr", "image/jxr", self, 90)
    registry:addProvider("pam", "image/x-portable-arbitrarymap", self, 90)
    registry:addProvider("pbm", "image/x‑portable‑bitmap", self, 90)
    registry:addProvider("pgm", "image/x‑portable‑bitmap", self, 90)
    registry:addProvider("png", "image/png", self, 90)
    registry:addProvider("pnm", "image/x‑portable‑bitmap", self, 90)
    registry:addProvider("ppm", "image/x‑portable‑bitmap", self, 90)
    registry:addProvider("svg", "image/svg+xml", self, 80)
    registry:addProvider("tif", "image/tiff", self, 90)
    registry:addProvider("tiff", "image/tiff", self, 90)
    -- Windows Media Photo == JPEG XR
    registry:addProvider("wdp", "image/vnd.ms-photo", self, 90)
end

return PdfDocument
