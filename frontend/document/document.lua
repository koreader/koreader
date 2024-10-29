local Blitbuffer = require("ffi/blitbuffer")
local CacheItem = require("cacheitem")
local Configurable = require("configurable")
local DocCache = require("document/doccache")
local DrawContext = require("ffi/drawcontext")
local CanvasContext = require("document/canvascontext")
local Geom = require("ui/geometry")
local Math = require("optmath")
local TileCacheItem = require("document/tilecacheitem")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")

--[[
This is an abstract interface to a document
]]--
local Document = {
    -- file name
    file = nil,
    -- engine instance
    _document = nil,

    links = nil, -- table

    GAMMA_NO_GAMMA = 1.0,

    -- override bbox from original page's getUsedBBox
    bbox = nil, -- table

    -- flag to show whether the document was opened successfully
    is_open = false,

    -- flag to show that the document needs to be unlocked by a password
    is_locked = false,

    -- flag to show that the document is edited and needs to write back to disk
    is_edited = false,

    -- whether this document can be rendered in color
    is_color_capable = true,
    -- bb type needed by engine for color rendering
    color_bb_type = Blitbuffer.TYPE_BBRGB32,

    -- image content stats, if supported by the engine
    _drawn_images_count = nil,
    _drawn_images_surface_ratio = nil,
}

function Document:extend(subclass_prototype)
    local o = subclass_prototype or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function Document:new(o)
    o = self:extend(o)
    if o._init then o:_init() end
    if o.init then o:init() end
    return o
end

-- base document initialization should be called on each document init
function Document:_init()
    self.links = {}
    self.bbox = {}
    self.configurable = Configurable:new{}
    self.info = {
        -- whether the document is pageable
        has_pages = false,
        -- whether words can be provided
        has_words = false,
        -- whether hyperlinks can be provided
        has_hyperlinks = false,
        -- whether (native to format) annotations can be provided
        has_annotations = false,

        -- whether pages can be rotated
        is_rotatable = false,

        number_of_pages = 0,
        -- if not pageable, length of the document in pixels
        doc_height = 0,

        -- other metadata
        title = "",
        author = "",
        date = ""
    }

    -- Should be updated by a call to Document.updateColorRendering(self) in subclasses
    self.render_color = false

    -- Those may be updated via KOptOptions, or the DitheringUpdate event.
    -- Whether HW dithering is enabled
    self.hw_dithering = false
    -- Whether SW dithering is enabled
    self.sw_dithering = false

    -- Zero-init those to be able to drop the nil guards at runtime
    self._drawn_images_count = 0
    self._drawn_images_surface_ratio = 0
end

-- override this method to open a document
function Document:init()
end

-- this might be overridden by a document implementation
function Document:unlock(password)
    -- return true instead when the password provided unlocked the document
    return false
end

