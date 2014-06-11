local DrawContext = require("ffi/drawcontext")
local Blitbuffer = require("ffi/blitbuffer")
local Cache = require("cache")
local CacheItem = require("cacheitem")
local TileCacheItem = require("document/tilecacheitem")
local Geom = require("ui/geometry")
local Configurable = require("configurable")
local Math = require("optmath")
local DEBUG = require("dbg")

--[[
This is an abstract interface to a document
]]--
local Document = {
    -- file name
    file = nil,

    info = {
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
    },

    links = {},

    GAMMA_NO_GAMMA = 1.0,

    -- override bbox from orignal page's getUsedBBox
    bbox = {},

    -- flag to show whether the document was opened successfully
    is_open = false,
    error_message = nil,

    -- flag to show that the document needs to be unlocked by a password
    is_locked = false,
}

function Document:new(o)
    local o = o or {}
    setmetatable(o, self)
    self.__index = self
    if o._init then o:_init() end
    if o.init then o:init() end
    return o
end

-- base document initialization should be called on each document init
function Document:_init()
    self.configurable = Configurable:new()
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
    if self.is_open then
        self.is_open = false
        self._document:close()
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

function Document:_readMetadata()
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
    --DEBUG("dimen for pageno", pageno, "zoom", zoom, "rotation", rotation, "is", native_dimen)
    return native_dimen
end

function Document:getPageBBox(pageno)
    local bbox = self.bbox[pageno] -- exact
    if bbox ~= nil then
        --DEBUG("bbox from", pageno)
        return bbox
    else
        local oddEven = Math.oddEven(pageno)
        bbox = self.bbox[oddEven] -- odd/even
    end
    if bbox ~= nil then -- last used up to this page
        --DEBUG("bbox from", oddEven)
        return bbox
    else
        for i = 0,pageno do
            bbox = self.bbox[ pageno - i ]
            if bbox ~= nil then
                --DEBUG("bbox from", pageno - i)
                return bbox
            end
        end
    end
    if bbox == nil then -- fallback bbox
        bbox = self:getUsedBBox(pageno)
        --DEBUG("bbox from ORIGINAL page")
    end
    --DEBUG("final bbox", bbox)
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
    local ubbox_dimen = nil
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

function Document:getPageLinks(pageno)
    return nil
end

function Document:getLinkFromPosition(pageno, pos)
    return nil
end

function Document:getTextBoxes(pageno)
    return nil
end

function Document:getOCRWord(pageno, rect)
    return nil
end

function Document:renderPage(pageno, rect, zoom, rotation, gamma, render_mode)
    local hash = "renderpg|"..self.file.."|"..pageno.."|"..zoom.."|"..rotation.."|"..gamma.."|"..render_mode
    local page_size = self:getPageDimensions(pageno, zoom, rotation)
    -- this will be the size we actually render
    local size = page_size
    -- we prefer to render the full page, if it fits into cache
    if not Cache:willAccept(size.w * size.h / 2) then
        -- whole page won't fit into cache
        DEBUG("rendering only part of the page")
        -- TODO: figure out how to better segment the page
        if not rect then
            DEBUG("aborting, since we do not have a specification for that part")
            -- required part not given, so abort
            return
        end
        -- only render required part
        hash = "renderpg|"..self.file.."|"..pageno.."|"..zoom.."|"..rotation.."|"..gamma.."|"..render_mode.."|"..tostring(rect)
        size = rect
    end

    -- prepare cache item with contained blitbuffer
    local tile = TileCacheItem:new{
        size = size.w * size.h / 2 + 64, -- estimation
        excerpt = size,
        pageno = pageno,
        bb = Blitbuffer.new(size.w, size.h)
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
        --DEBUG("gamma correction: ", gamma)
        dc:setGamma(gamma)
    end

    -- render
    local page = self._document:openPage(pageno)
    page:draw(dc, tile.bb, size.x, size.y, render_mode)
    page:close()
    Cache:insert(hash, tile)

    return tile
end

-- a hint for the cache engine to paint a full page to the cache
-- TODO: this should trigger a background operation
function Document:hintPage(pageno, zoom, rotation, gamma, render_mode)
    local hash_full_page = "renderpg|"..self.file.."|"..pageno.."|"..zoom.."|"..rotation.."|"..gamma.."|"..render_mode
    if not Cache:check(hash_full_page, TileCacheItem) then
        DEBUG("hinting page", pageno)
        self:renderPage(pageno, nil, zoom, rotation, gamma, render_mode)
    end
end

--[[
Draw page content to blitbuffer.
1. find tile in cache
2. if not found, call renderPage

@target: target blitbuffer
@rect: visible_area inside document page
--]]
function Document:drawPage(target, x, y, rect, pageno, zoom, rotation, gamma, render_mode)
    local hash_full_page = "renderpg|"..self.file.."|"..pageno.."|"..zoom.."|"..rotation.."|"..gamma.."|"..render_mode
    local hash_excerpt = hash_full_page.."|"..tostring(rect)
    local tile = Cache:check(hash_full_page, TileCacheItem)
    if not tile then
        tile = Cache:check(hash_excerpt)
        if not tile then
            DEBUG("rendering")
            tile = self:renderPage(pageno, rect, zoom, rotation, gamma, render_mode)
        end
    end
    DEBUG("now painting", tile, rect)
    target:blitFrom(tile.bb,
        x, y,
        rect.x - tile.excerpt.x,
        rect.y - tile.excerpt.y,
        rect.w, rect.h)
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
