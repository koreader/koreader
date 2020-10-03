local Blitbuffer = require("ffi/blitbuffer")
local CacheItem = require("cacheitem")
local serial = require("serialize")
local logger = require("logger")

local TileCacheItem = CacheItem:new{}

function TileCacheItem:onFree()
    if self.bb.free then
        logger.dbg("free blitbuffer", self.bb)
        self.bb:free()
    end
end

function TileCacheItem:dump(filename)
    logger.dbg("dumping tile cache to", filename, self.excerpt)
    return serial.dump(self.size, self.excerpt, self.pageno,
            self.bb.w, self.bb.h, self.bb.stride, self.bb:getType(),
            Blitbuffer.tostring(self.bb), filename)
end

function TileCacheItem:load(filename)
    local w, h, stride, bb_type, bb_data
    self.size, self.excerpt, self.pageno,
            w, h, stride, bb_type, bb_data = serial.load(filename)
    self.bb = Blitbuffer.fromstring(w, h, bb_type, bb_data, stride)
    logger.dbg("loading tile cache from", filename, self)
end

return TileCacheItem
