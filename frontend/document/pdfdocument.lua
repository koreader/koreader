local Blitbuffer = require("ffi/blitbuffer")
local CacheItem = require("cacheitem")
local CanvasContext = require("document/canvascontext")
local DocCache = require("document/doccache")
local DocSettings = require("docsettings")
local Document = require("document/document")
local DrawContext = require("ffi/drawcontext")
local logger = require("logger")
local TileCacheItem = require("document/tilecacheitem")
local UIManager = require("ui/uimanager")
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
    self._worker_broken = false
    self._worker_initialized = false
    -- 2-slot MRU/LRU cache of resolution-independent per-page display lists.
    self._display_list_slots = { {}, {} }
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

function PdfDocument:saveHighlight(pageno, item, annot_color)
    local can_write = self:_checkIfWritable()
    if can_write ~= true then return can_write end

    self.is_edited = true
    local quadpoints, n = _quadpointsFromPboxes(item.pboxes)
    local page = self._document:openPage(pageno)
    local annot_type = C.PDF_ANNOT_HIGHLIGHT
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
    self:_purgeDisplayListCache()
end

function PdfDocument:deleteHighlight(pageno, item)
    local can_write = self:_checkIfWritable()
    if can_write ~= true then return can_write end

    self.is_edited = true
    local quadpoints, n = _quadpointsFromPboxes(item.pboxes)
    local page = self._document:openPage(pageno)
    local annot = page:getMarkupAnnotation(quadpoints, n)
    if annot ~= nil then
        page:deleteAnnotation(annot)
        self:resetTileCacheValidity()
        self:_purgeDisplayListCache()
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
        self:_purgeDisplayListCache()
    end
    page:close()
end

function PdfDocument:getEmbeddedAnnotations()
    local annotations = {}
    for pageno = 1, self.info.number_of_pages do
        local page = self._document:openPage(pageno)
        local page_annots = page:getEmbeddedAnnotations()
        if page_annots then
            annotations[pageno] = page_annots
        end
        page:close()
    end
    return next(annotations) and annotations
end

function PdfDocument:writeDocument()
    logger.info("writing document to", self.file)
    self._document:writeDocument(self.file)
end

function PdfDocument:close()
    self._pending_hint = nil
    self:_clearPollTimer()
    if self._in_flight_job or (pdf and pdf.workerStatus() == pdf.WORKER_RUNNING) then
        pdf.workerAbort()
        pdf.workerWait()
        self._in_flight_job = nil
        CanvasContext:enableCPUCores(1)
    end
    if self._display_list_slots then
        self:_purgeDisplayListCache()
    end

    -- NOTE: We can't just rely on Document:close's return code for that, as we need self._document
    --       in :writeDocument, and it would have been destroyed.
    local DocumentRegistry = require("document/documentregistry")
    if DocumentRegistry:getReferenceCount(self.file) == 1 then
        -- We're the final reference to this Document instance.
        if self.is_edited then
            self:writeDocument()
        end
    end

    return Document.close(self)
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

function PdfDocument:getPageBBox(pageno, defer_busy)
    return self.koptinterface:getPageBBox(self, pageno, defer_busy)
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

function PdfDocument:renderPage(pageno, rect, zoom, rotation, gamma, saturation, hinting)
    return self.koptinterface:renderPage(self, pageno, rect, zoom, rotation, gamma, saturation, hinting)
end

function PdfDocument:hintPage(pageno, zoom, rotation, gamma, saturation, hint_rect, dispatch_only, use_bbox)
    return self.koptinterface:hintPage(self, pageno, zoom, rotation, gamma, saturation, hint_rect, dispatch_only, use_bbox)
end

function PdfDocument:drawPage(target, x, y, rect, pageno, zoom, rotation, gamma, saturation)
    return self.koptinterface:drawPage(self, target, x, y, rect, pageno, zoom, rotation, gamma, saturation)
end

function PdfDocument:register(registry)
    --- Document types ---
    registry:addProvider("cbr", "application/vnd.comicbook-rar", self, 100)
    registry:addProvider("cbr", "application/vnd.rar", self, 100)
    registry:addProvider("cbt", "application/vnd.comicbook+tar", self, 100)
    registry:addProvider("cbz", "application/vnd.comicbook+zip", self, 100)
    registry:addProvider("cbz", "application/x-cbz", self, 100) -- Alternative mimetype for OPDS.
    registry:addProvider("cfb", "application/octet-stream", self, 80) -- Compound File Binary, a Microsoft general-purpose file with a file-system-like structure.
    registry:addProvider("docx", "application/vnd.openxmlformats-officedocument.wordprocessingml.document", self, 80)
    registry:addProvider("docx", "application/docx", self, 80) -- Alternative mimetype for OPDS.
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

