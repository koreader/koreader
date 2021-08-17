--[[--
Interface to k2pdfoptlib backend.
--]]

local CacheItem = require("cacheitem")
local CanvasContext = require("document/canvascontext")
local DataStorage = require("datastorage")
local DEBUG = require("dbg")
local DocCache = require("document/doccache")
local Document = require("document/document")
local Geom = require("ui/geometry")
local KOPTContext = require("ffi/koptcontext")
local Persist = require("persist")
local TileCacheItem = require("document/tilecacheitem")
local logger = require("logger")
local util = require("ffi/util")

local KoptInterface = {
    ocrengine = "ocrengine",
    tessocr_data = DataStorage:getDataDir() .. "/data",
    ocr_lang = "eng",
    ocr_type = 3, -- default 0, for more accuracy use 3
    last_context_size = nil,
    default_context_size = 1024*1024,
}

local ContextCacheItem = CacheItem:new{}

function ContextCacheItem:onFree()
    KoptInterface:waitForContext(self.kctx)
    logger.dbg("ContextCacheItem: free KOPTContext", self.kctx)
    self.kctx:free()
end

function ContextCacheItem:dump(filename)
    if self.kctx:isPreCache() == 0 then
        logger.dbg("Dumping KOPTContext to", filename)

        local cache_file = Persist:new{
            path = filename,
            codec = "zstd",
        }

        local t = KOPTContext.totable(self.kctx)
        t.cache_size = self.size

        local ok, size = cache_file:save(t)
        if ok then
            return size
        else
            logger.warn("Failed to dump KOPTContext")
            return nil
        end
    end
end

function ContextCacheItem:load(filename)
    logger.dbg("Loading KOPTContext from", filename)

    local cache_file = Persist:new{
        path = filename,
        codec = "zstd",
    }

    local t = cache_file:load(filename)
    if t then
        self.size = t.cache_size
        self.kctx = KOPTContext.fromtable(t)
    else
        logger.warn("Failed to load KOPTContext")
    end
end

local OCREngine = CacheItem:new{}

function OCREngine:onFree()
    if self.ocrengine.freeOCR then
        logger.dbg("free OCREngine", self.ocrengine)
        self.ocrengine:freeOCR()
    end
end

function KoptInterface:setDefaultConfigurable(configurable)
    configurable.doc_language = DKOPTREADER_CONFIG_DOC_DEFAULT_LANG_CODE
    configurable.trim_page = DKOPTREADER_CONFIG_TRIM_PAGE
    configurable.text_wrap = DKOPTREADER_CONFIG_TEXT_WRAP
    configurable.detect_indent = DKOPTREADER_CONFIG_DETECT_INDENT
    configurable.max_columns = DKOPTREADER_CONFIG_MAX_COLUMNS
    configurable.auto_straighten = DKOPTREADER_CONFIG_AUTO_STRAIGHTEN
    configurable.justification = DKOPTREADER_CONFIG_JUSTIFICATION
    configurable.writing_direction = 0
    configurable.font_size = DKOPTREADER_CONFIG_FONT_SIZE
    configurable.page_margin = DKOPTREADER_CONFIG_PAGE_MARGIN
    configurable.quality = DKOPTREADER_CONFIG_RENDER_QUALITY
    configurable.contrast = DKOPTREADER_CONFIG_CONTRAST
    configurable.defect_size = DKOPTREADER_CONFIG_DEFECT_SIZE
    configurable.line_spacing = DKOPTREADER_CONFIG_LINE_SPACING
    configurable.word_spacing = DKOPTREADER_CONFIG_DEFAULT_WORD_SPACING
end

function KoptInterface:waitForContext(kc)
    -- if koptcontext is being processed in background thread
    -- the isPreCache will return 1.
    while kc and kc:isPreCache() == 1 do
        logger.dbg("waiting for background rendering")
        util.usleep(100000)
    end
    return kc
end

--[[--
Get reflow context.
--]]
function KoptInterface:createContext(doc, pageno, bbox)
    -- Now koptcontext keeps track of its dst bitmap reflowed by libk2pdfopt.
    -- So there is no need to check background context when creating new context.
    local kc = KOPTContext.new()
    local canvas_size = CanvasContext:getSize()
    local lang = doc.configurable.doc_language
    if lang == "chi_sim" or lang == "chi_tra" or
        lang == "jpn" or lang == "kor" then
        kc:setCJKChar()
    end
    kc:setLanguage(lang)
    kc:setTrim(doc.configurable.trim_page)
    kc:setWrap(doc.configurable.text_wrap)
    kc:setIndent(doc.configurable.detect_indent)
    kc:setColumns(doc.configurable.max_columns)
    kc:setDeviceDim(canvas_size.w, canvas_size.h)
    kc:setDeviceDPI(CanvasContext:getDPI())
    kc:setStraighten(doc.configurable.auto_straighten)
    kc:setJustification(doc.configurable.justification)
    kc:setWritingDirection(doc.configurable.writing_direction)
    kc:setZoom(doc.configurable.font_size)
    kc:setMargin(doc.configurable.page_margin)
    kc:setQuality(doc.configurable.quality)
    kc:setContrast(doc.configurable.contrast)
    kc:setDefectSize(doc.configurable.defect_size)
    kc:setLineSpacing(doc.configurable.line_spacing)
    kc:setWordSpacing(doc.configurable.word_spacing)
    if bbox then
        if bbox.x0 >= bbox.x1 or bbox.y0 >= bbox.y1 then
            local page_size = Document.getNativePageDimensions(doc, pageno)
            bbox.x0, bbox.y0 = 0, 0
            bbox.x1, bbox.y1 = page_size.w, page_size.h
        end
        kc:setBBox(bbox.x0, bbox.y0, bbox.x1, bbox.y1)
    end
    if DEBUG.is_on then kc:setDebug() end
    return kc
end

function KoptInterface:getContextHash(doc, pageno, bbox, hash_list)
    local canvas_size = CanvasContext:getSize()
    table.insert(hash_list, doc.file)
    table.insert(hash_list, doc.mod_time)
    table.insert(hash_list, pageno)
    doc.configurable:hash(hash_list)
    table.insert(hash_list, bbox.x0)
    table.insert(hash_list, bbox.y0)
    table.insert(hash_list, bbox.x1)
    table.insert(hash_list, bbox.y1)
    table.insert(hash_list, canvas_size.w)
    table.insert(hash_list, canvas_size.h)
