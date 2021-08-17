--[[
A LRU cache, based on https://github.com/starius/lua-lru
]]--

local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local lru = require("ffi/lru")
local md5 = require("ffi/sha2").md5

local CanvasContext = require("document/canvascontext")
if CanvasContext.should_restrict_JIT then
    jit.off(true, true)
end

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
        self.slots = math.floor(self.size / self.avg_itemsize)
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

-- For documentation purposes, here's a battle-tested shell version of calcFreeMem
--[[
    if grep -q 'MemAvailable' /proc/meminfo ; then
        # We'll settle for 85% of available memory to leave a bit of breathing room
        tmpfs_size="$(awk '/MemAvailable/ {printf "%d", $2 * 0.85}' /proc/meminfo)"
    elif grep -q 'Inactive(file)' /proc/meminfo ; then
        # Basically try to emulate the kernel's computation, c.f., https://unix.stackexchange.com/q/261247
        # Again, 85% of available memory
        tmpfs_size="$(awk -v low=$(grep low /proc/zoneinfo | awk '{k+=$2}END{printf "%d", k}') \
            '{a[$1]=$2}
            END{
                printf "%d", (a["MemFree:"]+a["Active(file):"]+a["Inactive(file):"]+a["SReclaimable:"]-(12*low))*0.85;
            }' /proc/meminfo)"
    else
        # Ye olde crap workaround of Free + Buffers + Cache...
        # Take it with a grain of salt, and settle for 80% of that...
        tmpfs_size="$(awk \
            '{a[$1]=$2}
            END{
                printf "%d", (a["MemFree:"]+a["Buffers:"]+a["Cached:"])*0.80;
            }' /proc/meminfo)"
    fi
--]]

-- And here's our simplified Lua version...
function Cache:_calcFreeMem()
    local memtotal, memfree, memavailable, buffers, cached

    local meminfo = io.open("/proc/meminfo", "r")
    if meminfo then
        for line in meminfo:lines() do
            if not memtotal then
                memtotal = line:match("^MemTotal:%s-(%d+) kB")
                if memtotal then
                    -- Next!
                    goto continue
                end
            end

            if not memfree then
                memfree = line:match("^MemFree:%s-(%d+) kB")
                if memfree then
                    -- Next!
                    goto continue
                end
            end

            if not memavailable then
                memavailable = line:match("^MemAvailable:%s-(%d+) kB")
                if memavailable then
                    -- Best case scenario, we're done :)
                    break
                end
            end

            if not buffers then
                buffers = line:match("^Buffers:%s-(%d+) kB")
                if buffers then
                    -- Next!
                    goto continue
                end
            end

            if not cached then
                cached = line:match("^Cached:%s-(%d+) kB")
                if cached then
                    -- Ought to be the last entry we care about, we're done
                    break
                end
            end

            ::continue::
        end
        meminfo:close()
    else
        -- Not on Linux?
        return 0, 0
    end

    if memavailable then
        -- Leave a bit of margin, and report 85% of that...
        return math.floor(memavailable * 0.85) * 1024, memtotal * 1024
    else
        -- Crappy Free + Buffers + Cache version, because the zoneinfo approach is a tad hairy...
        -- So, leave an even larger margin, and only report 75% of that...
        return math.floor((memfree + buffers + cached) * 0.75) * 1024, memtotal * 1024
    end
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
    -- We only allow a single object to fill 75% of the cache
    return size*4 < self.size*3
end

function Cache:serialize()
    if not self.disk_cache then
        return
    end

    -- Calculate the current disk cache size
    local cached_size = 0
    local sorted_caches = {}
    for _, file in pairs(self.cached) do
        table.insert(sorted_caches, {file=file, time=lfs.attributes(file, "access")})
        cached_size = cached_size + (lfs.attributes(file, "size") or 0)
    end
    table.sort(sorted_caches, function(v1, v2) return v1.time > v2.time end)

    -- Only serialize the second most recently used cache item (as the MRU would be the *hinted* page).
    local mru_key
    local mru_found = 0
    for key, item in self.cache:pairs() do
        -- Only dump cache items that actually request persistence
        if item.persistent and item.dump then
            mru_key = key
            mru_found = mru_found + 1
            if mru_found >= 2 then
                -- We found the second MRU item, i.e., the *displayed* page
                break
            end
        end
    end
    if mru_key then
        local cache_full_path = self.cache_path .. md5(mru_key)
        local cache_file_exists = lfs.attributes(cache_full_path)

        if not cache_file_exists then
            logger.dbg("Dumping cache item", mru_key)
            local cache_item = self.cache:get(mru_key)
            local cache_size = cache_item:dump(cache_full_path)
            if cache_size then
                cached_size = cached_size + cache_size
            end
        end
    end

    -- Allocate the same amount of storage to the disk cache than the memory cache
    while cached_size > self.size do
        -- discard the least recently used cache
        local discarded = table.remove(sorted_caches)
        if discarded then
            cached_size = cached_size - lfs.attributes(discarded.file, "size")
            os.remove(discarded.file)
        else
            logger.warn("Cache accounting is broken")
            break
        end
    end
    -- We may have updated the disk cache's content, so refresh its state
    self:refreshSnapshot()
end

-- Blank the cache
function Cache:clear()
    self.cache:clear()
end

-- Terribly crappy workaround: evict half the cache if we appear to be redlining on free RAM...
function Cache:memoryPressureCheck()
    local memfree, memtotal = self:_calcFreeMem()

    -- Nonsensical values? (!Linux), skip this.
    if memtotal == 0 then
        return
    end

    -- If less that 20% of the total RAM is free, drop half the Cache...
    local free_fraction = memfree / memtotal
    if free_fraction < 0.20 then
        logger.warn(string.format("Running low on memory (~%d%%, ~%.2f/%d MiB), evicting half of the cache...",
                                  free_fraction * 100, memfree / 1024 / 1024, memtotal / 1024 / 1024))
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