-- Asynchronous background hinting (c.f., base/mupdf_worker.c)

local POLL_INTERVAL_S = 0.02  -- UIManager polling cadence for job completion

function PdfDocument:_clearPollTimer()
    if self._in_flight_poll then
        UIManager:unschedule(self._in_flight_poll)
        self._in_flight_poll = nil
    end
end

--- Initialize the background rasterization worker once per process.
-- @treturn bool true when the worker is available
function PdfDocument:_ensureWorker()
    if self._worker_broken then
        return false
    end
    if not self._worker_initialized then
        local ok, ret = pcall(pdf.workerInit)
        if not ok then
            logger.warn("PdfDocument: cannot initialize background worker:", ret)
            self._worker_broken = true
            return false
        end
        if ret ~= 0 then
            logger.warn("PdfDocument: background worker init failed with code", ret)
            self._worker_broken = true
            return false
        end
        self._worker_initialized = true
    end
    return true
end

function PdfDocument:_colorspaceForWorker()
    if self.render_color then
        return pdf.bgr and pdf.WORKER_CS_BGR or pdf.WORKER_CS_RGB
    end
    return pdf.WORKER_CS_GRAY
end

--- Retrieve (or build and cache) the resolution-independent display list for `pageno`.
-- Uses a 2-slot MRU/LRU cache so zoomed viewport slices reuse the parsed list.
-- @tparam int pageno
-- @treturn[opt] cdata dlist
-- @treturn[opt] table cache entry
-- @treturn[opt] bool true if freshly built
function PdfDocument:_getDisplayList(pageno)
    local slots = self._display_list_slots
    local entry = slots[1]
    if entry.pageno == pageno then
        return entry.dlist, entry, false
    end
    entry = slots[2]
    if entry.pageno == pageno then
        slots[2], slots[1] = slots[1], slots[2]
        return slots[1].dlist, slots[1], false
    end

    local lru = slots[2]
    if lru.dlist then
        pdf.dropDisplayList(lru.dlist)
        lru.dlist = nil
        lru.pageno = nil
    end

    local page = self._document:openPage(pageno)
    local ok, dlist = pcall(pdf.newDisplayListFromPage, page)
    if not ok then
        page:close()
        logger.warn("PdfDocument: display list creation failed:", tostring(dlist))
        return nil
    end
    local page_w, page_h = page:getSize(self.dc_null)
    local has_transparency_mask = pdf.pageHasTransparencyMask(page.ctx, page.page) ~= 0
    page:close()

    slots[2] = slots[1]
    slots[1] = {
        pageno = pageno,
        dlist = dlist,
        page_bbox = { w = page_w, h = page_h },
        has_transparency_mask = has_transparency_mask,
    }
    return dlist, slots[1], true
end

function PdfDocument:_purgeDisplayListCache()
    for i = 1, 2 do
        local entry = self._display_list_slots[i]
        if entry.dlist then
            pdf.dropDisplayList(entry.dlist)
            entry.dlist = nil
            entry.pageno = nil
        end
    end
end

local function _jobMatchesTarget(job, pageno, rect, zoom, rotation, gamma, saturation)
    return job.pageno == pageno
        and job.zoom == zoom
        and job.rotation == rotation
        and job.gamma == gamma
        and job.saturation == saturation
        and (job.rect == nil or (rect ~= nil and tostring(job.rect) == tostring(rect)))
end

function PdfDocument:_jobStillRelevant(job)
    local pending = self._pending_hint
    if pending and _jobMatchesTarget(job, pending.pageno, pending.rect,
            pending.zoom, pending.rotation, pending.gamma, pending.saturation) then
        return true
    end
    local active = self._active_view
    if not active then
        return true
    end
    return job.pageno == active.pageno
        and job.zoom == active.zoom
        and job.rotation == active.rotation
        and job.gamma == active.gamma
        and job.saturation == active.saturation
        and (job.rect == nil or active.rect == nil
            or tostring(job.rect) == tostring(active.rect))