end

function KoptInterface:getPageBBox(doc, pageno)
    if doc.configurable.text_wrap ~= 1 and doc.configurable.trim_page == 1 then
        -- auto bbox finding
        return self:getAutoBBox(doc, pageno)
    elseif doc.configurable.text_wrap ~= 1 and doc.configurable.trim_page == 2 then
        -- semi-auto bbox finding
        return self:getSemiAutoBBox(doc, pageno)
    else
        -- get saved manual bbox
        return Document.getPageBBox(doc, pageno)
    end
end

--[[--
Auto detect bbox.
--]]
function KoptInterface:getAutoBBox(doc, pageno)
    local native_size = Document.getNativePageDimensions(doc, pageno)
    local bbox = {
        x0 = 0,
        y0 = 0,
        x1 = native_size.w,
        y1 = native_size.h,
    }
    local hash_list = { "autobbox" }
    self:getContextHash(doc, pageno, bbox, hash_list)
    local hash = table.concat(hash_list, "|")
    local cached = DocCache:check(hash)
    if not cached then
        local page = doc._document:openPage(pageno)
        local kc = self:createContext(doc, pageno, bbox)
        page:getPagePix(kc)
        local x0, y0, x1, y1 = kc:getAutoBBox()
        local w, h = native_size.w, native_size.h
        if (x1 - x0)/w > 0.1 or (y1 - y0)/h > 0.1 then
            bbox.x0, bbox.y0, bbox.x1, bbox.y1 = x0, y0, x1, y1
        else
            bbox = Document.getPageBBox(doc, pageno)
        end
        DocCache:insert(hash, CacheItem:new{ autobbox = bbox, size = 160 })
        page:close()
        kc:free()
        return bbox
    else
        return cached.autobbox
    end
end

--[[--
Detect bbox within user restricted bbox.
--]]
function KoptInterface:getSemiAutoBBox(doc, pageno)
    -- use manual bbox
    local bbox = Document.getPageBBox(doc, pageno)
    local hash_list = { "semiautobbox" }
    self:getContextHash(doc, pageno, bbox, hash_list)
    local hash = table.concat(hash_list, "|")
    local cached = DocCache:check(hash)
    if not cached then
        local page = doc._document:openPage(pageno)
        local kc = self:createContext(doc, pageno, bbox)
        local auto_bbox = {}
        page:getPagePix(kc)
        auto_bbox.x0, auto_bbox.y0, auto_bbox.x1, auto_bbox.y1 = kc:getAutoBBox()
        auto_bbox.x0 = auto_bbox.x0 + bbox.x0
        auto_bbox.y0 = auto_bbox.y0 + bbox.y0
        auto_bbox.x1 = auto_bbox.x1 + bbox.x0
        auto_bbox.y1 = auto_bbox.y1 + bbox.y0
        logger.dbg("Semi-auto detected bbox", auto_bbox)
        local native_size = Document.getNativePageDimensions(doc, pageno)
        if (auto_bbox.x1 - auto_bbox.x0)/native_size.w < 0.1 and (auto_bbox.y1 - auto_bbox.y0)/native_size.h < 0.1 then
            logger.dbg("Semi-auto detected bbox too small, using manual bbox")
            auto_bbox = bbox
        end
        page:close()
        DocCache:insert(hash, CacheItem:new{ semiautobbox = auto_bbox, size = 160 })
        kc:free()
        return auto_bbox
    else
        return cached.semiautobbox
    end
end

--[[--
Get cached koptcontext for a certain page.

If the context doesn't exist in cache, make a new context and reflow the src page
immediately, or wait for the background thread with reflowed context.
--]]
function KoptInterface:getCachedContext(doc, pageno)
    local bbox = doc:getPageBBox(pageno)
    local hash_list = { "kctx" }
    self:getContextHash(doc, pageno, bbox, hash_list)
    local hash = table.concat(hash_list, "|")
    local cached = DocCache:check(hash, ContextCacheItem)
    if not cached then
        -- If kctx is not cached, create one and get reflowed bmp in foreground.
        local kc = self:createContext(doc, pageno, bbox)
        local page = doc._document:openPage(pageno)
        logger.dbg("reflowing page", pageno, "in foreground")
        -- reflow page
        --local secs, usecs = util.gettime()
        page:reflow(kc, 0)
        page:close()
        --local nsecs, nusecs = util.gettime()
        --local dur = nsecs - secs + (nusecs - usecs) / 1000000
        --self:logReflowDuration(pageno, dur)
        local fullwidth, fullheight = kc:getPageDim()
        logger.dbg("reflowed page", pageno, "fullwidth:", fullwidth, "fullheight:", fullheight)
        self.last_context_size = fullwidth * fullheight + 3072 -- estimation
        DocCache:insert(hash, ContextCacheItem:new{
            persistent = true,
            size = self.last_context_size,
            kctx = kc
        })
        return kc
    else
        -- wait for background thread
        local kc = self:waitForContext(cached.kctx)
        local fullwidth, fullheight = kc:getPageDim()
        self.last_context_size = fullwidth * fullheight + 3072 -- estimation
        return kc
    end
end

--[[--
Get page dimensions.
--]]
function KoptInterface:getPageDimensions(doc, pageno, zoom, rotation)
    if doc.configurable.text_wrap == 1 then
        return self:getRFPageDimensions(doc, pageno, zoom, rotation)
    else
        return Document.getPageDimensions(doc, pageno, zoom, rotation)
    end
end

--[[--
Get reflowed page dimensions.
--]]
function KoptInterface:getRFPageDimensions(doc, pageno, zoom, rotation)
    local kc = self:getCachedContext(doc, pageno)
    local fullwidth, fullheight = kc:getPageDim()
    return Geom:new{ w = fullwidth, h = fullheight }
end

