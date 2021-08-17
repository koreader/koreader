local Blitbuffer = require("ffi/blitbuffer")
local CacheItem = require("cacheitem")
local Persist = require("persist")
local logger = require("logger")

local TileCacheItem = CacheItem:new{}

function TileCacheItem:onFree()
    logger.dbg("TileCacheItem: free blitbuffer", self.bb)
    self.bb:free()
end

--- @note: Perhaps one day we'll be able to teach bitser or string.buffer about custom structs with pointers to buffers,
---        so we won't have to do the BB tostring/fromstring dance anymore...
function TileCacheItem:totable()
    local t = {
        size = self.size,
        pageno = self.pageno,
        excerpt = self.excerpt,
        created_ts = self.created_ts,
        persistent = self.persistent,
        bb = {
            w = self.bb.w,
            h = self.bb.h,
            stride = tonumber(self.bb.stride),
            fmt = self.bb:getType(),
            data = Blitbuffer.tostring(self.bb),
        },
    }

    return t
end

function TileCacheItem:dump(filename)
    logger.dbg("Dumping tile cache to", filename, self.excerpt)

    local cache_file = Persist:new{
        path = filename,
        codec = "zstd",
    }

    local ok, size = cache_file:save(self:totable())
    if ok then
        return size
    else
        logger.warn("Failed to dump tile cache")
        return nil
    end
end

function TileCacheItem:fromtable(t)
    self.size = t.size
    self.pageno = t.pageno
    self.excerpt = t.excerpt
    self.created_ts = t.created_ts
    self.persistent = t.persistent
    self.bb = Blitbuffer.fromstring(t.bb.w, t.bb.h, t.bb.fmt, t.bb.data, t.bb.stride)
end

function TileCacheItem:load(filename)
    local cache_file = Persist:new{
        path = filename,
        codec = "zstd",
    }

    local t = cache_file:load(filename)
    if t then
        self:fromtable(t)

        logger.dbg("Loaded tile cache from", filename, self)
    else
        logger.warn("Failed to load tile cache from", filename)
    end
end

return TileCacheItem