end

--- Park a hint while the worker is busy (latest wins); if the running job
-- no longer matches the active view or parked hint, abort and replace it.
function PdfDocument:_queuePendingHint(pageno, rect, zoom, rotation, gamma, saturation)
    local job = self._in_flight_job
    if _jobMatchesTarget(job, pageno, rect, zoom, rotation, gamma, saturation) then
        return
    end
    self._pending_hint = {
        pageno = pageno,
        rect = rect,
        zoom = zoom,
        rotation = rotation,
        gamma = gamma,
        saturation = saturation,
    }
    if not self:_jobStillRelevant(job) then
        self:_abortInFlightJob()
        self:_dispatchPendingHint()
    end
end

function PdfDocument:_dispatchPendingHint()
    local pending = self._pending_hint
    if not pending then
        return
    end
    self._pending_hint = nil
    self:hintPageAsync(pending.pageno, pending.rect, pending.zoom,
        pending.rotation, pending.gamma, pending.saturation, true)
end

--- Dispatch a hint job to the background worker.
-- @treturn bool true when already cached, dispatched, or parked asynchronously; false to fall back to sync
function PdfDocument:hintPageAsync(pageno, rect, zoom, rotation, gamma, saturation, dispatch_only)
    if not self:_ensureWorker() then
        return false
    end
    self:_drainFinishedWorker(true)

    -- Skip work if a valid tile is already in DocCache.
    local full_hash = self:getFullPageHash(pageno, zoom, rotation, gamma, saturation)
    local hash = rect and (full_hash .. "|" .. tostring(rect)) or full_hash
    local cached = DocCache:check(full_hash, TileCacheItem)
    if not cached and rect then
        cached = DocCache:check(hash)
    end
    if cached and (not self.tile_cache_validity_ts
            or (cached.created_ts and cached.created_ts >= self.tile_cache_validity_ts)) then
        return true
    end

    if self._in_flight_job then
        if dispatch_only then
            self:_queuePendingHint(pageno, rect, zoom, rotation, gamma, saturation)
            return true
        end
        return false
    end

    local size
    if rect then
        size = rect
    else
        size = self:getPageDimensions(pageno, zoom, rotation)
    end
    local size_x = size.x or 0
    local size_y = size.y or 0

    local dlist, dl_entry = self:_getDisplayList(pageno)
    if not dlist then
        return false
    end
    local transparency_mask = (self.configurable.background_cleanup or 0) ~= 0
        and dl_entry.has_transparency_mask or false

    -- Anchor bb on _in_flight_job so LuaJIT GC cannot collect it mid-render.
    local bb = Blitbuffer.new(size.w, size.h, self.render_color and self.color_bb_type or nil)
    if bb.stride ~= size.w * (self.render_color and 4 or 1) then
        logger.warn("PdfDocument: unexpected blitbuffer stride, hint stays synchronous")
        return false
    end

    -- Plain scale/rotate matrix without translate; bbox anchors the excerpt origin.
    local ctm = pdf.makeCTM(zoom, rotation, 0, 0)
    local bbox = ffi.new("fz_irect", size_x, size_y, size_x + size.w, size_y + size.h)
    local scissor = ffi.new("fz_rect", size_x, size_y, size_x + size.w, size_y + size.h)

    local res = pdf.workerSubmit(dlist, ctm, scissor, bbox,
        ffi.cast("unsigned char*", bb.data), bb.stride,
        self:_colorspaceForWorker(),
        self.render_color and 1 or 0,
        transparency_mask and 1 or 0,
        gamma, saturation)
    if res ~= 0 then
        logger.warn("PdfDocument: worker submit failed, hint stays synchronous")
        return false
    end

    CanvasContext:enableCPUCores(2)

    self._in_flight_job = {
        pageno = pageno,
        rect = rect,
        size = size,
        zoom = zoom,
        rotation = rotation,
        gamma = gamma,
        saturation = saturation,
        hash = hash,
        bb = bb,
    }

    self:_clearPollTimer()
    local function pollWorker()
        if not self._in_flight_job then
            self._in_flight_poll = nil
            return
        end
        local status = pdf.workerStatus()
        if status == pdf.WORKER_RUNNING then
            UIManager:scheduleIn(POLL_INTERVAL_S, pollWorker)
        elseif status == pdf.WORKER_DONE then
            self:_commitInFlightJob()
        else -- WORKER_ERROR or WORKER_ABORTED
            self._in_flight_job = nil
            self._in_flight_poll = nil
            CanvasContext:enableCPUCores(1)
        end
    end
    self._in_flight_poll = pollWorker
    UIManager:scheduleIn(POLL_INTERVAL_S, pollWorker)
    return true
