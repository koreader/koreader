--[[
Inheritable abstraction for cache items
--]]

local CacheItem = {
    size = 128, -- some reasonable default for a small table
}

function CacheItem:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function CacheItem:onFree()
end

return CacheItem
