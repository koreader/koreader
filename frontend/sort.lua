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
function natsort(a, b)
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
-- Rely on LRU to avoid explicit cache maintenance concerns (at the cost of a bit of memory).
-- The extra persistence this affords us also happens to help with the FM use-case ;).
local lru = require("ffi/lru")
-- We start with a small hard-coded value at require-time,
-- so as to prevent circular dependencies issues with luadefaults and early callers (e.g., userpatch).
local natsort_cache = lru.new(128, nil, false)
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

-- Set the cache to its desired size
function sort.natsort_cache_init()
    natsort_cache = lru.new(G_defaults:readSetting("DNATURAL_SORT_CACHE_SLOTS"), nil, false)
end

return sort
