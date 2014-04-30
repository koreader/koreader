local Blitbuffer = require("ffi/blitbuffer")
local CacheItem = require("cacheitem")
local serial = require("serialize")
local DEBUG = require("dbg")

local TileCacheItem = CacheItem:new{}

function TileCacheItem:onFree()
    if self.bb.free then
        DEBUG("free blitbuffer", self.bb)
        self.bb:free()
    end
end

function TileCacheItem:dump(filename)
    DEBUG("dumping tile cache to", filename, self.excerpt)
    return serial.dump(self.size, self.excerpt, self.pageno,
            self.bb.w, self.bb.h, self.bb.pitch, self.bb:getType(),
            Blitbuffer.tostring(self.bb), filename)
end

function TileCacheItem:load(filename)
    local w, h, pitch, bb_type, bb_data
    self.size, self.excerpt, self.pageno,
            w, h, pitch, bb_type, bb_data = serial.load(filename)
    self.bb = Blitbuffer.fromstring(w, h, bb_type, bb_data, pitch)
    DEBUG("loading tile cache from", filename, self)
end

return TileCacheItem