--[[--
Get first page image.
--]]
function KoptInterface:getCoverPageImage(doc)
    local native_size = Document.getNativePageDimensions(doc, 1)
    local canvas_size = CanvasContext:getSize()
    local zoom = math.min(canvas_size.w / native_size.w, canvas_size.h / native_size.h)
    local tile = Document.renderPage(doc, 1, nil, zoom, 0, 1, 0)
    if tile then
        return tile.bb:copy()
    end
end

function KoptInterface:renderPage(doc, pageno, rect, zoom, rotation, gamma, render_mode)
    if doc.configurable.text_wrap == 1 then
        return self:renderReflowedPage(doc, pageno, rect, zoom, rotation, render_mode)
    elseif doc.configurable.page_opt == 1 then
        return self:renderOptimizedPage(doc, pageno, rect, zoom, rotation, render_mode)
    else
        return Document.renderPage(doc, pageno, rect, zoom, rotation, gamma, render_mode)
    end
end

--[[--
Render reflowed page into tile cache.

Inherited from common document interface.
--]]
function KoptInterface:renderReflowedPage(doc, pageno, rect, zoom, rotation, render_mode)
    doc.render_mode = render_mode
    local bbox = doc:getPageBBox(pageno)
    local hash_list = { "renderpg" }
    self:getContextHash(doc, pageno, bbox, hash_list)
    local hash = table.concat(hash_list, "|")

    local cached = DocCache:check(hash)
    if not cached then
        -- do the real reflowing if kctx has not been cached yet
        local kc = self:getCachedContext(doc, pageno)
        local fullwidth, fullheight = kc:getPageDim()
        if not DocCache:willAccept(fullwidth * fullheight) then
            -- whole page won't fit into cache
            error("aborting, since we don't have enough cache for this page")
        end
        -- prepare cache item with contained blitbuffer
        local tile = TileCacheItem:new{
            excerpt = Geom:new{ w = fullwidth, h = fullheight },
            pageno = pageno,
        }
        tile.bb = kc:dstToBlitBuffer()
        tile.size = tonumber(tile.bb.stride) * tile.bb.h + 512 -- estimation
        DocCache:insert(hash, tile)
        return tile
    else
        return cached
    end
end

--[[--
Render optimized page into tile cache.

Inherited from common document interface.
--]]
function KoptInterface:renderOptimizedPage(doc, pageno, rect, zoom, rotation, render_mode)
    doc.render_mode = render_mode
    local bbox = doc:getPageBBox(pageno)
    local hash_list = { "renderoptpg" }
    self:getContextHash(doc, pageno, bbox, hash_list)
    local hash = table.concat(hash_list, "|")

    local cached = DocCache:check(hash, TileCacheItem)
    if not cached then
        local page_size = Document.getNativePageDimensions(doc, pageno)
        local full_page_bbox = {
            x0 = 0, y0 = 0,
            x1 = page_size.w,
            y1 = page_size.h,
        }
        local kc = self:createContext(doc, pageno, full_page_bbox)
        local page = doc._document:openPage(pageno)
        kc:setZoom(zoom)
        page:getPagePix(kc)
        page:close()
        logger.dbg("optimizing page", pageno)
        kc:optimizePage()
        local fullwidth, fullheight = kc:getPageDim()
        -- prepare cache item with contained blitbuffer
        local tile = TileCacheItem:new{
            persistent = true,
            excerpt = Geom:new{
                x = 0, y = 0,
                w = fullwidth,
                h = fullheight
            },
            pageno = pageno,
        }
        tile.bb = kc:dstToBlitBuffer()
        tile.size = tonumber(tile.bb.stride) * tile.bb.h + 512 -- estimation
        kc:free()
        DocCache:insert(hash, tile)
        return tile
    else
        return cached
    end
end

function KoptInterface:hintPage(doc, pageno, zoom, rotation, gamma, render_mode)
    if doc.configurable.text_wrap == 1 then
        self:hintReflowedPage(doc, pageno, zoom, rotation, gamma, render_mode)
    elseif doc.configurable.page_opt == 1 then
        self:renderOptimizedPage(doc, pageno, nil, zoom, rotation, gamma, render_mode)
    else
        Document.hintPage(doc, pageno, zoom, rotation, gamma, render_mode)
    end
end

--[[--
Render reflowed page into cache in background thread.

This method returns immediately, leaving the precache flag on
in context. Subsequent usage of this context should wait for the precache flag
off by calling self:waitForContext(kctx)

Inherited from common document interface.
--]]
function KoptInterface:hintReflowedPage(doc, pageno, zoom, rotation, gamma, render_mode)
    local bbox = doc:getPageBBox(pageno)
    local hash_list = { "kctx" }
    self:getContextHash(doc, pageno, bbox, hash_list)
    local hash = table.concat(hash_list, "|")
    local cached = DocCache:check(hash)
    if not cached then
        local kc = self:createContext(doc, pageno, bbox)
        local page = doc._document:openPage(pageno)
        logger.dbg("hinting page", pageno, "in background")
        -- reflow will return immediately and running in background thread
        kc:setPreCache()
        page:reflow(kc, 0)
        page:close()
        DocCache:insert(hash, ContextCacheItem:new{
            size = self.last_context_size or self.default_context_size,
            kctx = kc,
        })
    end
end

function KoptInterface:drawPage(doc, target, x, y, rect, pageno, zoom, rotation, gamma, render_mode)
    if doc.configurable.text_wrap == 1 then
        self:drawContextPage(doc, target, x, y, rect, pageno, zoom, rotation, render_mode)
    elseif doc.configurable.page_opt == 1 then
        self:drawContextPage(doc, target, x, y, rect, pageno, zoom, rotation, render_mode)
    else
        Document.drawPage(doc, target, x, y, rect, pageno, zoom, rotation, gamma, render_mode)
    end
end

--[[--
Draw cached tile pixels into target blitbuffer.

Inherited from common document interface.
--]]
function KoptInterface:drawContextPage(doc, target, x, y, rect, pageno, zoom, rotation, render_mode)
    local tile = self:renderPage(doc, pageno, rect, zoom, rotation, render_mode)
    target:blitFrom(tile.bb,
        x, y,
        rect.x - tile.excerpt.x,
        rect.y - tile.excerpt.y,
        rect.w, rect.h)
end

