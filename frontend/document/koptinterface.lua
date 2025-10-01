--[[--
Interface to k2pdfoptlib backend.
--]]

local CacheItem = require("cacheitem")
local CanvasContext = require("document/canvascontext")
local DataStorage = require("datastorage")
local DEBUG = require("dbg")
local DocCache = require("document/doccache")
local Document = require("document/document")
local FFIUtil = require("ffi/util")
local Geom = require("ui/geometry")
local KOPTContext = require("ffi/koptcontext")
local Persist = require("persist")
local TileCacheItem = require("document/tilecacheitem")
local Utf8Proc = require("ffi/utf8proc")
local logger = require("logger")
local util = require("util")
local ffi = require("ffi")

local KoptInterface = {
    ocrengine = "ocrengine",
    -- If `$TESSDATA_PREFIX` is set, don't override it: let libk2pdfopt honor it
    -- (which includes checking for data in both `$TESSDATA_PREFIX/tessdata` and
    -- in `$TESSDATA_PREFIX/` on more recent versions).
    tessocr_data = not os.getenv('TESSDATA_PREFIX') and DataStorage:getDataDir().."/data/tessdata" or nil,
    ocr_lang = "eng",
    ocr_type = -1, -- default: assume a single uniform block of text.
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
    configurable.doc_language = G_defaults:readSetting("DKOPTREADER_CONFIG_DOC_DEFAULT_LANG_CODE")
    configurable.trim_page = G_defaults:readSetting("DKOPTREADER_CONFIG_TRIM_PAGE")
    configurable.text_wrap = G_defaults:readSetting("DKOPTREADER_CONFIG_TEXT_WRAP")
    configurable.detect_indent = G_defaults:readSetting("DKOPTREADER_CONFIG_DETECT_INDENT")
    configurable.max_columns = G_defaults:readSetting("DKOPTREADER_CONFIG_MAX_COLUMNS")
    configurable.auto_straighten = G_defaults:readSetting("DKOPTREADER_CONFIG_AUTO_STRAIGHTEN")
    configurable.justification = G_defaults:readSetting("DKOPTREADER_CONFIG_JUSTIFICATION")
    configurable.writing_direction = 0
    configurable.font_size = G_defaults:readSetting("DKOPTREADER_CONFIG_FONT_SIZE")
    configurable.page_margin = G_defaults:readSetting("DKOPTREADER_CONFIG_PAGE_MARGIN")
    configurable.quality = G_defaults:readSetting("DKOPTREADER_CONFIG_RENDER_QUALITY")
    configurable.contrast = G_defaults:readSetting("DKOPTREADER_CONFIG_CONTRAST")
    configurable.defect_size = G_defaults:readSetting("DKOPTREADER_CONFIG_DEFECT_SIZE")
    configurable.line_spacing = G_defaults:readSetting("DKOPTREADER_CONFIG_LINE_SPACING")
    configurable.word_spacing = G_defaults:readSetting("DKOPTREADER_CONFIG_DEFAULT_WORD_SPACING")
end

function KoptInterface:waitForContext(kc)
    -- If our koptcontext is busy in a background thread, isPreCache will return 1.
    local waited = false
    while kc and kc:isPreCache() == 1 do
        waited = true
        logger.dbg("waiting for background rendering")
        FFIUtil.usleep(100000)
    end

    if waited or self.bg_thread then
        -- Background thread is done, go back to a single CPU core.
        CanvasContext:enableCPUCores(1)
        self.bg_thread = nil
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
    -- k2pdfopt (for reflowing) and mupdf use different algorithms to apply gamma when rendering
    kc:setContrast(1 / doc.configurable.contrast)
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
    table.insert(hash_list, doc.render_color and 'color' or 'bw')
    table.insert(hash_list, doc.render_mode)
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
        page:getPagePix(kc, doc.render_mode)
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
        page:getPagePix(kc, doc.render_mode)
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

-- lazily load libpthread
local cached_pthread
local function get_pthread()
    if cached_pthread then
        return cached_pthread
    end
    local candidates, ok
    if ffi.os == "Windows" then
        candidates = {"libwinpthread-1.dll"}
    elseif FFIUtil.isAndroid() then
        -- pthread directives are in Bionic library on Android
        candidates = {"libc.so"}
    else
        -- Kobo devices strangely have no libpthread.so in LD_LIBRARY_PATH
        -- so we hardcode the libpthread.so.0 here just for Kobo.
        candidates = {"pthread", "libpthread.so.0"}
    end
    for _, libname in ipairs(candidates) do
        ok, cached_pthread = pcall(ffi.load, libname)
        if ok then
            require("ffi/pthread_h")
            return cached_pthread
        end
    end
end

function KoptInterface:reflowPage(doc, pageno, bbox, background)
    logger.dbg("reflowing page", pageno, background and "in background" or "in foreground")
    local kc = self:createContext(doc, pageno, bbox)
    if background then
        kc:setPreCache()
        self.bg_thread = true
    end
    -- Calculate zoom.
    kc.zoom = (1.5 * kc.zoom * kc.quality * kc.dev_width) / bbox.x1
    -- Generate pixmap.
    local page = doc._document:openPage(pageno)
    page:getPagePix(kc, doc.render_mode)
    page:close()
    -- Reflow.
    if background then
        local pthread = get_pthread()
        local rf_thread = ffi.new("pthread_t[1]")
        local attr = ffi.new("pthread_attr_t[1]")
        pthread.pthread_attr_init(attr)
        pthread.pthread_attr_setdetachstate(attr, pthread.PTHREAD_CREATE_DETACHED)
        pthread.pthread_create(rf_thread, attr, KOPTContext.k2pdfopt.k2pdfopt_reflow_bmp, ffi.cast("void*", kc))
        pthread.pthread_attr_destroy(attr)
    else
        KOPTContext.k2pdfopt.k2pdfopt_reflow_bmp(kc)
    end
    return kc
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
        --local secs, usecs = FFIUtil.gettime()
        local kc = self:reflowPage(doc, pageno, bbox, false)
        -- reflow page
        --local nsecs, nusecs = FFIUtil.gettime()
        --local dur = nsecs - secs + (nusecs - usecs) / 1000000
        --self:logReflowDuration(pageno, dur)
        local fullwidth, fullheight = kc:getPageDim()
        logger.dbg("reflowed page", pageno, "fullwidth:", fullwidth, "fullheight:", fullheight)
        self.last_context_size = fullwidth * fullheight + 3072 -- estimation
        DocCache:insert(hash, ContextCacheItem:new{
            persistent = true,
            doc_path = doc.file,
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
    local tile = Document.renderPage(doc, 1, nil, zoom, 0, 1.0)
    if tile then
        return tile.bb:copy()
    end
end

function KoptInterface:renderPage(doc, pageno, rect, zoom, rotation, gamma, hinting)
    if doc.configurable.text_wrap == 1 then
        return self:renderReflowedPage(doc, pageno, rect, zoom, rotation, hinting)
    elseif doc.configurable.page_opt == 1 or doc.configurable.auto_straighten > 0 then
        return self:renderOptimizedPage(doc, pageno, rect, zoom, rotation, hinting)
    else
        return Document.renderPage(doc, pageno, rect, zoom, rotation, gamma, hinting)
    end
end

--[[--
Render reflowed page into tile cache.

Inherited from common document interface.
--]]
function KoptInterface:renderReflowedPage(doc, pageno, rect, zoom, rotation)
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
function KoptInterface:renderOptimizedPage(doc, pageno, rect, zoom, rotation, hinting)
    local bbox = doc:getPageBBox(pageno)
    local hash_list = { "renderoptpg" }
    self:getContextHash(doc, pageno, bbox, hash_list)
    local hash = table.concat(hash_list, "|")

    local cached = DocCache:check(hash, TileCacheItem)
    if not cached then
        if hinting then
            CanvasContext:enableCPUCores(2)
        end

        local page_size = Document.getNativePageDimensions(doc, pageno)
        local full_page_bbox = {
            x0 = 0, y0 = 0,
            x1 = page_size.w,
            y1 = page_size.h,
        }
        local kc = self:createContext(doc, pageno, full_page_bbox)
        local page = doc._document:openPage(pageno)
        kc:setZoom(zoom)
        page:getPagePix(kc, doc.render_mode)
        page:close()
        logger.dbg("optimizing page", pageno)
        kc:optimizePage()
        local fullwidth, fullheight = kc:getPageDim()
        -- prepare cache item with contained blitbuffer
        local tile = TileCacheItem:new{
            persistent = true,
            doc_path = doc.file,
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

        if hinting then
            CanvasContext:enableCPUCores(1)
        end

        return tile
    else
        return cached
    end
end

function KoptInterface:hintPage(doc, pageno, zoom, rotation, gamma)
    --- @note: Crappy safeguard around memory issues like in #7627: if we're eating too much RAM, drop half the cache...
    DocCache:memoryPressureCheck()

    if doc.configurable.text_wrap == 1 then
        self:hintReflowedPage(doc, pageno, zoom, rotation, gamma, true)
    elseif doc.configurable.page_opt == 1 or doc.configurable.auto_straighten > 0 then
        self:renderOptimizedPage(doc, pageno, nil, zoom, rotation, gamma, true)
    else
        Document.hintPage(doc, pageno, zoom, rotation, gamma)
    end
end

--[[--
Render reflowed page into cache in background thread.

This method returns immediately, leaving the precache flag on
in context. Subsequent usage of this context should wait for the precache flag
off by calling self:waitForContext(kctx)

Inherited from common document interface.
--]]
function KoptInterface:hintReflowedPage(doc, pageno, zoom, rotation, gamma, hinting)
    local bbox = doc:getPageBBox(pageno)
    local hash_list = { "kctx" }
    self:getContextHash(doc, pageno, bbox, hash_list)
    local hash = table.concat(hash_list, "|")
    local cached = DocCache:check(hash)
    if not cached then
        if hinting then
            CanvasContext:enableCPUCores(2)
        end
        local kc = self:reflowPage(doc, pageno, bbox, true)
        DocCache:insert(hash, ContextCacheItem:new{
            size = self.last_context_size or self.default_context_size,
            kctx = kc,
        })
        -- We'll wait until the background thread is done to go back to a single core, as this returns immediately!
        -- c.f., :waitForContext
    end
end

function KoptInterface:drawPage(doc, target, x, y, rect, pageno, zoom, rotation, gamma)
    if doc.configurable.text_wrap == 1 then
        self:drawContextPage(doc, target, x, y, rect, pageno, zoom, rotation)
    elseif doc.configurable.page_opt == 1 or doc.configurable.auto_straighten > 0 then
        self:drawContextPage(doc, target, x, y, rect, pageno, zoom, rotation)
    else
        Document.drawPage(doc, target, x, y, rect, pageno, zoom, rotation, gamma)
    end
end

--[[--
Draw cached tile pixels into target blitbuffer.

Inherited from common document interface.
--]]
function KoptInterface:drawContextPage(doc, target, x, y, rect, pageno, zoom, rotation)
    local tile = self:renderPage(doc, pageno, rect, zoom, rotation, 1.0)
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
        local kc
        local kctx_hash = hash:gsub("^rfpgboxes|", "kctx|")
        cached = DocCache:check(kctx_hash)
        if not cached then
            kc = self:getCachedContext(doc, pageno)
        else
            kc = self:waitForContext(cached.kctx)
        end
        --kc:setDebug()
        local fullwidth, fullheight = kc:getPageDim()
        local boxes, nr_word = kc:getReflowedWordBoxes("dst", 0, 0, fullwidth, fullheight)
        if not boxes then
            return
        end
        DocCache:insert(hash, CacheItem:new{ rfpgboxes = boxes, size = 192 * nr_word }) -- estimation
        return boxes
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
        local kc
        local kctx_hash = hash:gsub("^nativepgboxes|", "kctx|")
        cached = DocCache:check(kctx_hash)
        if not cached then
            kc = self:createContext(doc, pageno)
            DocCache:insert(kctx_hash, ContextCacheItem:new{
                persistent = true,
                doc_path = doc.file,
                size = self.last_context_size or self.default_context_size,
                kctx = kc,
            })
        else
            kc = self:waitForContext(cached.kctx)
        end
        --kc:setDebug()
        local fullwidth, fullheight = kc:getPageDim()
        local boxes, nr_word = kc:getNativeWordBoxes("dst", 0, 0, fullwidth, fullheight)
        if not boxes then
            return
        end
        DocCache:insert(hash, CacheItem:new{ nativepgboxes = boxes, size = 192 * nr_word }) -- estimation
        return boxes
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
        local reflowed_kc
        local kctx_hash = hash:gsub("^scratchrfpgboxes|", "kctx|")
        cached = DocCache:check(kctx_hash)
        if not cached then
            reflowed_kc = self:getCachedContext(doc, pageno)
        else
            reflowed_kc = self:waitForContext(cached.kctx)
        end
        local fullwidth, fullheight = reflowed_kc:getPageDim()
        local kc = self:createContext(doc, pageno)
        kc:copyDestBMP(reflowed_kc)
        local boxes, nr_word = kc:getNativeWordBoxes("dst", 0, 0, fullwidth, fullheight)
        kc:free()
        if not boxes then
            return
        end
        DocCache:insert(hash, CacheItem:new{ scratchrfpgboxes = boxes, size = 192 * nr_word }) -- estimation
        return boxes
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
    page:getPagePix(kc, doc.render_mode)
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
        page:getPagePix(kc, doc.render_mode)
        local boxes, nr_word = kc:getNativeWordBoxes("src", 0, 0, page_size.w, page_size.h)
        if boxes then
            DocCache:insert(hash, CacheItem:new{ scratchnativepgboxes = boxes, size = 192 * nr_word }) -- estimation
        end
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
        page:getPagePix(kc, doc.render_mode)
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
        local kc
        local kctx_hash = hash:gsub("^rfocrword|", "kctx|")
        cached = DocCache:check(kctx_hash)
        if not cached then
            kc = self:getCachedContext(doc, pageno)
        else
            kc = self:waitForContext(cached.kctx)
        end
        local _, word = pcall(
            kc.getTOCRWord, kc, "dst",
            rect.x, rect.y, rect.w, rect.h,
            self.tessocr_data, self.ocr_lang, self.ocr_type, 0, 1)
        DocCache:insert(hash, CacheItem:new{ rfocrword = word, size = #word + 64 }) -- estimation
        return word
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
        page:getPagePix(kc, doc.render_mode)
        --kc:exportSrcPNGFile({rect}, nil, "ocr-word.png")
        local word_w, word_h = kc:getPageDim()
        local _, word = pcall(
            kc.getTOCRWord, kc, "src",
            0, 0, word_w, word_h,
            self.tessocr_data, self.ocr_lang, self.ocr_type, 0, 1)
        if word then
            DocCache:insert(hash, CacheItem:new{ ocrword = word, size = #word + 64 }) -- estimation
        end
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
        rect = Geom.boundingBox(pboxes)
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
    page:getPagePix(kc, doc.render_mode)
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
    if FFIUtil.isAndroid() then
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
            local box = boxes[i][j]
            local word = box and box.word
            if word then
                if not line_first_word_seen then
                    line_first_word_seen = true
                    if #line_text > 0 then
                        if line_text:sub(-1) == "-" then
                            -- Previous line ended with a minus.
                            -- Assume it's some hyphenation and discard it.
                            line_text = line_text:sub(1, -2)
                        elseif line_text:sub(-2, -1) == "\u{00AD}" then
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
                        local prev_word_end = prev_word:match(util.UTF8_CHAR_PATTERN.."$")
                        local word_start = word:match(util.UTF8_CHAR_PATTERN)
                        if util.isCJKChar(prev_word_end) and util.isCJKChar(word_start) then
                            -- Two CJK chars whose spacing is not large enough,
                            -- but even so they must not have a space added.
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
        self.last_text_boxes = text_boxes
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
    if not DEBUG.dassert(scratch_reflowed_page_boxes and next(scratch_reflowed_page_boxes) ~= nil, "scratch_reflowed_page_boxes shouldn't be nil/{}") then
        return
    end

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

local function get_prev_text(boxes, i, j, nb_words)
    local prev_count = 0
    local prev_text = {}
    while prev_count < nb_words do
        if i == 1 and j == 1 then
            break
        elseif j == 1 then
            i = i - 1
            j = #boxes[i]
        else
            j = j - 1
        end
        local current_word = boxes[i][j].word
        if #current_word > 0 then
            table.insert(prev_text, 1, current_word)
            prev_count = prev_count + 1
        end
    end
    if #prev_text > 0 then
        return table.concat(prev_text, " ")
    end
end

local function get_next_text(boxes, i, j, nb_words)
    local next_count = 0
    local next_text = {}
    while next_count < nb_words do
        if i == #boxes and j == #boxes[i] then
            break
        elseif j == #boxes[i] then
            i = i + 1
            j = 1
        else
            j = j + 1
        end
        local current_word = boxes[i][j].word
        if #current_word > 0 then
            table.insert(next_text, current_word)
            next_count = next_count + 1
        end
    end
    if #next_text > 0 then
        return table.concat(next_text, " ")
    end
end

function KoptInterface:getSelectedWordContext(word, nb_words, pos)
    local boxes = self.last_text_boxes
    if not pos or not boxes or #boxes == 0 then return end
    local i, j = getWordBoxIndices(boxes, pos)
    local i_end, j_end = i, j
    local word_array = util.splitToArray(word, " ")
    for idx, split_word in ipairs(word_array) do
        local box_word = boxes[i_end][j_end].word
        if box_word:sub(-1) == "-" and j_end == #boxes[i_end] and box_word ~= split_word then
            -- Line final hyphenation.
            -- Combine word with first word of next line.
            box_word = box_word:sub(1, -2)
            i_end = i_end + 1
            j_end = 1
            box_word = box_word .. boxes[i_end][j_end].word
        elseif box_word:sub(-2, -1) == "\u{00AD}" and j_end == #boxes[i_end] and box_word ~= split_word then
            -- Hyphen
            box_word = box_word:sub(1, -3)
            i_end = i_end + 1
            j_end = 1
            box_word = box_word .. boxes[i_end][j_end].word
        end
        if box_word ~= split_word then return end
        if idx ~= #word_array then
            if j_end == #boxes[i_end] then
                i_end = i_end + 1
                j_end = 1
            else
                j_end = j_end + 1
            end
        end
    end
    local prev_text = get_prev_text(boxes, i, j, nb_words)
    local next_text = get_next_text(boxes, i_end, j_end, nb_words)
    return prev_text, next_text
end

--[[--
Get link from position in screen page.
]]--
function KoptInterface:getLinkFromPosition(doc, pageno, pos)
    local function _inside_box(coords, box)
        if coords then
            local x, y = coords.x, coords.y
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
    local rpos = {page = pageno}
    rpos.x, rpos.y = kc:nativeToReflowPosTransform(pos.x, pos.y)
    return rpos
end

--[[--
Transform position in reflowed page to native page.
]]--
function KoptInterface:reflowToNativePosTransform(doc, pageno, abs_pos, rel_pos)
    local kc = self:getCachedContext(doc, pageno)
    local npos = {page = pageno}
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
    if not DEBUG.dassert(scratch_reflowed_word_box0 and next(scratch_reflowed_word_box0) ~= nil, "scratch_reflowed_word_box0 shouldn't be nil/{}") then
        return
    end
    local reflowed_word_box0 = self:getWordFromBoxes(reflowed_page_boxes, pos0)

    local scratch_reflowed_word_box1 = self:getWordFromBoxes(scratch_reflowed_page_boxes, pos1)
    if not DEBUG.dassert(scratch_reflowed_word_box1 and next(scratch_reflowed_word_box1) ~= nil, "scratch_reflowed_word_box1 shouldn't be nil/{}") then
        return
    end
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
Compare positions within one page.
Returns 1 if positions are ordered (if ppos2 is after ppos1), -1 if not, 0 if same.
Positions of the word boxes containing ppos1 and ppos2 are compared.
--]]
function KoptInterface:comparePositions(doc, ppos1, ppos2)
    if ppos1.page < ppos2.page then
        return 1
    elseif ppos1.page > ppos2.page then
        return -1
    end
    local box1 = self:getWordFromPosition(doc, ppos1).pbox
    local box2 = self:getWordFromPosition(doc, ppos2).pbox
    if box1.y == box2.y then
        if box1.x == box2.x then
            return 0
        elseif box1.x > box2.x then
            return -1
        end
    elseif box1.y > box2.y then
        return -1
    end
    return 1
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
        if boxes then
            return Geom.boundingBox(boxes)
        end
    else
        return rect
    end
end

local function get_pattern_list(pattern, case_insensitive)
    -- pattern list of single words
    local plist = {}
    -- (as in util.splitToWords(), but only splitting on spaces, keeping punctuation marks)
    for word in util.gsplit(pattern, "%s+") do
        if util.hasCJKChar(word) then
            for char in util.gsplit(word, "[\192-\255][\128-\191]+", true) do
                table.insert(plist, case_insensitive and Utf8Proc.lowercase(util.fixUtf8(char, "?")) or char)
            end
        else
            table.insert(plist, case_insensitive and Utf8Proc.lowercase(util.fixUtf8(word, "?")) or word)
        end
    end
    if #plist == 1 then
        plist.from_start = pattern:sub(1, 1) == " "
        plist.from_end = pattern:sub(-1) == " "
    end
    return plist
end

local function all_matches(boxes, plist, case_insensitive)
    local pnb = #plist
    -- return matched word indices from index i, j
    local function match(i, j)
        local pindex = 1
        local matched_indices = {}
        if pnb == 0 then return end
        while true do
            if #boxes[i] < j then
                j = j - #boxes[i]
                i = i + 1
            end
            if i > #boxes then break end
            local box = boxes[i][j]
            local word = case_insensitive and Utf8Proc.lowercase(util.fixUtf8(box.word, "?")) or box.word
            local pword = plist[pindex]
            local matched
            if pnb == 1 then -- single word in plist
                if plist.from_start or plist.from_end then
                    if plist.from_start and plist.from_end then
                        matched = word == pword
                    elseif plist.from_start then
                        matched = word:sub(1, #pword) == pword
                    else -- plist.from_end
                        matched = word:sub(-#pword) == pword
                    end
                else
                    matched = word:find(pword, 1, true)
                end
            else -- multiple words in plist
                if pindex == 1 then
                    -- first word of query should match at end of a word from the document
                   matched = word:sub(-#pword) == pword
                elseif pindex == pnb then
                    -- last word of query should match at start of the word from the document
                    matched = word:sub(1, #pword) == pword
                else
                    -- middle words in query should match exactly the word from the document
                    matched = word == pword
                end
            end
            if matched then
                table.insert(matched_indices, {i, j})
                if pindex == pnb then
                    -- all words in plist iterated, all matched
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
    -- Note that this returns a full word box, even if what matches
    -- is only a substring of a word box.
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

function KoptInterface:findAllMatches(doc, pattern, case_insensitive, page)
    local text_boxes = doc:getPageTextBoxes(page)
    if not text_boxes then return end
    local plist = get_pattern_list(pattern, case_insensitive)
    local matches = {}
    for indices in all_matches(text_boxes, plist, case_insensitive) do
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

function KoptInterface:findText(doc, pattern, origin, reverse, case_insensitive, pageno)
    logger.dbg("Koptinterface: find text", pattern, origin, reverse, case_insensitive, pageno)
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
        local matches = self:findAllMatches(doc, pattern, case_insensitive, i)
        if #matches > 0 then
            matches.page = i
            return matches
        end
    end
end

function KoptInterface:findAllText(doc, pattern, case_insensitive, nb_context_words, max_hits)
    local plist = get_pattern_list(pattern, case_insensitive)
    local res = {}
    for page = 1, doc:getPageCount() do
        local text_boxes = doc:getPageTextBoxes(page)
        if text_boxes then
            for indices in all_matches(text_boxes, plist, case_insensitive) do -- each found pattern in the page
                local res_item = {
                    start = page,
                    boxes = {}, -- to draw temp highlight in onMenuSelect
                }
                local text = {}
                local i_prev, j_prev, i_next, j_next
                for ind, index in ipairs(indices) do -- each word in the pattern
                    local i, j = unpack(index)
                    local word = text_boxes[i][j]
                    res_item.boxes[ind] = {
                        x = word.x0, y = word.y0,
                        w = word.x1 - word.x0,
                        h = word.y1 - word.y0,
                    }
                    text[ind] = word.word
                    if ind == 1 then
                        i_prev, j_prev = i, j
                    end
                    if ind == #indices then
                        i_next, j_next = i, j
                    end
                end
                res_item.matched_text = table.concat(text, " ")
                res_item.prev_text = get_prev_text(text_boxes, i_prev, j_prev, nb_context_words)
                res_item.next_text = get_next_text(text_boxes, i_next, j_next, nb_context_words)
                table.insert(res, res_item)
                if #res == max_hits then
                    return res
                end
            end
        end
    end
    if #res > 0 then
        return res
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
