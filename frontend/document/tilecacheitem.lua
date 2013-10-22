local CacheItem = require("cacheitem")
local DEBUG = require("dbg")

local TileCacheItem = CacheItem:new{}

function TileCacheItem:onFree()
	if self.bb.free then
		DEBUG("free blitbuffer", self.bb)
		self.bb:free()
	end
end

return TileCacheItem
