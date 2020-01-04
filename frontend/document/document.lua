local Blitbuffer = require("ffi/blitbuffer")
local Cache = require("cache")
local CacheItem = require("cacheitem")
local Configurable = require("configurable")
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

    links = {},

    GAMMA_NO_GAMMA = 1.0,

    -- override bbox from orignal page's getUsedBBox
    bbox = {},

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

}

function Document:new(from_o)
    local o = from_o or {}
    setmetatable(o, self)
    self.__index = self
    if o._init then o:_init() end
    if o.init then o:init() end
    return o
end

-- base document initialization should be called on each document init
function Document:_init()
    self.configurable = Configurable:new()
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

    -- Should be updated by a call to Document.updateColorRendering(self)
    -- in subclasses
    self.render_color = false
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
function Document:close()
    local DocumentRegistry = require("document/documentregistry")
    if self.is_open and DocumentRegistry:closeDocument(self.file) == 0 then
        self.is_open = false
        self._document:close()
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

-- calculate partial digest of the document and store in its docsettings to avoid document saving
-- feature to change its checksum.
--
-- To the calculating mechanism itself.
-- since only PDF documents could be modified by KOReader by appending data
-- at the end of the files when highlighting, we use a non-even sampling
-- algorithm which samples with larger weight at file head and much smaller
-- weight at file tail, thus reduces the probability that appended data may change
-- the digest value.
-- Note that if PDF file size is around 1024, 4096, 16384, 65536, 262144
-- 1048576, 4194304, 16777216, 67108864, 268435456 or 1073741824, appending data
-- by highlighting in KOReader may change the digest value.
function Document:fastDigest(docsettings)
    if not self.file then return end
    local file = io.open(self.file, 'rb')
    if file then
        local tmp_docsettings = false
        if not docsettings then -- if not provided, open/create it
            docsettings = require("docsettings"):open(self.file)
            tmp_docsettings = true
        end
        local result = docsettings:readSetting("partial_md5_checksum")
        if not result then
            logger.dbg("computing and storing partial_md5_checksum")
            local bit = require("bit")
            local md5 = require("ffi/MD5")
            local lshift = bit.lshift
            local step, size = 1024, 1024
            local m = md5.new()
            for i = -1, 10 do
                file:seek("set", lshift(step, 2*i))
                local sample = file:read(size)
                if sample then
                    m:update(sample)
                else
                    break
                end
            end
            result = m:sum()
            docsettings:saveSetting("partial_md5_checksum", result)
        end
        if tmp_docsettings then
            docsettings:close()
        end
        file:close()
        return result
    end
end

-- this might be overridden by a document implementation
function Document:getNativePageDimensions(pageno)
    local hash = "pgdim|"..self.file.."|"..pageno
    local cached = Cache:check(hash)
    if cached then
        return cached[1]
    end
    local page = self._document:openPage(pageno)
    local page_size_w, page_size_h = page:getSize(self.dc_null)
    local page_size = Geom:new{ w = page_size_w, h = page_size_h }
    Cache:insert(hash, CacheItem:new{ page_size })
    page:close()
    return page_size
end

function Document:getProps()
    return self._document:getDocumentProps()
end

function Document:_readMetadata()
    self.mod_time = lfs.attributes(self.file, "modification")
    self.info.number_of_pages = self._document:getPages()
    return true
end

function Document:getPageCount()
    return self.info.number_of_pages
end