-- this might be overridden by a document implementation
-- (in which case, do make sure it calls this one, too, to avoid refcounting mismatches in DocumentRegistry!)
-- Returns true if the Document instance needs to be destroyed (no more live refs),
-- false if not (i.e., we've just decreased the refcount, so, leave internal engine data alone).
-- nil if all hell broke loose.
function Document:close()
    local DocumentRegistry = require("document/documentregistry")
    if self.is_open then
        local refcount = DocumentRegistry:closeDocument(self.file)
        if refcount == 0 then
            self.is_open = false
            self._document:close()
            self._document = nil

            -- NOTE: DocumentRegistry:openDocument will force a GC sweep the next time we open a Document.
            --       MµPDF will also do a bit of spring cleaning of its internal cache when opening a *different* document.
            return true
        else
            -- This can happen in perfectly sane contexts (i.e., Reader -> History -> View fullsize cover on the *same* book).
            logger.dbg("Document: Decreased refcount to", refcount, "for", self.file)
            return false
        end
    else
        logger.warn("Tried to close an already closed document:", self.file)
        return nil
    end
end

-- check if document is edited and needs to write to disk
function Document:isEdited()
    return self.is_edited
end

-- discard change will set is_edited flag to false and implematation of Document
-- should check the is_edited flag before writing document
function Document:discardChange()
    self.is_edited = false
end

-- this might be overridden by a document implementation
function Document:getNativePageDimensions(pageno)
    local hash = "pgdim|"..self.file.."|"..self.mod_time.."|"..pageno
    local cached = DocCache:check(hash)
    if cached then
        return cached[1]
    end
    local page = self._document:openPage(pageno)
    local page_size_w, page_size_h = page:getSize(self.dc_null)
    local page_size = Geom:new{ w = page_size_w, h = page_size_h }
    DocCache:insert(hash, CacheItem:new{ page_size })
    page:close()
    return page_size
end

function Document:getDocumentProps()
    -- pdfdocument, djvudocument
    return self._document:getMetadata()
    -- credocument, picdocument - overridden by a document implementation
end

function Document:getProps(cached_doc_metadata)
    local function makeNilIfEmpty(str)
        if str == "" then
            return nil
        end
        return str
    end
    local props = cached_doc_metadata or self:getDocumentProps()
    local title = makeNilIfEmpty(props.title or props.Title)
    local authors = makeNilIfEmpty(props.authors or props.author or props.Author)
    local series = makeNilIfEmpty(props.series or props.Series)
    local series_index
    if series and string.find(series, "#") then
        -- If there's a series index in there, split it off to series_index, and only store the name in series.
        -- This property is currently only set by:
        --   * DjVu, for which I couldn't find a real standard for metadata fields
        --     (we currently use Series for this field, c.f., https://exiftool.org/TagNames/DjVu.html).
        --   * CRe, which could offer us a split getSeriesName & getSeriesNumber...
        --     except getSeriesNumber does an atoi, so it'd murder decimal values.
        --     So, instead, parse how it formats the whole thing as a string ;).
        local series_name
        series_name, series_index = series:match("(.*) #(%d+%.?%d-)$")
        if series_index then
            series = series_name
            series_index = tonumber(series_index)
        end
    end
    local language = makeNilIfEmpty(props.language or props.Language)
    local keywords = makeNilIfEmpty(props.keywords or props.Keywords)
    local description = makeNilIfEmpty(props.description or props.Description or props.subject)
    local identifiers = makeNilIfEmpty(props.identifiers)
    return {
        title        = title,
        authors      = authors,
        series       = series,
        series_index = series_index,
        language     = language,
        keywords     = keywords,
        description  = description,
        identifiers  = identifiers,
    }
end

function Document:_readMetadata()
    self.mod_time = lfs.attributes(self.file, "modification")
    self.info.number_of_pages = self._document:getPages()
    return true
end

function Document:getPageCount()
    return self.info.number_of_pages
end

-- Some functions that look quite silly, but they can be
-- overridden for document types that support separate flows
-- (e.g. CreDocument)
function Document:hasNonLinearFlows()
    return false
end

function Document:hasHiddenFlows()
    return false
end

function Document:getNextPage(page)
    local new_page = page + 1
    return (new_page > 0 and new_page <= self.info.number_of_pages) and new_page or 0
end

function Document:getPrevPage(page)
    if page == 0 then return self.info.number_of_pages end
    local new_page = page - 1
    return (new_page > 0 and new_page <= self.info.number_of_pages) and new_page or 0
end

function Document:getTotalPagesLeft(page)
    return self.info.number_of_pages - page
end

function Document:getPageFlow(page)
    return 0
end

function Document:getFirstPageInFlow(flow)
    return 1
end

function Document:getTotalPagesInFlow(flow)
    return self.info.number_of_pages
end

function Document:getPageNumberInFlow(page)
    return page
end

-- Transform a given rect according to the specified zoom & rotation
function Document:transformRect(native_rect, zoom, rotation)
    local rect = native_rect:copy()
    if rotation == 90 or rotation == 270 then
        -- switch orientation
        rect.w, rect.h = rect.h, rect.w
    end
    -- Apply the zoom factor, and round to integer in a sensible manner
    rect:transformByScale(zoom)
    return rect
end

-- Ditto, but we get the input rect from the full page dimensions for a given page number
function Document:getPageDimensions(pageno, zoom, rotation)
    local native_rect = self:getNativePageDimensions(pageno)
    return self:transformRect(native_rect, zoom, rotation)
end

function Document:getPageBBox(pageno)
    local bbox = self.bbox[pageno] -- exact
    if bbox ~= nil then
        return bbox
    else
        local oddEven = Math.oddEven(pageno)
        bbox = self.bbox[oddEven] -- odd/even
    end
    if bbox ~= nil then -- last used up to this page
        return bbox
    else
        for i = 0,pageno do
            bbox = self.bbox[ pageno - i ]
            if bbox ~= nil then
                return bbox
            end
        end
    end
    if bbox == nil then -- fallback bbox
        bbox = self:getUsedBBox(pageno)
    end
    return bbox
end

--[[
This method returns pagesize if bbox is corrupted
--]]
function Document:getUsedBBoxDimensions(pageno, zoom, rotation)
    local bbox = self:getPageBBox(pageno)
    -- clipping page bbox
    if bbox.x0 < 0 then bbox.x0 = 0 end
    if bbox.y0 < 0 then bbox.y0 = 0 end
    if bbox.x1 and bbox.x1 < 0 then bbox.x1 = 0 end
    if bbox.y1 and bbox.y1 < 0 then bbox.y1 = 0 end
    local ubbox_dimen
    if (not bbox.x1 or bbox.x0 >= bbox.x1) or (not bbox.y1 or bbox.y0 >= bbox.y1) then
        -- if document's bbox info is corrupted, we use the page size
        ubbox_dimen = self:getPageDimensions(pageno, zoom, rotation)
    else
        ubbox_dimen = Geom:new{
            x = bbox.x0,
            y = bbox.y0,
            w = bbox.x1 - bbox.x0,
            h = bbox.y1 - bbox.y0,
        }
        --- @note: Should we round this regardless of zoom?
        if zoom ~= 1 then
            ubbox_dimen:transformByScale(zoom)
        end
    end
    return ubbox_dimen
end

function Document:getToc()
    return self._document:getToc()
end

function Document:canHaveAlternativeToc()
    return false
end

function Document:isTocAlternativeToc()
    return false
end

function Document:getPageLinks(pageno)
    return nil
end

function Document:getLinkFromPosition(pageno, pos)
    return nil
end

function Document:getImageFromPosition(pos)
    return nil
end

function Document:getTextFromPositions(pos0, pos1)
    return nil
end

function Document:getTextBoxes(pageno)
    return nil
end

function Document:getOCRWord(pageno, rect)
    return nil
end

function Document:getCoverPageImage()
    return nil
end

function Document:findText()
    return nil
end

function Document:findAllText()
    return nil
end

function Document:updateColorRendering()
    if self.is_color_capable and CanvasContext.is_color_rendering_enabled then
        self.render_color = true
    else
        self.render_color = false
    end
end

function Document:getTileCacheValidity()
    return self.tile_cache_validity_ts
end

function Document:setTileCacheValidity(ts)
    self.tile_cache_validity_ts = ts
end

function Document:resetTileCacheValidity()
    self.tile_cache_validity_ts = os.time()
end

function Document:getFullPageHash(pageno, zoom, rotation, gamma)
    return "renderpg|"..self.file.."|"..self.mod_time.."|"..pageno.."|"
                    ..zoom.."|"
                    ..rotation.."|"..gamma.."|"..self.render_mode..(self.render_color and "|color" or "|bw")
                    ..(self.reflowable_font_size and "|"..self.reflowable_font_size or "")
end

function Document:getPagePartHash(pageno, zoom, rotation, gamma, rect)
    return "renderpgpart|"..self.file.."|"..self.mod_time.."|"..pageno.."|"
                    ..tostring(rect).."|"..zoom.."|"..tostring(rect.scaled_rect).."|"
                    ..rotation.."|"..gamma.."|"..self.render_mode..(self.render_color and "|color" or "|bw")
                    ..(self.reflowable_font_size and "|"..self.reflowable_font_size or "")
end

function Document:renderPage(pageno, rect, zoom, rotation, gamma, hinting)
    -- If rect contains a nested scaled_rect object, our caller handled scaling itself (e.g., drawPagePart)
    local is_prescaled = rect and rect.scaled_rect ~= nil or false

    local hash, hash_excerpt, tile
    if is_prescaled then
        hash = self:getPagePartHash(pageno, zoom, rotation, gamma, rect)

        tile = DocCache:check(hash, TileCacheItem)
    else
        hash = self:getFullPageHash(pageno, zoom, rotation, gamma)

        tile = DocCache:check(hash, TileCacheItem)

        -- In the is_prescaled branch above, we're *already* only rendering part of the page
        if not tile and rect then
            hash_excerpt = hash.."|"..tostring(rect)
            tile = DocCache:check(hash_excerpt)
        end
    end
    if tile then
        if self.tile_cache_validity_ts then
            if tile.created_ts and tile.created_ts >= self.tile_cache_validity_ts then
                return tile
            end
            logger.dbg("discarding stale cached tile")
        else
            return tile
        end
    end

    if hinting then
        CanvasContext:enableCPUCores(2)
    end

    local page_size = self:getPageDimensions(pageno, zoom, rotation)

    -- This will be the actual render size (i.e., the BB's dimensions)
    local size
    if is_prescaled then
        -- Our caller already handled the scaling, honor it.
        -- And we don't particulalry care whether DocCache will be able to cache it in RAM, so no need to double-check.
        size = rect.scaled_rect
    else
        -- We prefer to render the full page, if it fits into cache...
        size = page_size
        if not DocCache:willAccept(size.w * size.h * (self.render_color and 4 or 1) + 512) then
            -- ...and if it doesn't...
            logger.dbg("Attempting to render only part of the page:", rect)
            --- @todo figure out how to better segment the page
            if not rect then
                logger.warn("No render region was specified, we won't render the page at all!")
                -- no rect specified, abort
                if hinting then
                    CanvasContext:enableCPUCores(1)
                end
                return
            end
            -- ...only render the requested rect
            hash = hash_excerpt
            size = rect
        end
    end

    -- Prepare our BB, and wrap it in a cache item for DocCache
    tile = TileCacheItem:new{
        persistent = not is_prescaled, -- we don't want to dump page fragments to disk (unnecessary, and it would confuse DocCache's heuristics)
        doc_path = self.file,
        created_ts = os.time(),
        excerpt = size,
        pageno = pageno,
        bb = Blitbuffer.new(size.w, size.h, self.render_color and self.color_bb_type or nil)
    }
    tile.size = tonumber(tile.bb.stride) * tile.bb.h + 512 -- estimation

    -- We need a draw context
    local dc = DrawContext.new()

    dc:setRotate(rotation)
    -- Make the context match the rotation,
    -- by pointing at the rotated origin via coordinates offsets.
    -- NOTE: We rotate our *Screen* bb on rotation (SetRotationMode), not the document,
    --       so we hardly ever exercize this codepath...
    --       AFAICT, the only thing that *ever* (attempted to) rotate the document was ReaderRotation's key bindings (RotationUpdate).
    --- @note: It was broken as all hell (it had likely never worked outside of its original implementation in KPV), and has been removed in #12658
    if rotation == 90 then
        dc:setOffset(page_size.w, 0)
    elseif rotation == 180 then
        dc:setOffset(page_size.w, page_size.h)
    elseif rotation == 270 then
        dc:setOffset(0, page_size.h)
    end
    dc:setZoom(zoom)

    if gamma ~= self.GAMMA_NO_GAMMA then
        dc:setGamma(gamma)
    end

    -- And finally, render the page in our BB
    local page = self._document:openPage(pageno)
    page:draw(dc, tile.bb, size.x, size.y, self.render_mode)
    page:close()
    DocCache:insert(hash, tile)

    if hinting then
        CanvasContext:enableCPUCores(1)
    end
    return tile
end

-- a hint for the cache engine to paint a full page to the cache
--- @todo this should trigger a background operation
function Document:hintPage(pageno, zoom, rotation, gamma)
    logger.dbg("hinting page", pageno)
    self:renderPage(pageno, nil, zoom, rotation, gamma, true)
end

--[[
Draw page content to blitbuffer.
1. find tile in cache
2. if not found, call renderPage

@target: target blitbuffer
@rect: visible_area inside document page
--]]
function Document:drawPage(target, x, y, rect, pageno, zoom, rotation, gamma)
    local tile = self:renderPage(pageno, rect, zoom, rotation, gamma)
    -- Enable SW dithering if requested (only available in koptoptions)
    if self.sw_dithering then
        target:ditherblitFrom(tile.bb,
            x, y,
            rect.x - tile.excerpt.x,
            rect.y - tile.excerpt.y,
            rect.w, rect.h)
    else
        target:blitFrom(tile.bb,
            x, y,
            rect.x - tile.excerpt.x,
            rect.y - tile.excerpt.y,
            rect.w, rect.h)
    end
end

function Document:getDrawnImagesStatistics()
    -- For now, only set by CreDocument in CreDocument:drawCurrentView()
    -- Returns 0, 0 (as per Document:init) otherwise.
    return self._drawn_images_count, self._drawn_images_surface_ratio
end

function Document:drawPagePart(pageno, native_rect, rotation)
    -- native_rect is straight from base, so not a Geom
    local rect = Geom:new(native_rect)

    local canvas_size = CanvasContext:getSize()
    -- Compute a zoom in order to scale to best fit, so that ImageViewer doesn't have to rescale further.
    -- Optionally, based on ImageViewer settings, we'll auto-rotate for the best resolution.
    local rotate = false
    if G_reader_settings:isTrue("imageviewer_rotate_auto_for_best_fit") then
        rotate = (canvas_size.w > canvas_size.h) ~= (rect.w > rect.h)
    end
    local zoom = rotate and math.min(canvas_size.w / rect.h, canvas_size.h / rect.w) or math.min(canvas_size.w / rect.w, canvas_size.h / rect.h)
    local scaled_rect = self:transformRect(rect, zoom, rotation)
    -- Stuff it inside rect so renderPage knows we're handling scaling ourselves
    rect.scaled_rect = scaled_rect

    -- Enable SMP via the hinting flag
    local tile = self:renderPage(pageno, rect, zoom, rotation, 1.0, true)
    return tile.bb, rotate
end

function Document:getPageText(pageno)
    -- is this worth caching? not done yet.
    local page = self._document:openPage(pageno)
    local text = page:getPageText()
    page:close()
    return text
end

function Document:saveHighlight(pageno, item)
    return nil
end

function Document:deleteHighlight(pageno, item)
    return nil
end

function Document:updateHighlightContents(pageno, item, contents)
    return nil
end

--[[
helper functions
--]]
function Document:logMemoryUsage(pageno)
    local status_file = io.open("/proc/self/status", "r")
    local log_file = io.open("mem_usage_log.txt", "a+")
    local data = -1
    if status_file then
        for line in status_file:lines() do
            local s, n
            s, n = line:gsub("VmData:%s-(%d+) kB", "%1")
            if n ~= 0 then data = tonumber(s) end
            if data ~= -1 then break end
        end
        status_file:close()
    end
    if log_file then
        if log_file:seek("end") == 0 then -- write the header only once
            log_file:write("PAGE\tMEM\n")
        end
        log_file:write(string.format("%s\t%s\n", pageno, data))
        log_file:close()
    end
end

return Document