end

--- Commit or clean up a worker job that settled between poll ticks.
-- @tparam[opt] bool suppress_dispatch keep the worker idle instead of launching `_pending_hint`
function PdfDocument:_drainFinishedWorker(suppress_dispatch)
    if not self._in_flight_job then
        return
    end
    local status = pdf.workerStatus()
    if status == pdf.WORKER_DONE then
        self:_commitInFlightJob(suppress_dispatch)
    elseif status ~= pdf.WORKER_RUNNING then
        self:_clearPollTimer()
        self._in_flight_job = nil
        CanvasContext:enableCPUCores(1)
    end
end

--- Insert a completed worker job's tile into `DocCache`.
-- @tparam[opt] bool suppress_dispatch keep the worker idle instead of launching `_pending_hint`
function PdfDocument:_commitInFlightJob(suppress_dispatch)
    local job = self._in_flight_job
    if not job then
        return
    end

    local tile = TileCacheItem:new{
        persistent = (job.rect == nil),
        doc_path = self.file,
        created_ts = os.time(),
        excerpt = job.size,
        pageno = job.pageno,
        bb = job.bb,
    }
    tile.size = tonumber(tile.bb.stride) * tile.bb.h + 512
    DocCache:insert(job.hash, tile)

    self:_clearPollTimer()
    self._in_flight_job = nil
    CanvasContext:enableCPUCores(1)
    if not suppress_dispatch then
        self:_dispatchPendingHint()
    end
end

function PdfDocument:hasPendingBackgroundRender()
    return self._in_flight_job ~= nil
        or (self._worker_initialized and not self._worker_broken
            and pdf.workerStatus() == pdf.WORKER_RUNNING)
end

function PdfDocument:abortBackgroundRender()
    self:_abortInFlightJob()
end

function PdfDocument:shouldDeferHint(cur_page, dir, view_state)
    self:_drainFinishedWorker(true)
    if not self:hasPendingBackgroundRender() then
        return false
    end
    local job = self._in_flight_job
    if not job or self:_jobStillRelevant(job)
            or (cur_page
                and job.rotation == view_state.rotation
                and job.gamma == view_state.gamma
                and job.saturation == view_state.saturation
                and ((job.pageno == cur_page and job.zoom == view_state.zoom)
                     or job.pageno == cur_page + dir)) then
        return true
    end
    self:abortBackgroundRender()
    return false
end

--- Abort the in-flight worker job and block until the worker thread is idle.
function PdfDocument:_abortInFlightJob()
    self:_drainFinishedWorker(true)
    local job = self._in_flight_job
    if not job then
        return
    end
    pdf.workerAbort()
    pdf.workerWait()
    self:_clearPollTimer()
    self._in_flight_job = nil
    CanvasContext:enableCPUCores(1)
end

--- Coalesce a synchronous `renderPage` miss with a matching in-flight job,
-- or abort an obsolete job so the caller can render synchronously.
-- @treturn[opt] string `"committed"`, `"covered"`, or nil
function PdfDocument:resolveInFlightHint(pageno, rect, zoom, rotation, gamma, saturation, hinting)
    self:_drainFinishedWorker(true)
    local job = self._in_flight_job
    if not job then
        return nil
    end

    local same_target = job.pageno == pageno
        and job.zoom == zoom
        and job.rotation == rotation
        and job.gamma == gamma
        and job.saturation == saturation
        and (job.rect == nil or (rect ~= nil and tostring(job.rect) == tostring(rect)))

    if same_target then
        if pdf.workerStatus() == pdf.WORKER_DONE then
            self:_commitInFlightJob(true)
            return "committed"
        end
        if hinting then
            return "covered"
        end
        local status = pdf.workerWait()
        if status ~= pdf.WORKER_DONE then
            self:_abortInFlightJob()
            return nil
        end
        self:_commitInFlightJob(true)
        return "committed"
    end

    self:_abortInFlightJob()
    return nil
end

return PdfDocument
