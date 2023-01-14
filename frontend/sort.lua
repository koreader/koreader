--[[
This module contains a collection of comparison functions for table.sort
@module sort
]]

local sort = {}

--[[--
Natural sorting functions, for use with table.sort
<http://notebook.kulchenko.com/algorithms/alphanumeric-natural-sorting-for-humans-in-lua>
--]]
-- Original implementation by Paul Kulchenko
--[[
local function addLeadingZeroes(d)
    local dec, n = string.match(d, "(%.?)0*(.+)")
    return #dec > 0 and ("%.12f"):format(d) or ("%s%03d%s"):format(dec, #n, n)
end
function sort.natsort(a, b)
    return tostring(a):gsub("%.?%d+", addLeadingZeroes)..("%3d"):format(#b)
           < tostring(b):gsub("%.?%d+", addLeadingZeroes)..("%3d"):format(#a)
end
--]]
-- Hardened (but more expensive) implementation by Egor Skriptunoff, with an UTF-8 tweak by Paul Kulchenko
local function natsort_conv(s)
    local res, dot = "", ""
    for n, m, c in tostring(s):gmatch("(0*(%d*))(.?)") do
        if n == "" then
            dot, c = "", dot..c
        else
            res = res..(dot == "" and ("%03d%s"):format(#m, m)
                                   or "."..n)
            dot, c = c:match("(%.?)(.*)")
        end
        res = res..c:gsub("[%z\1-\127\192-\255]", "\0%0")
    end
    return res
end
-- The above conversion is *fairly* expensive,
-- and table.sort ensures that it'll be called on identical strings multiple times,
-- so keeping a cache of massaged strings makes sense.
-- <https://github.com/koreader/koreader/pull/10023#discussion_r1069776657>
-- Rely on LRU to avoid explicit cache maintenance concerns
-- (given the type of content we massage, the memory impact is fairly insignificant).
-- The extra persistence this affords us also happens to help with the FM use-case ;).

-- Dumb hash-map => cold, ~200 to 250ms; hot: ~150ms (which roughly matches sorting by numerical file attributes).
--[[
local natsort_caches = {
    default = {}
}
local natsort_cache = natsort_caches.default

function sort.natsort(a, b)
    local ca, cb = natsort_cache[a], natsort_cache[b]
    if not ca then
        ca = natsort_conv(a)
        natsort_cache[a] = ca
    end
    if not cb then
        cb = natsort_conv(b)
        natsort_cache[b] = cb
    end

    return ca < cb or ca == cb and a < b
end

function sort.natsort_set_cache(tag)
    if not natsort_caches[tag] then
        natsort_caches[tag] = {}
    end

    natsort_cache = natsort_caches[tag]
end
--]]

-- LRU => cold, ~200 to 250ms; hot ~150 to 175ms (which is barely any slower than a dumb hash-map, yay, LRU and LuaJIT magic).
local lru = require("ffi/lru")
local natsort_caches = {
    global = lru.new(512, nil, false),
}
local natsort_cache = natsort_caches.global

function sort.natsort(a, b)
    local ca, cb = natsort_cache:get(a), natsort_cache:get(b)
    if not ca then
        ca = natsort_conv(a)
        natsort_cache:set(a, ca)
    end
    if not cb then
        cb = natsort_conv(b)
        natsort_cache:set(b, cb)
    end

    return ca < cb or ca == cb and a < b
end

function sort.natsort_set_cache(tag, slots)
    print("sort.natsort_set_cache", tag, slots)
    -- Add a bit of scratch space to account for subsequent calls
    if slots then
        slots = math.ceil(slots * 1.25)
    else
        slots = 1024
    end

    if not natsort_caches[tag] then
        print("settings up", slots, "slots for", tag)
        natsort_caches[tag] = lru.new(slots, nil, false)
    else
        if slots > natsort_caches[tag]:total_slots() then
            print("growing", tag, "from", natsort_caches[tag]:total_slots(), "to", slots)
            natsort_caches[tag]:resize_slots(slots)
        end
    end

    natsort_cache = natsort_caches[tag]
end

return sort
