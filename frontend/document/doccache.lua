--[[
"Global" LRU cache used by Document & friends.
--]]

local Cache = require("cache")
local CanvasContext = require("document/canvascontext")
local DataStorage = require("datastorage")
local logger = require("logger")

local function calcCacheMemSize()
    local min = DGLOBAL_CACHE_SIZE_MINIMUM
    local max = DGLOBAL_CACHE_SIZE_MAXIMUM
    local calc = Cache:_calcFreeMem() * (DGLOBAL_CACHE_FREE_PROPORTION or 0)
    local size = math.min(max, math.max(min, calc))

    logger.dbg(string.format("Allocating a %dMB budget for the global document cache", size / 1024 / 1024))
    return size
end

local DocCache = Cache:new{
    size = calcCacheMemSize(),
    -- Average item size is a screen's worth of bitmap, mixed with a few much smaller tables (pgdim, pglinks, etc.), hence the / 3
    avg_itemsize = math.floor(CanvasContext:getWidth() * CanvasContext:getHeight() * (CanvasContext.is_color_rendering_enabled and 4 or 1) / 3),
    -- Rely on CacheItem's eviction callback to free resources *immediately* on eviction.
    enable_eviction_cb = true,
    disk_cache = true,
    cache_path = DataStorage:getDataDir() .. "/cache/",
}

return DocCache
