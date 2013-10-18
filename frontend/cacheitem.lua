--[[
Inheritable abstraction for cache items
--]]

local CacheItem = {
	size = 64, -- some reasonable default for simple Lua values / small tables
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
