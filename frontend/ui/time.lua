--[[--
A simple module to compare and do arithmetic with fixed point time (seconds) values.

@usage
    local time = require("ui/time")

    local start_time = time.now()
    -- Do some stuff.
    -- You can add and subtract `fts times` objects.
    local duration = time.now() - start.fts
    -- And convert that object to various more human-readable formats, e.g.,
    print(string.format("Stuff took %.3fms", time.toMS(duration)))
]]

local ffi = require("ffi")
require("ffi/posix_h")
local logger = require("logger")

local C = ffi.C

-- Numbers in lua are double float which have a mantissa (precision) of 53 bit (plus sign + exponent)
-- We won't use the exponent here.
-- So we can store 2^53 = 9.0072*10^15 different values. If we use the lower 6 digits for µs, we can store
-- up to 9.0072*10^9 seconds.
-- A year has 365.25*24*3600 = 3.15576*10^7 s, so we can store up to 285 years (9.0072e9/3.15576e7) with µs precision.

-- A FTS_PRECISION of 1e6 will give us a µs precision.
local FTS_PRECISION = 1e6

local S2FTS = FTS_PRECISION
local MS2FTS = FTS_PRECISION / 1e3
local US2FTS = FTS_PRECISION / 1e6
local NS2FTS = FTS_PRECISION / 1e9

local FTS2S = 1 / S2FTS
local FTS2MS = 1 / MS2FTS
local FTS2US = 1 / US2FTS

-- ffi object for C.clock_gettime calls
local timespec = ffi.new("struct timespec")

-- We prefer CLOCK_MONOTONIC_COARSE if it's available and has a decent resolution,
-- as we generally don't need nano/micro second precision,
-- and it can be more than twice as fast as CLOCK_MONOTONIC/CLOCK_REALTIME/gettimeofday...
local PREFERRED_MONOTONIC_CLOCKID = C.CLOCK_MONOTONIC
-- Ditto for REALTIME (for :realtime_coarse only, :realtime uses gettimeofday ;)).
local PREFERRED_REALTIME_CLOCKID = C.CLOCK_REALTIME
-- CLOCK_BOOTTIME is only available on Linux 2.6.39+...
local HAVE_BOOTTIME = false
if ffi.os == "Linux" then
    -- Unfortunately, it was only implemented in Linux 2.6.32, and we may run on older kernels than that...
    -- So, just probe it to see if we can rely on it.
    local probe_ts = ffi.new("struct timespec")
    if C.clock_getres(C.CLOCK_MONOTONIC_COARSE, probe_ts) == 0 then
        -- Now, it usually has a 1ms resolution on modern x86_64 systems,
        -- but it only provides a 10ms resolution on all my armv7 devices :/.
        if probe_ts.tv_sec == 0 and probe_ts.tv_nsec <= 1000000 then
            PREFERRED_MONOTONIC_CLOCKID = C.CLOCK_MONOTONIC_COARSE
        end
    end
    logger.dbg("fts: Preferred MONOTONIC clock source is", PREFERRED_MONOTONIC_CLOCKID == C.CLOCK_MONOTONIC_COARSE and "CLOCK_MONOTONIC_COARSE" or "CLOCK_MONOTONIC")
    if C.clock_getres(C.CLOCK_REALTIME_COARSE, probe_ts) == 0 then
        if probe_ts.tv_sec == 0 and probe_ts.tv_nsec <= 1000000 then
            PREFERRED_REALTIME_CLOCKID = C.CLOCK_REALTIME_COARSE
        end
    end
    logger.dbg("fts: Preferred REALTIME clock source is", PREFERRED_REALTIME_CLOCKID == C.CLOCK_REALTIME_COARSE and "CLOCK_REALTIME_COARSE" or "CLOCK_REALTIME")

    if C.clock_getres(C.CLOCK_BOOTTIME, probe_ts) == 0 then
        HAVE_BOOTTIME = true
    end
    logger.dbg("fts: BOOTTIME clock source is", HAVE_BOOTTIME and "supported" or "NOT supported")

    probe_ts = nil --luacheck: ignore
end

--[[--
Fixed point time. Maps to a POSIX struct timeval (<sys/time.h>).
]]
local time = {}

--[[--
Returns an fts time based on the current wall clock time.
(e.g., gettimeofday / clock_gettime(CLOCK_REALTIME).

This is a simple wrapper around util.gettime() to get all the niceties of a time.
If you don't need sub-second precision, prefer os.time().
Which means that, yes, this is a fancier POSIX Epoch ;).

@usage
    local time = require("ui/time")
    local fts_start = time.realtime()
    -- Do some stuff.
    -- You can add and substract fts times
    local fts_duration = time.realtime() - fts_start

@treturn fts fixed point time
]]
function time.realtime()
    C.clock_gettime(C.CLOCK_REALTIME, timespec)
    -- TIMESPEC_TO_FTS
    return tonumber(timespec.tv_sec) * S2FTS + math.floor(tonumber(timespec.tv_nsec) * NS2FTS)
end

--[[--
Returns an fts time based on the current value from the system's MONOTONIC clock source.
(e.g., clock_gettime(CLOCK_MONOTONIC).)

POSIX guarantees that this clock source will *never* go backwards (but it *may* return the same value multiple times).
On Linux, this will not account for time spent with the device in suspend (unlike CLOCK_BOOTTIME).

@treturn Tfts fixed point time
]]
function time.monotonic()
    C.clock_gettime(C.CLOCK_MONOTONIC, timespec)
    -- TIMESPEC_TO_FTS
    return tonumber(timespec.tv_sec) * S2FTS + math.floor(tonumber(timespec.tv_nsec) * NS2FTS)
