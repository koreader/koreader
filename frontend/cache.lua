--[[
A global LRU cache
]]--
require("MD5")
local lfs = require("libs/libkoreader-lfs")
local DEBUG = require("dbg")

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

local cache_path = lfs.currentdir().."/cache/"

--[[
-- return a snapshot of disk cached items for subsequent check
--]]
function getDiskCache()
    local cached = {}
    for key_md5 in lfs.dir(cache_path) do
        local file = cache_path..key_md5
        if lfs.attributes(file, "mode") == "file" then
            cached[key_md5] = file
        end
    end
    return cached
end

local Cache = {
    -- cache configuration:
    max_memsize = calcCacheMemSize(),
    -- cache state:
    current_memsize = 0,
    -- associative cache
    cache = {},
    -- this will hold the LRU order of the cache
    cache_order = {},
    -- disk Cache snapshot
    cached = getDiskCache(),
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
        DEBUG("too much memory claimed for", key)
        return
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

--[[
--  check for cache item for key
--  if ItemClass is given, disk cache is also checked.
--]]
function Cache:check(key, ItemClass)
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
    elseif ItemClass then
        local cached = self.cached[md5(key)]
        if cached then
            local item = ItemClass:new{}
            local ok, msg = pcall(item.load, item, cached)
            if ok then
                self:insert(key, item)
                return item
            else
                DEBUG("discard cache", msg)
            end
        end
    end
end

function Cache:willAccept(size)
    -- we only allow single objects to fill 75% of the cache
    if size*4 < self.max_memsize*3 then
        return true
    end
end

function Cache:serialize()
    -- calculate disk cache size
    local cached_size = 0
    local sorted_caches = {}
    for _,file in pairs(self.cached) do
        table.insert(sorted_caches, {file=file, time=lfs.attributes(file, "access")})
        cached_size = cached_size + (lfs.attributes(file, "size") or 0)
    end
    table.sort(sorted_caches, function(v1,v2) return v1.time > v2.time end)
    -- serialize the most recently used cache
    local cache_size = 0
    for _, key in ipairs(self.cache_order) do
        if self.cache[key].dump then
            cache_size = self.cache[key]:dump(cache_path..md5(key)) or 0
            if cache_size > 0 then break end
        end
    end
    -- set disk cache the same limit as memory cache
    while cached_size + cache_size - self.max_memsize > 0 do
        -- discard the least recently used cache
        local discarded = table.remove(sorted_caches)
        cached_size = cached_size - lfs.attributes(discarded.file, "size")
        os.remove(discarded.file)
    end
    -- disk cache may have changes so need to refresh disk cache snapshot
    self.cached = getDiskCache()
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