--[[
Extract text boxes in a MuPDF/Djvu page.

Returned boxes are in native page coordinates zoomed at `1.0`.
--]]
function KoptInterface:getTextBoxes(doc, pageno)
    local text = doc:getPageTextBoxes(pageno)
    if text and #text > 1 and doc.configurable.forced_ocr ~= 1 then
        return text
    -- if we have no text in original page then we will reuse native word boxes
    -- in reflow mode and find text boxes from scratch in non-reflow mode
    else
        if doc.configurable.text_wrap == 1 then
            return self:getNativeTextBoxes(doc, pageno)
        else
            return self:getNativeTextBoxesFromScratch(doc, pageno)
        end
    end
end

--[[--
Get text boxes in reflowed page via rectmaps in koptcontext.
--]]
function KoptInterface:getReflowedTextBoxes(doc, pageno)
    local bbox = doc:getPageBBox(pageno)
    local hash_list = { "rfpgboxes" }
    self:getContextHash(doc, pageno, bbox, hash_list)
    local hash = table.concat(hash_list, "|")
    local cached = DocCache:check(hash)
    if not cached then
        local kctx_hash = hash:gsub("^rfpgboxes|", "kctx|")
        cached = DocCache:check(kctx_hash)
        if cached then
            local kc = self:waitForContext(cached.kctx)
            --kc:setDebug()
            local fullwidth, fullheight = kc:getPageDim()
            local boxes, nr_word = kc:getReflowedWordBoxes("dst", 0, 0, fullwidth, fullheight)
            if not boxes then
                return nil
            end
            DocCache:insert(hash, CacheItem:new{ rfpgboxes = boxes, size = 192 * nr_word }) -- estimation
            return boxes
        end
    else
        return cached.rfpgboxes
    end
end

--[[--
Get text boxes in native page via rectmaps in koptcontext.
--]]
function KoptInterface:getNativeTextBoxes(doc, pageno)
    local bbox = doc:getPageBBox(pageno)
    local hash_list = { "nativepgboxes" }
    self:getContextHash(doc, pageno, bbox, hash_list)
    local hash = table.concat(hash_list, "|")
    local cached = DocCache:check(hash)
    if not cached then
        local kctx_hash = hash:gsub("^nativepgboxes|", "kctx|")
        cached = DocCache:check(kctx_hash)
        if cached then
            local kc = self:waitForContext(cached.kctx)
            --kc:setDebug()
            local fullwidth, fullheight = kc:getPageDim()
            local boxes, nr_word = kc:getNativeWordBoxes("dst", 0, 0, fullwidth, fullheight)
            if not boxes then
                return nil
            end
            DocCache:insert(hash, CacheItem:new{ nativepgboxes = boxes, size = 192 * nr_word }) -- estimation
            return boxes
        end
    else
        return cached.nativepgboxes
    end
end

--[[--
Get text boxes in reflowed page via optical method.

Done by OCR pre-processing in Tesseract and Leptonica.
--]]
function KoptInterface:getReflowedTextBoxesFromScratch(doc, pageno)
    local bbox = doc:getPageBBox(pageno)
    local hash_list = { "scratchrfpgboxes" }
    self:getContextHash(doc, pageno, bbox, hash_list)
    local hash = table.concat(hash_list, "|")
    local cached = DocCache:check(hash)
    if not cached then
        local kctx_hash = hash:gsub("^scratchrfpgboxes|", "kctx|")
        cached = DocCache:check(kctx_hash)
        if cached then
            local reflowed_kc = self:waitForContext(cached.kctx)
            local fullwidth, fullheight = reflowed_kc:getPageDim()
            local kc = self:createContext(doc, pageno)
            kc:copyDestBMP(reflowed_kc)
            local boxes, nr_word = kc:getNativeWordBoxes("dst", 0, 0, fullwidth, fullheight)
            kc:free()
            if not boxes then
                return nil
            end
            DocCache:insert(hash, CacheItem:new{ scratchrfpgboxes = boxes, size = 192 * nr_word }) -- estimation
            return boxes
        end
    else
        return cached.scratchrfpgboxes
    end
end

function KoptInterface:getPanelFromPage(doc, pageno, ges)
    local page_size = Document.getNativePageDimensions(doc, pageno)
    local bbox = {
        x0 = 0, y0 = 0,
        x1 = page_size.w,
        y1 = page_size.h,
    }
    local kc = self:createContext(doc, pageno, bbox)
    kc:setZoom(1.0)
    local page = doc._document:openPage(pageno)
    page:getPagePix(kc)
    local panel = kc:getPanelFromPage(ges)
    page:close()
    kc:free()
    return panel
end

--[[--
Get text boxes in native page via optical method.

Done by OCR pre-processing in Tesseract and Leptonica.
--]]
function KoptInterface:getNativeTextBoxesFromScratch(doc, pageno)
    local hash = "scratchnativepgboxes|"..doc.file.."|"..pageno
    local cached = DocCache:check(hash)
    if not cached then
        local page_size = Document.getNativePageDimensions(doc, pageno)
        local bbox = {
            x0 = 0, y0 = 0,
            x1 = page_size.w,
            y1 = page_size.h,
        }
        local kc = self:createContext(doc, pageno, bbox)
        kc:setZoom(1.0)
        local page = doc._document:openPage(pageno)
        page:getPagePix(kc)
        local boxes, nr_word = kc:getNativeWordBoxes("src", 0, 0, page_size.w, page_size.h)
        DocCache:insert(hash, CacheItem:new{ scratchnativepgboxes = boxes, size = 192 * nr_word }) -- estimation
        page:close()
        kc:free()
        return boxes
    else
        return cached.scratchnativepgboxes
    end
end