end

--- Ditto, but w/ CLOCK_MONOTONIC_COARSE if it's available and has a 1ms resolution or better (uses CLOCK_MONOTONIC otherwise).
function time.monotonic_coarse()
    C.clock_gettime(PREFERRED_MONOTONIC_CLOCKID, timespec)
    -- TIMESPEC_TO_FTS
    return tonumber(timespec.tv_sec) * S2FTS + math.floor(tonumber(timespec.tv_nsec) * NS2FTS)
end


-- Ditto, but w/ CLOCK_REALTIME_COARSE if it's available and has a 1ms resolution or better (uses CLOCK_REALTIME otherwise).
function time.realtime_coarse()
    C.clock_gettime(PREFERRED_REALTIME_CLOCKID, timespec)
    -- TIMESPEC_TO_FTS
    return tonumber(timespec.tv_sec) * S2FTS + math.floor(tonumber(timespec.tv_nsec) * NS2FTS)
    end

--- Since CLOCK_BOOTIME may not be supported, we offer a few aliases with automatic fallbacks to MONOTONIC or REALTIME
if HAVE_BOOTTIME then
    --- Ditto, but w/ CLOCK_BOOTTIME (will return an fts time set to 0, 0 if the clock source is unsupported, as it's 2.6.39+)
    --- Only use it if you *know* it's going to be supported, otherwise, prefer the four following aliases.
    function time.boottime()
        C.clock_gettime(C.CLOCK_BOOTTIME, timespec)
        -- TIMESPEC_TO_FTS
    return tonumber(timespec.tv_sec) * S2FTS + math.floor(tonumber(timespec.tv_nsec) * NS2FTS)
    end

    time.boottime_or_monotonic = time.boottime
    time.boottime_or_monotonic_coarse = time.boottime
    time.boottime_or_realtime = time.boottime
    time.boottime_or_realtime_coarse = time.boottime
else
    function time.boottime()
        logger.warn("fts: Attemped to call boottime on a platform where it's unsupported!")
        return 0
    end

    time.boottime_or_monotonic = time.monotonic
    time.boottime_or_monotonic_coarse = time.monotonic_coarse
    time.boottime_or_realtime = time.realtime
    time.boottime_or_realtime_coarse = time.realtime_coarse
end

--[[-- Alias for `monotonic_coarse`.

The assumption being anything that requires accurate timestamps expects a monotonic clock source.
This is certainly true for KOReader's UI scheduling.
]]
time.now = time.monotonic_coarse

--- Converts an fts time to a Lua (decimal) number (sec.usecs) (accurate to the ms, rounded to 4 decimal places)
function time.tonumber(time_fts)
    -- Round to 4 decimal places
    return math.floor(time.toS(time_fts) * 10000 + 0.5) / 10000
end

-- Converts an fts to seconds (with comma)
function time.toS(time_fts)
    return time_fts * FTS2S
end

--[[-- Converts a fts to a Lua (int) number (resolution: 1ms).

(Mainly useful when computing a time lapse for benchmarking purposes).
]]
function time.toMS(time_fts)
    return math.floor(time_fts * FTS2MS + 0.5)
end

--- Converts an fts to a Lua (int) number (resolution: 1µs)
function time.toUS(time_fts)

    return math.floor(time_fts * FTS2US + 0.5)
end

--- Converts a Lua number (sec.usecs) to an fts time
function time.fromnumber(seconds)
    return math.floor(seconds * S2FTS)
end

--[[-- Compare a past *MONOTONIC* fts time to *now*, returning the elapsed time between the two. (sec.usecs variant)

Returns a Lua (decimal) number (sec.usecs) (accurate to the ms, rounded to 4 decimal places) (i.e., time.tonumber())
]]
function time.getDuration(start_time)
   return time.tonumber(time.now() - start_time)
end

--[[-- Compare a past *MONOTONIC* fts time object to *now*, returning the elapsed time between the two. (ms variant)

Returns a Lua (int) number (resolution: 1ms)
]]
function time.getDurationMs(start_time)
   return time.toMS(time.now() - start_time)
end

--[[-- Compare a past *MONOTONIC* fts time object to *now*, returning the elapsed time between the two. (µs variant)

Returns a Lua (int) number (resolution: 1µs)
]]
function time.getDurationUs(start_time)
   return time.toUS(time.now() - start_time)
end

--- Ditto for one set to math.huge
time.huge = math.huge

function time.tv(tv)
    return tv.sec * S2FTS + tv.usec * US2FTS
end

function time.splitsus(time_fts)
    if not time_fts then return nil, nil end
    local sec = math.floor(time_fts * FTS2S)
    local usec = math.floor(time_fts - sec * S2FTS) * FTS2US
    return sec, usec
end

function time.s(seconds)
    return math.floor(seconds * S2FTS)
end

function time.ms(usec)
    return math.floor(usec * MS2FTS)
end

function time.us(usec)
    return math.floor(usec * US2FTS)
end

--not needed any more
--[[
function time.toTv(time)
    local TimeVal = require("ui/timeval")
    if not time then return TimeVal.zero end
    local sec, usec = time.splitsus(time)
    return TimeVal:new{ sec = sec, usec = usec }
en]]

-- for debugging
function time.format_time(time_fts)
    return string.format("%.06f", time_fts * FTS2S)
end

return time
