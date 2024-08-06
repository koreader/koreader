--[[
A LRU cache, based on https://github.com/starius/lua-lru
]]--

local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local lru = require("ffi/lru")
local md5 = require("ffi/sha2").md5
local util = require("util")

local Cache = {
    -- Cache configuration:
    -- Max storage space, in bytes...
    size = nil,
    -- ...Average item size, used to compute the amount of slots in the LRU.
    avg_itemsize = nil,
    -- Or, simply set the number of slots, with no storage space limitation.
    -- c.f., GlyphCache, CatalogCache
    slots = nil,
    -- Should LRU call the object's onFree method on eviction? Implies using CacheItem instead of plain tables/objects.
    -- c.f., DocCache
    enable_eviction_cb = false,
    -- Generally, only DocCache uses this
    disk_cache = false,
    cache_path = nil,
}

function Cache:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    if o.init then o:init() end
    return o
end

function Cache:init()
    if self.slots then
        -- Caller doesn't care about storage space, just slot count
        self.cache = lru.new(self.slots, nil, self.enable_eviction_cb)
    else
        -- Compute the amount of slots in the LRU based on the max size & the average item size
        self.slots = math.ceil(self.size / self.avg_itemsize)
        self.cache = lru.new(self.slots, self.size, self.enable_eviction_cb)
    end

    if self.disk_cache then
        self.cached = self:_getDiskCache()
    else
        -- No need to go through our own check or even get methods if there's no disk cache, hit lru directly
        self.check = self.cache.get
    end

    if not self.enable_eviction_cb or not self.size then
        -- We won't be using CacheItem here, so we can pass the size manually if necessary.
        -- e.g., insert's signature is now (key, value, [size]), instead of relying on CacheItem's size field.
        self.insert = self.cache.set

        -- With debug info (c.f., below)
        --self.insert = self.set
    end
end

--[[
-- return a snapshot of disk cached items for subsequent check
--]]
function Cache:_getDiskCache()
    local cached = {}
    for key_md5 in lfs.dir(self.cache_path) do
        local file = self.cache_path .. key_md5
        if lfs.attributes(file, "mode") == "file" then
            cached[key_md5] = file
        end
    end
    return cached
end

function Cache:insert(key, object)
    -- If this object is single-handledly too large for the cache, don't cache it.
    if not self:willAccept(object.size) then
        logger.warn("Too much memory would be claimed by caching", key)
        return
    end

    self.cache:set(key, object, object.size)

    -- Accounting debugging
    --self:_insertion_stats(key, object.size)
end

--[[
function Cache:set(key, object, size)
    self.cache:set(key, object, size)

    -- Accounting debugging
    self:_insertion_stats(key, size)
end

function Cache:_insertion_stats(key, size)
    print(string.format("Cache %s (%d/%d) [%.2f/%.2f @ ~%db] inserted %db key: %s",
                        self,
                        self.cache:used_slots(), self.slots,
                        self.cache:used_size() / 1024 / 1024, (self.size or 0) / 1024 / 1024, self.cache:used_size() / self.cache:used_slots(),
                        size or 0, key))
end
--]]

--[[
--  check for cache item by key
--  if ItemClass is given, disk cache is also checked.
--]]
function Cache:check(key, ItemClass)
    local value = self.cache:get(key)
    if value then
        return value
    elseif ItemClass then
        local cached = self.cached[md5(key)]
        if cached then
            local item = ItemClass:new{}
            local ok, msg = pcall(item.load, item, cached)
            if ok then
                self:insert(key, item)
                return item
            else
                logger.warn("Failed to load on-disk cache:", msg)
                --- It's apparently unusable, purge it and refresh the snapshot.
                os.remove(cached)
                self:refreshSnapshot()
            end
        end
    end
end

-- Shortcut when disk_cache is disabled
function Cache:get(key)
    return self.cache:get(key)
end

function Cache:willAccept(size)
    -- We only allow a single object to fill 50% of the cache
    return size*4 < self.size*2
end

-- Blank the cache
function Cache:clear()
    self.cache:clear()
end

-- Terribly crappy workaround: evict half the cache if we appear to be redlining on free RAM...
function Cache:memoryPressureCheck()
    local memfree, memtotal = util.calcFreeMem()

    -- Nonsensical values? (!Linux), skip this.
    if memtotal == nil then
        return
    end

    -- If less that 20% of the total RAM is free, drop half the Cache...
    local free_fraction = memfree / memtotal
    if free_fraction < 0.20 then
        logger.warn(string.format("Running low on memory (~%d%%, ~%.2f/%d MiB), evicting half of the cache...",
                                  free_fraction * 100,
                                  memfree / (1024 * 1024),
                                  memtotal / (1024 * 1024)))
        self.cache:chop()

        -- And finish by forcing a GC sweep now...
        collectgarbage()
        collectgarbage()
    end
end

-- Refresh the disk snapshot (mainly used by ui/data/onetime_migration)
function Cache:refreshSnapshot()
    if not self.disk_cache then
        return
    end

    self.cached = self:_getDiskCache()
end

-- Evict the disk cache (ditto)
function Cache:clearDiskCache()
    if not self.disk_cache then
        return
    end

    for _, file in pairs(self.cached) do
        os.remove(file)
    end

    self:refreshSnapshot()
end

return Cache