--[[--
Get page regions in native page via optical method.
--]]
function KoptInterface:getPageBlock(doc, pageno, x, y)
    local kctx
    local bbox = doc:getPageBBox(pageno)
    local hash_list = { "pageblocks" }
    self:getContextHash(doc, pageno, bbox, hash_list)
    local hash = table.concat(hash_list, "|")
    local cached = DocCache:check(hash)
    if not cached then
        local page_size = Document.getNativePageDimensions(doc, pageno)
        local full_page_bbox = {
            x0 = 0, y0 = 0,
            x1 = page_size.w,
            y1 = page_size.h,
        }
        local kc = self:createContext(doc, pageno, full_page_bbox)
        -- leptonica needs a source image of at least 300dpi
        kc:setZoom(CanvasContext:getWidth() / page_size.w * 300 / CanvasContext:getDPI())
        local page = doc._document:openPage(pageno)
        page:getPagePix(kc)
        kc:findPageBlocks()
        DocCache:insert(hash, CacheItem:new{ kctx = kc, size = 3072 }) -- estimation
        page:close()
        kctx = kc
    else
        kctx = cached.kctx
    end
    return kctx:getPageBlock(x, y)
end

--[[--
Get word from OCR providing selected word box.
--]]
function KoptInterface:getOCRWord(doc, pageno, wbox)
    if not DocCache:check(self.ocrengine) then
        DocCache:insert(self.ocrengine, OCREngine:new{ ocrengine = KOPTContext.new(), size = 3072 }) -- estimation
    end
    if doc.configurable.text_wrap == 1 then
        return self:getReflewOCRWord(doc, pageno, wbox.sbox)
    else
        return self:getNativeOCRWord(doc, pageno, wbox.sbox)
    end
end

