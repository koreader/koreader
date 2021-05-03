--[[
A global LRU cache
]]--

local DataStorage = require("datastorage")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local md5 = require("ffi/sha2").md5

local CanvasContext = require("document/canvascontext")
if CanvasContext.should_restrict_JIT then
    jit.off(true, true)
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
local function calcFreeMem()
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

local function calcCacheMemSize()
    local min = DGLOBAL_CACHE_SIZE_MINIMUM
    local max = DGLOBAL_CACHE_SIZE_MAXIMUM
    local calc = calcFreeMem() * (DGLOBAL_CACHE_FREE_PROPORTION or 0)
    return math.min(max, math.max(min, calc))
end

local cache_path = DataStorage:getDataDir() .. "/cache/"

--[[
-- return a snapshot of disk cached items for subsequent check
--]]
local function getDiskCache()
    local cached = {}
    for key_md5 in lfs.dir(cache_path) do
        local file = cache_path .. key_md5
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

-- internal: remove reference in cache_order list
function Cache:_unref(key)
    for i = #self.cache_order, 1, -1 do
        if self.cache_order[i] == key then
            table.remove(self.cache_order, i)
            break
        end
    end
end

-- internal: free cache item
function Cache:_free(key)
    self.current_memsize = self.current_memsize - self.cache[key].size
    self.cache[key]:onFree()
    self.cache[key] = nil
end

-- drop an item named via key from the cache
function Cache:drop(key)
    if not self.cache[key] then return end

    self:_unref(key)
    self:_free(key)
end

function Cache:insert(key, object)
    -- make sure that one key only exists once: delete existing
    self:drop(key)
    -- If this object is single-handledly too large for the cache, we're done
    if object.size > self.max_memsize then
        logger.warn("Too much memory would be claimed by caching", key)
        return
    end
    -- If inserting this obect would blow the cache's watermark,
    -- start dropping least recently used items first.
    -- (they are at the end of the cache_order array)
    while self.current_memsize + object.size > self.max_memsize do
        local removed_key = table.remove(self.cache_order)
        if removed_key then
            self:_free(removed_key)
        else
            logger.warn("Cache accounting is broken")
            break
        end
    end
    -- Insert new object in front of the LRU order
    table.insert(self.cache_order, 1, key)
    self.cache[key] = object
    self.current_memsize = self.current_memsize + object.size
end

--[[
--  check for cache item by key
--  if ItemClass is given, disk cache is also checked.
--]]
function Cache:check(key, ItemClass)
    if self.cache[key] then
        if self.cache_order[1] ~= key then
            -- Move key in front of the LRU list (i.e., MRU)
            self:_unref(key)
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
                logger.warn("Failed to load on-disk cache:", msg)
                --- It's apparently unusable, purge it and refresh the snapshot.
                os.remove(cached)
                self:refreshSnapshot()
            end
        end
    end
end

function Cache:willAccept(size)
    -- We only allow single objects to fill 75% of the cache
    return size*4 < self.max_memsize*3
end

function Cache:serialize()
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
    for _, key in ipairs(self.cache_order) do
        local cache_item = self.cache[key]

        -- Only dump cache items that actually request persistence
        if cache_item.persistent and cache_item.dump then
            mru_key = key
            mru_found = mru_found + 1
            if mru_found >= 2 then
                -- We found the second MRU item, i.e., the *displayed* page
                break
            end
        end
    end
    if mru_key then
        local cache_full_path = cache_path .. md5(mru_key)
        local cache_file_exists = lfs.attributes(cache_full_path)

        if not cache_file_exists then
            logger.dbg("Dumping cache item", mru_key)
            local cache_item = self.cache[mru_key]
            local cache_size = cache_item:dump(cache_full_path)
            if cache_size then
                cached_size = cached_size + cache_size
            end
        end
    end

    -- Allocate the same amount of storage to the disk cache than the memory cache
    while cached_size > self.max_memsize do
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
    for k, _ in pairs(self.cache) do
        self.cache[k]:onFree()
    end
    self.cache = {}
    self.cache_order = {}
    self.current_memsize = 0
end

-- Terribly crappy workaround: evict half the cache if we appear to be redlining on free RAM...
function Cache:memoryPressureCheck()
    local memfree, memtotal = calcFreeMem()

    -- Nonsensical values? (!Linux), skip this.
    if memtotal == 0 then
        return
    end

    -- If less that 20% of the total RAM is free, drop half the Cache...
    if memfree / memtotal < 0.20 then
        logger.warn("Running low on memory, evicting half of the cache...")
        for i = #self.cache_order / 2, 1, -1 do
            local removed_key = table.remove(self.cache_order)
            self:_free(removed_key)
        end

        -- And finish by forcing a GC sweep now...
        collectgarbage()
        collectgarbage()
    end
end

-- Refresh the disk snapshot (mainly used by ui/data/onetime_migration)
function Cache:refreshSnapshot()
    self.cached = getDiskCache()
end

-- Evict the disk cache (ditto)
function Cache:clearDiskCache()
    for _, file in pairs(self.cached) do
        os.remove(file)
    end

    self:refreshSnapshot()
end

return Cache
