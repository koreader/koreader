--[[
This module contains a collection of comparison functions (or factories for comparison functions) for table.sort
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
-- We can rely on LRU to avoid explicit cache maintenance concerns
-- (given the type of content we massage, the memory impact is fairly insignificant).
-- The extra persistence this affords us also happens to help with the FM use-case ;).

-- Dumb persistent hash-map => cold, ~200 to 250ms; hot: ~150ms (which roughly matches sorting by numerical file attributes).
-- (Numbers are from the FM sorting 350 entries (mostly composed of author names) on an H2O).
--[[
local natsort_cache = {}

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
--]]

-- LRU => cold, ~200 to 250ms; hot ~150 to 175ms (which is barely any slower than a dumb hash-map, yay, LRU and LuaJIT magic).
--[[
local lru = require("ffi/lru")
local natsort_cache = lru.new(512, nil, false)

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
--]]

-- TODO: LuaDoc
function sort.natsort_cmp(operands_func, cache)
    if not cache then
        cache = {}
        print("setting up cache", cache)
    end

    local natsort
    if operands_func then
        natsort = function(a, b)
            a, b = operands_func(a, b)
            local ca, cb = cache[a], cache[b]
            if not ca then
                ca = natsort_conv(a)
                cache[a] = ca
            end
            if not cb then
                cb = natsort_conv(b)
                cache[b] = cb
            end

            return ca < cb or ca == cb and a < b
        end
    else
        natsort = function(a, b)
            local ca, cb = cache[a], cache[b]
            if not ca then
                ca = natsort_conv(a)
                cache[a] = ca
            end
            if not cb then
                cb = natsort_conv(b)
                cache[b] = cb
            end

            return ca < cb or ca == cb and a < b
        end
    end
    return natsort, cache
end

return sort