-- calculates page dimensions
function Document:getPageDimensions(pageno, zoom, rotation)
    local native_dimen = self:getNativePageDimensions(pageno):copy()
    if rotation == 90 or rotation == 270 then
        -- switch orientation
        native_dimen.w, native_dimen.h = native_dimen.h, native_dimen.w
    end
    native_dimen:scaleBy(zoom)
    return native_dimen
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
    if bbox.x1 < 0 then bbox.x1 = 0 end
    if bbox.y1 < 0 then bbox.y1 = 0 end
    local ubbox_dimen
    if (bbox.x0 >= bbox.x1) or (bbox.y0 >= bbox.y1) then
        -- if document's bbox info is corrupted, we use the page size
        ubbox_dimen = self:getPageDimensions(pageno, zoom, rotation)
    else
        ubbox_dimen = Geom:new{
            x = bbox.x0,
            y = bbox.y0,
            w = bbox.x1 - bbox.x0,
            h = bbox.y1 - bbox.y0,
        }
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

function Document:updateColorRendering()
    if self.is_color_capable and CanvasContext.is_color_rendering_enabled then
        self.render_color = true
    else
        self.render_color = false
    end
end

function Document:preRenderPage()
    return nil
end

function Document:postRenderPage()
    return nil
end

function Document:getFullPageHash(pageno, zoom, rotation, gamma, render_mode, color)
    return "renderpg|"..self.file.."|"..self.mod_time.."|"..pageno.."|"
                    ..zoom.."|"..rotation.."|"..gamma.."|"..render_mode..(color and "|color" or "")
                    ..(self.reflowable_font_size and "|"..self.reflowable_font_size or "")
end

function Document:renderPage(pageno, rect, zoom, rotation, gamma, render_mode)
    local hash_excerpt
    local hash = self:getFullPageHash(pageno, zoom, rotation, gamma, render_mode, self.render_color)
    local tile = Cache:check(hash, TileCacheItem)
    if not tile then
        hash_excerpt = hash.."|"..tostring(rect)
        tile = Cache:check(hash_excerpt)
    end
    if tile then return tile end

    self:preRenderPage()

    local page_size = self:getPageDimensions(pageno, zoom, rotation)
    -- this will be the size we actually render
    local size = page_size
    -- we prefer to render the full page, if it fits into cache
    if not Cache:willAccept(size.w * size.h + 64) then
        -- whole page won't fit into cache
        logger.dbg("rendering only part of the page")
        --- @todo figure out how to better segment the page
        if not rect then
            logger.warn("aborting, since we do not have a specification for that part")
            -- required part not given, so abort
            return
        end
        -- only render required part
        hash = hash_excerpt
        size = rect
    end

    -- prepare cache item with contained blitbuffer
    tile = TileCacheItem:new{
        persistent = true,
        size = size.w * size.h + 64, -- estimation
        excerpt = size,
        pageno = pageno,
        bb = Blitbuffer.new(size.w, size.h, self.render_color and self.color_bb_type or nil)
    }

    -- create a draw context
    local dc = DrawContext.new()

    dc:setRotate(rotation)
    -- correction of rotation
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

    -- render
    local page = self._document:openPage(pageno)
    page:draw(dc, tile.bb, size.x, size.y, render_mode)
    page:close()
    Cache:insert(hash, tile)

    self:postRenderPage()
    return tile
end

-- a hint for the cache engine to paint a full page to the cache
--- @todo this should trigger a background operation
function Document:hintPage(pageno, zoom, rotation, gamma, render_mode)
    logger.dbg("hinting page", pageno)
    self:renderPage(pageno, nil, zoom, rotation, gamma, render_mode)
end

--[[
Draw page content to blitbuffer.
1. find tile in cache
2. if not found, call renderPage

@target: target blitbuffer
@rect: visible_area inside document page
--]]
function Document:drawPage(target, x, y, rect, pageno, zoom, rotation, gamma, render_mode)
    local tile = self:renderPage(pageno, rect, zoom, rotation, gamma, render_mode)
    target:blitFrom(tile.bb,
        x, y,
        rect.x - tile.excerpt.x,
        rect.y - tile.excerpt.y,
        rect.w, rect.h)
end

function Document:getDrawnImagesStatistics()
    -- For now, only set by CreDocument in CreDocument:drawCurrentView()
    return self._drawn_images_count, self._drawn_images_surface_ratio
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
