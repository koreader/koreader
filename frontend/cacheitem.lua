--[[
Inheritable abstraction for cache items
--]]

local CacheItem = {
    size = 128, -- some reasonable default for a small table.
}
--- NOTE: As far as size estimations go, the assumption is that a key, value pair should roughly take two words,
---       and the most common items we cache are Geom-like tables (i.e., 4 key-value pairs).
---       That's generally a low estimation, especially for larger tables, where memory allocation trickery may be happening.

function CacheItem:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

-- Called on eviction.
-- We generally use it to free C/FFI resources *immediately* (as opposed to relying on our Userdata/FFI finalizers to do it "later" on GC).
-- c.f., TileCacheItem
function CacheItem:onFree()
end

return CacheItem
