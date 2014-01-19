--[[
A global LRU cache
]]--
local function calcFreeMem()
	local meminfo = io.open("/proc/meminfo", "r")
	local freemem = 0
	if meminfo then
		for line in meminfo:lines() do
			local free, buffer, cached, n
			free, n = line:gsub("^MemFree:%s-(%d+) kB", "%1")
			if n ~= 0 then freemem = freemem + tonumber(free)*1024 end
			buffer, n = line:gsub("^Buffers:%s-(%d+) kB", "%1")
			if n ~= 0 then freemem = freemem + tonumber(buffer)*1024 end
			cached, n = line:gsub("^Cached:%s-(%d+) kB", "%1")
			if n ~= 0 then freemem = freemem + tonumber(cached)*1024 end
		end
		meminfo:close()
	end
	return freemem
end

local function calcCacheMemSize()
	local min = DGLOBAL_CACHE_SIZE_MINIMUM
	local max = DGLOBAL_CACHE_SIZE_MAXIMUM
	local calc = calcFreeMem()*(DGLOBAL_CACHE_FREE_PROPORTION or 0)
	return math.min(max, math.max(min, calc))
end

local Cache = {
	-- cache configuration:
	max_memsize = calcCacheMemSize(),
	-- cache state:
	current_memsize = 0,
	-- associative cache
	cache = {},
	-- this will hold the LRU order of the cache
	cache_order = {}
}

function Cache:new(o)
	o = o or {}
	setmetatable(o, self)
	self.__index = self
	return o
end

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

return Cache