--[[--
Get word from OCR in reflew page.
--]]
function KoptInterface:getReflewOCRWord(doc, pageno, rect)
    self.ocr_lang = doc.configurable.doc_language
    local bbox = doc:getPageBBox(pageno)
    local hash_list = { "rfocrword" }
    self:getContextHash(doc, pageno, bbox, hash_list)
    table.insert(hash_list, rect.x)
    table.insert(hash_list, rect.y)
    table.insert(hash_list, rect.w)
    table.insert(hash_list, rect.h)
    local hash = table.concat(hash_list, "|")
    local cached = DocCache:check(hash)
    if not cached then
        local kctx_hash = hash:gsub("^rfocrword|", "kctx|")
        cached = DocCache:check(kctx_hash)
        if cached then
            local kc = self:waitForContext(cached.kctx)
            local _, word = pcall(
                kc.getTOCRWord, kc, "dst",
                rect.x, rect.y, rect.w, rect.h,
                self.tessocr_data, self.ocr_lang, self.ocr_type, 0, 1)
            DocCache:insert(hash, CacheItem:new{ rfocrword = word, size = #word + 64 }) -- estimation
            return word
        end
    else
        return cached.rfocrword
    end
end

--[[--
Get word from OCR in native page.
--]]
function KoptInterface:getNativeOCRWord(doc, pageno, rect)
    self.ocr_lang = doc.configurable.doc_language
    local hash = "ocrword|"..doc.file.."|"..pageno..rect.x..rect.y..rect.w..rect.h
    logger.dbg("hash", hash)
    local cached = DocCache:check(hash)
    if not cached then
        local bbox = {
            x0 = rect.x - math.floor(rect.h * 0.3),
            y0 = rect.y - math.floor(rect.h * 0.3),
            x1 = rect.x + rect.w + math.floor(rect.h * 0.3),
            y1 = rect.y + rect.h + math.floor(rect.h * 0.3),
        }
        local kc = self:createContext(doc, pageno, bbox)
        kc:setZoom(30/rect.h)
        local page = doc._document:openPage(pageno)
        page:getPagePix(kc)
        --kc:exportSrcPNGFile({rect}, nil, "ocr-word.png")
        local word_w, word_h = kc:getPageDim()
        local _, word = pcall(
            kc.getTOCRWord, kc, "src",
            0, 0, word_w, word_h,
            self.tessocr_data, self.ocr_lang, self.ocr_type, 0, 1)
        DocCache:insert(hash, CacheItem:new{ ocrword = word, size = #word + 64 }) -- estimation
        logger.dbg("word", word)
        page:close()
        kc:free()
        return word
    else
        return cached.ocrword
    end
end

--[[--
Get text from OCR providing selected text boxes.
--]]
function KoptInterface:getOCRText(doc, pageno, tboxes)
    if not DocCache:check(self.ocrengine) then
        DocCache:insert(self.ocrengine, OCREngine:new{ ocrengine = KOPTContext.new(), size = 3072 }) -- estimation
    end
    logger.info("Not implemented yet")
end

function KoptInterface:getClipPageContext(doc, pos0, pos1, pboxes, drawer)
    assert(pos0.page == pos1.page)
    assert(pos0.zoom == pos1.zoom)
    local rect
    if pboxes and #pboxes > 0 then
        local box = pboxes[1]
        rect = Geom:new{
            x = box.x, y = box.y,
            w = box.w, h = box.h,
        }
        for _, _box in ipairs(pboxes) do
            rect = rect:combine(Geom:new(_box))
        end
    else
        local zoom = pos0.zoom or 1
        rect = {
            x = math.min(pos0.x, pos1.x)/zoom,
            y = math.min(pos0.y, pos1.y)/zoom,
            w = math.abs(pos0.x - pos1.x)/zoom,
            h = math.abs(pos0.y - pos1.y)/zoom
        }
    end

    local bbox = {
        x0 = rect.x, y0 = rect.y,
        x1 = rect.x + rect.w,
        y1 = rect.y + rect.h
    }
    local kc = self:createContext(doc, pos0.page, bbox)
    local page = doc._document:openPage(pos0.page)
    page:getPagePix(kc)
    page:close()
    return kc, rect
end

function KoptInterface:clipPagePNGFile(doc, pos0, pos1, pboxes, drawer, filename)
    local kc = self:getClipPageContext(doc, pos0, pos1, pboxes, drawer)
    kc:exportSrcPNGFile(pboxes, drawer, filename)
    kc:free()
end

function KoptInterface:clipPagePNGString(doc, pos0, pos1, pboxes, drawer)
    local kc = self:getClipPageContext(doc, pos0, pos1, pboxes, drawer)
    -- there is no fmemopen in Android so leptonica.pixWriteMemPng will
    -- fail silently, workaround is creating a PNG file and read back the string
    local png = nil
    if util.isAndroid() then
        local tmp = "cache/tmpclippng.png"
        kc:exportSrcPNGFile(pboxes, drawer, tmp)
        local pngfile = io.open(tmp, "rb")
        if pngfile then
            png = pngfile:read("*all")
            pngfile:close()
        end
    else
        png = kc:exportSrcPNGString(pboxes, drawer)
    end
    kc:free()
    return png
end

--[[--
Get index of nearest word box around `pos`.
--]]
local function inside_box(box, pos)
    local x, y = pos.x, pos.y
    if box.x0 <= x and box.y0 <= y and box.x1 >= x and box.y1 >= y then
        return true
    end
    return false
end

local function box_distance(box, pos)
    if inside_box(box, pos) then
        return 0
    else
        local x0, y0 = pos.x, pos.y
        local x1, y1 = (box.x0 + box.x1) / 2, (box.y0 + box.y1) / 2
        return (x0 - x1)*(x0 - x1) + (y0 - y1)*(y0 - y1)
    end
end

local function getWordBoxIndices(boxes, pos)
    local m, n = 1, 1
    for i = 1, #boxes do
        for j = 1, #boxes[i] do
            if box_distance(boxes[i][j], pos) < box_distance(boxes[m][n], pos) then
                m, n = i, j
            end
        end
    end
    return m, n
end

--[[--
Get word and word box around `pos`.
--]]
function KoptInterface:getWordFromBoxes(boxes, pos)
    if not pos or not boxes or #boxes == 0 then return {} end
    local i, j = getWordBoxIndices(boxes, pos)
    local lb = boxes[i]
    local wb = boxes[i][j]
    if lb and wb then
        local box = Geom:new{
            x = wb.x0, y = lb.y0,
            w = wb.x1 - wb.x0,
            h = lb.y1 - lb.y0,
        }
        return {
            word = wb.word,
            box = box,
        }
    end
end

--[[--
Get text and text boxes between `pos0` and `pos1`.
--]]
function KoptInterface:getTextFromBoxes(boxes, pos0, pos1)
    if not pos0 or not pos1 or #boxes == 0 then return {} end
    local isCJKChar = require("util").isCJKChar
    local line_text = ""
    local line_boxes = {}
    local i_start, j_start = getWordBoxIndices(boxes, pos0)
    local i_stop, j_stop = getWordBoxIndices(boxes, pos1)
    if i_start == i_stop and j_start > j_stop or i_start > i_stop then
        i_start, i_stop = i_stop, i_start
        j_start, j_stop = j_stop, j_start
    end
    for i = i_start, i_stop do
        if i_start == i_stop and #boxes[i] == 0 then break end
        -- insert line words
        local j0 = i > i_start and 1 or j_start
        local j1 = i < i_stop and #boxes[i] or j_stop
        local line_first_word_seen = false
        local prev_word
        local prev_word_end_x
        for j = j0, j1 do
            local word = boxes[i][j].word
            if word then
                if not line_first_word_seen then
                    line_first_word_seen = true
                    if #line_text > 0 then
                        if line_text:sub(-1) == "-" then
                            -- Previous line ended with a minus.
                            -- Assume it's some hyphenation and discard it.
                            line_text = line_text:sub(1, -2)
                        elseif line_text:sub(-2, -1) == "\xC2\xAD" then
                            -- Previous line ended with a hyphen.
                            -- Assume it's some hyphenation and discard it.
                            line_text = line_text:sub(1, -3)
                        else
                            -- No hyphenation, add a space (might be not welcome
                            -- with CJK text, but well...)
                            line_text = line_text .. " "
                        end
                    end
                end
                local box = boxes[i][j]
                if prev_word then
                    -- A box should have been made for each word, so assume
                    -- we want a space between them, with some exceptions
                    local add_space = true
                    local box_height = box.y1 - box.y0
                    local dist_from_prev_word = box.x0 - prev_word_end_x
                    if prev_word:sub(-1, -1) == " " or word:sub(1, 1) == " " then
                        -- Already a space between these words
                        add_space = false
                    elseif dist_from_prev_word < box_height * 0.03 then
                        -- If the space between previous word box and this word box
                        -- is smaller than 5% of box height, assume these boxes
                        -- should be stuck
                        add_space = false
                    elseif dist_from_prev_word < box_height * 0.8 then
                        if isCJKChar(prev_word:sub(-3, -1)) and isCJKChar(word:sub(1, 3)) then
                            -- Two CJK chars whose spacing is not large enough
                            -- (we checked the 3 UTF8 bytes that CJK chars must be,
                            -- no need to split into unicode codepoints)
                            add_space = false
                        end
                    end
                    if add_space then
                        word = " " .. word
                    end
                end
                line_text = line_text .. word
                prev_word = word
                prev_word_end_x = box.x1
            end
        end
        -- insert line box
        local lb = boxes[i]
        if i > i_start and i < i_stop then
            local line_box = Geom:new{
                x = lb.x0, y = lb.y0,
                w = lb.x1 - lb.x0,
                h = lb.y1 - lb.y0,
            }
            table.insert(line_boxes, line_box)
        elseif i == i_start and i < i_stop then
            local wb = boxes[i][j_start]
            local line_box = Geom:new{
                x = wb.x0, y = lb.y0,
                w = lb.x1 - wb.x0,
                h = lb.y1 - lb.y0,
            }
            table.insert(line_boxes, line_box)
        elseif i > i_start and i == i_stop then
            local wb = boxes[i][j_stop]
            local line_box = Geom:new{
                x = lb.x0, y = lb.y0,
                w = wb.x1 - lb.x0,
                h = lb.y1 - lb.y0,
            }
            table.insert(line_boxes, line_box)
        elseif i == i_start and i == i_stop then
            local wb_start = boxes[i][j_start]
            local wb_stop = boxes[i][j_stop]
            local line_box = Geom:new{
                x = wb_start.x0, y = lb.y0,
                w = wb_stop.x1 - wb_start.x0,
                h = lb.y1 - lb.y0,
            }
            table.insert(line_boxes, line_box)
        end
    end
    return {
        text = line_text,
        boxes = line_boxes,
    }
end

--[[--
Get word and word box from `doc` position.
]]--
function KoptInterface:getWordFromPosition(doc, pos)
    local text_boxes = self:getTextBoxes(doc, pos.page)
    if text_boxes then
        if doc.configurable.text_wrap == 1 then
            return self:getWordFromReflowPosition(doc, text_boxes, pos)
        else
            return self:getWordFromNativePosition(doc, text_boxes, pos)
        end
    end
end

local function getBoxRelativePosition(s_box, l_box)
    local pos_rel = {}
    local s_box_center = s_box:center()
    pos_rel.x = (s_box_center.x - l_box.x)/l_box.w
    pos_rel.y = (s_box_center.y - l_box.y)/l_box.h
    return pos_rel
end

--[[--
Get word and word box from position in reflowed page.
]]--
function KoptInterface:getWordFromReflowPosition(doc, boxes, pos)
    local pageno = pos.page

    local scratch_reflowed_page_boxes = self:getReflowedTextBoxesFromScratch(doc, pageno)
    local scratch_reflowed_word_box = self:getWordFromBoxes(scratch_reflowed_page_boxes, pos)

    local reflowed_page_boxes = self:getReflowedTextBoxes(doc, pageno)
    local reflowed_word_box = self:getWordFromBoxes(reflowed_page_boxes, pos)

    local reflowed_pos_abs = scratch_reflowed_word_box.box:center()
    local reflowed_pos_rel = getBoxRelativePosition(scratch_reflowed_word_box.box, reflowed_word_box.box)

    local native_pos = self:reflowToNativePosTransform(doc, pageno, reflowed_pos_abs, reflowed_pos_rel)
    local native_word_box = self:getWordFromBoxes(boxes, native_pos)

    local word_box = {
        word = native_word_box.word,
        pbox = native_word_box.box,   -- box on page
        sbox = scratch_reflowed_word_box.box, -- box on screen
        pos = native_pos,
    }
    return word_box
end

--[[--
Get word and word box from position in native page.
]]--
function KoptInterface:getWordFromNativePosition(doc, boxes, pos)
    local native_word_box = self:getWordFromBoxes(boxes, pos)
    local word_box = {
        word = native_word_box.word,
        pbox = native_word_box.box,   -- box on page
        sbox = native_word_box.box,   -- box on screen
        pos = pos,
    }
    return word_box
end

--[[--
Get link from position in screen page.
]]--
function KoptInterface:getLinkFromPosition(doc, pageno, pos)
    local function _inside_box(_pos, box)
        if _pos then
            local x, y = _pos.x, _pos.y
            if box.x <= x and box.y <= y
                and box.x + box.w >= x
                and box.y + box.h >= y then
                return true
            end
        end
    end
    local page_links = doc:getPageLinks(pageno)
    if page_links then
        if doc.configurable.text_wrap == 1 then
            pos = self:reflowToNativePosTransform(doc, pageno, pos, {x=0.5, y=0.5})
        end

        local offset = CanvasContext:scaleBySize(5)
        local len = CanvasContext:scaleBySize(10)
        for i = 1, #page_links do
            local link = page_links[i]
            -- enlarge tappable link box
            local lbox = Geom:new{
                x = link.x0 - offset,
                y = link.y0 - offset,
                w = link.x1 - link.x0 + len,
                h = link.y1 - link.y0 + len,
            }
            -- Allow external links, with link.uri instead of link.page
            if _inside_box(pos, lbox) then -- and link.page then
                return link, lbox
            end
        end
    end
end

--[[--
Transform position in native page to reflowed page.
]]--
function KoptInterface:nativeToReflowPosTransform(doc, pageno, pos)
    local kc = self:getCachedContext(doc, pageno)
    local rpos = {}
    rpos.x, rpos.y = kc:nativeToReflowPosTransform(pos.x, pos.y)
    return rpos
end

--[[--
Transform position in reflowed page to native page.
]]--
function KoptInterface:reflowToNativePosTransform(doc, pageno, abs_pos, rel_pos)
    local kc = self:getCachedContext(doc, pageno)
    local npos = {}
    npos.x, npos.y = kc:reflowToNativePosTransform(abs_pos.x, abs_pos.y, rel_pos.x, rel_pos.y)
    return npos
end

--[[--
Get text and text boxes from screen positions.
--]]
function KoptInterface:getTextFromPositions(doc, pos0, pos1)
    local text_boxes = self:getTextBoxes(doc, pos0.page)
    if text_boxes then
        if doc.configurable.text_wrap == 1 then
            return self:getTextFromReflowPositions(doc, text_boxes, pos0, pos1)
        else
            return self:getTextFromNativePositions(doc, text_boxes, pos0, pos1)
        end
    end
end

--[[--
Get text and text boxes from screen positions for reflowed page.
]]--
function KoptInterface:getTextFromReflowPositions(doc, native_boxes, pos0, pos1)
    local pageno = pos0.page

    local scratch_reflowed_page_boxes = self:getReflowedTextBoxesFromScratch(doc, pageno)
    local reflowed_page_boxes = self:getReflowedTextBoxes(doc, pageno)

    local scratch_reflowed_word_box0 = self:getWordFromBoxes(scratch_reflowed_page_boxes, pos0)
    local reflowed_word_box0 = self:getWordFromBoxes(reflowed_page_boxes, pos0)
    local scratch_reflowed_word_box1 = self:getWordFromBoxes(scratch_reflowed_page_boxes, pos1)
    local reflowed_word_box1 = self:getWordFromBoxes(reflowed_page_boxes, pos1)

    local reflowed_pos_abs0 = scratch_reflowed_word_box0.box:center()
    local reflowed_pos_rel0 = getBoxRelativePosition(scratch_reflowed_word_box0.box, reflowed_word_box0.box)
    local reflowed_pos_abs1 = scratch_reflowed_word_box1.box:center()
    local reflowed_pos_rel1 = getBoxRelativePosition(scratch_reflowed_word_box1.box, reflowed_word_box1.box)

    local native_pos0 = self:reflowToNativePosTransform(doc, pageno, reflowed_pos_abs0, reflowed_pos_rel0)
    local native_pos1 = self:reflowToNativePosTransform(doc, pageno, reflowed_pos_abs1, reflowed_pos_rel1)

    local reflowed_text_boxes = self:getTextFromBoxes(reflowed_page_boxes, pos0, pos1)
    local native_text_boxes = self:getTextFromBoxes(native_boxes, native_pos0, native_pos1)
    local text_boxes = {
        text = native_text_boxes.text,
        pboxes = native_text_boxes.boxes,   -- boxes on page
        sboxes = reflowed_text_boxes.boxes, -- boxes on screen
        pos0 = native_pos0,
        pos1 = native_pos1
    }
    return text_boxes
end

--[[--
Get text and text boxes from screen positions for native page.
]]--
function KoptInterface:getTextFromNativePositions(doc, native_boxes, pos0, pos1)
    local native_text_boxes = self:getTextFromBoxes(native_boxes, pos0, pos1)
    local text_boxes = {
        text = native_text_boxes.text,
        pboxes = native_text_boxes.boxes,   -- boxes on page
        sboxes = native_text_boxes.boxes,   -- boxes on screen
        pos0 = pos0,
        pos1 = pos1,
    }
    return text_boxes
end


--[[--
Get text boxes from page positions.
--]]
function KoptInterface:getPageBoxesFromPositions(doc, pageno, ppos0, ppos1)
    if not ppos0 or not ppos1 then return end
    if doc.configurable.text_wrap == 1 then
        local spos0 = self:nativeToReflowPosTransform(doc, pageno, ppos0)
        local spos1 = self:nativeToReflowPosTransform(doc, pageno, ppos1)
        local page_boxes = self:getReflowedTextBoxes(doc, pageno)
        if not page_boxes then
            logger.warn("KoptInterface: missing page_boxes")
            return
        end
        local text_boxes = self:getTextFromBoxes(page_boxes, spos0, spos1)
        return text_boxes.boxes
    else
        local page_boxes = self:getTextBoxes(doc, pageno)
        if not page_boxes then
            logger.warn("KoptInterface: missing page_boxes")
            return
        end
        local text_boxes = self:getTextFromBoxes(page_boxes, ppos0, ppos1)
        return text_boxes.boxes
    end
end

--[[--
Get page rect from native rect.
--]]
function KoptInterface:nativeToPageRectTransform(doc, pageno, rect)
    if doc.configurable.text_wrap == 1 then
        local pos0 = {
            x = rect.x + 5, y = rect.y + 5
        }
        local pos1 = {
            x = rect.x + rect.w - 5,
            y = rect.y + rect.h - 5
        }
        local boxes = self:getPageBoxesFromPositions(doc, pageno, pos0, pos1)
        local res_rect = nil
        if #boxes > 0 then
            res_rect = boxes[1]
            for _, box in pairs(boxes) do
                res_rect = res_rect:combine(box)
            end
        end
        return res_rect
    else
        return rect
    end
end

local function all_matches(boxes, pattern, caseInsensitive)
    -- pattern list of single words
    local plist = {}
    -- split utf-8 characters
    for words in pattern:gmatch("[\32-\127\192-\255]+[\128-\191]*") do
        -- split space seperated words
        for word in words:gmatch("[^%s]+") do
            table.insert(plist, caseInsensitive and word:lower() or word)
        end
    end
    -- return mached word indices from index i, j
    local function match(i, j)
        local pindex = 1
        local matched_indices = {}
        if #plist == 0 then return end
        while true do
            if #boxes[i] < j then
                j = j - #boxes[i]
                i = i + 1
            end
            if i > #boxes then break end
            local box = boxes[i][j]
            local word = caseInsensitive and box.word:lower() or box.word
            if word:match(plist[pindex]) then
                table.insert(matched_indices, {i, j})
                if pindex == #plist then
                    return matched_indices
                else
                    j = j + 1
                    pindex = pindex + 1
                end
            else
                break
            end
        end
    end
    return coroutine.wrap(function()
        for i, line in ipairs(boxes) do
            for j, box in ipairs(line) do
                local matches = match(i, j)
                if matches then
                    coroutine.yield(matches)
                end
            end
        end
    end)
end

function KoptInterface:findAllMatches(doc, pattern, caseInsensitive, page)
    local text_boxes = doc:getPageTextBoxes(page)
    if not text_boxes then return end
    local matches = {}
    for indices in all_matches(text_boxes or {}, pattern, caseInsensitive) do
        for _, index in ipairs(indices) do
            local i, j = unpack(index)
            local word = text_boxes[i][j]
            local word_box = {
                x = word.x0, y = word.y0,
                w = word.x1 - word.x0,
                h = word.y1 - word.y0,
            }
            -- rects will be transformed to reflowed page rects if needed
            table.insert(matches, self:nativeToPageRectTransform(doc, page, word_box))
        end
    end
    return matches
end

function KoptInterface:findText(doc, pattern, origin, reverse, caseInsensitive, pageno)
    logger.dbg("Koptinterface: find text", pattern, origin, reverse, caseInsensitive, pageno)
    local last_pageno = doc:getPageCount()
    local start_page, end_page
    if reverse == 1 then
        -- backward
        if origin == 0 then
            -- from end of current page to first page
            start_page, end_page = pageno, 1
        elseif origin == -1 then
            -- from the last page to end of current page
            start_page, end_page = last_pageno, pageno + 1
        elseif origin == 1 then
            start_page, end_page = pageno - 1, 1
        end
    else
        -- forward
        if origin == 0 then
            -- from current page to the last page
            start_page, end_page = pageno, last_pageno
        elseif origin == -1 then
            -- from the first page to current page
            start_page, end_page = 1, pageno - 1
        elseif origin == 1 then
            -- from next page to the last page
            start_page, end_page = pageno + 1, last_pageno
        end
    end
    for i = start_page, end_page, (reverse == 1) and -1 or 1 do
        local matches = self:findAllMatches(doc, pattern, caseInsensitive, i)
        if #matches > 0 then
            matches.page = i
            return matches
        end
    end
end

--[[--
Log reflow duration.
--]]
function KoptInterface:logReflowDuration(pageno, dur)
    local file = io.open("reflow_dur_log.txt", "a+")
    if file then
        if file:seek("end") == 0 then -- write the header only once
            file:write("PAGE\tDUR\n")
        end
        file:write(string.format("%s\t%s\n", pageno, dur))
        file:close()
    end
end

return KoptInterface
