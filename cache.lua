--[[
Inheritable abstraction for cache items
]]--
CacheItem = {
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

--[[
A global LRU cache
]]--
Cache = {
	-- cache configuration:
	max_memsize = 1024*1024*5, -- 5MB cache size
	-- cache state:
	current_memsize = 0,
	-- associative cache
	cache = {},
	-- this will hold the LRU order of the cache
	cache_order = {}
}

function Cache:insert(key, object)
	-- guarantee that we have enough memory in cache
	if(object.size > self.max_memsize) then
		-- we're not allowed to claim this much at all
		error("too much memory claimed")
	end
	-- delete objects that least recently used
	-- (they are at the end of the cache_order array)
	while self.current_memsize + object.size > self.max_memsize do
		local removed_key = table.remove(self.cache_order)
		self.current_memsize = self.current_memsize - self.cache[removed_key].size
		self.cache[removed_key]:onFree()
		self.cache[removed_key] = nil
	end
	-- insert new object in front of the LRU order
	table.insert(self.cache_order, 1, key)
	self.cache[key] = object
	self.current_memsize = self.current_memsize + object.size
end

function Cache:check(key)
	if self.cache[key] then
		if self.cache_order[1] ~= key then
			-- put key in front of the LRU list
			for k, v in ipairs(self.cache_order) do
				if v == key then
					table.remove(self.cache_order, k)
				end
			end
			table.insert(self.cache_order, 1, key)
		end
		return self.cache[key]
	end
end

function Cache:willAccept(size)
	-- we only allow single objects to fill 75% of the cache
	if size*4 < self.max_memsize*3 then
		return true
	end
end

-- blank the cache
function Cache:clear()
	for k, _ in pairs(self.cache) do
		self.cache[k]:onFree()
	end
	self.cache = {}
	self.cache_order = {}
	self.current_memsize = 0
end
