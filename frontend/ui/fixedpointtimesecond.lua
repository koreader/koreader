--[[--
A simple module to module to compare and do arithmetic with time values.

@usage
    local fts = require("ui/fixedpointtimesecond")

    local start_fts = fps.now_fts()
    -- Do some stuff.
    -- You can add and subtract `TimeVal` objects.
    local duration_fts = fts.now_fts() - start.fts
    -- And convert that object to various more human-readable formats, e.g.,
    print(string.format("Stuff took %.3fms", fts.tomSecs(duration_fts)))
]]

local ffi = require("ffi")
require("ffi/posix_h")
local logger = require("logger")
local util = require("ffi/util")

local C = ffi.C

-- Numbers in lua are double float which have a mantissa (precision) of 53 bit (plus sign + exponent)
-- We won't use the exponent here.
-- So we can store 2^53 = 9.0072*10^15 different values. If we use the lower 6 digits for µs, we can store
-- up to 9.0072*10^9 seconds.
-- A year has 365.25*24*3600 = 3.15576*10^7 s, so we can store up to 285 years (9.0072e9/3.15576r7) with µs precision.

-- A TV_PRECISION of 1e6 will give us a µs precision.
local TV_PRECISION = 1e6


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
TimeVal object. Maps to a POSIX struct timeval (<sys/time.h>).
]]
local fts = {
    precision = TV_PRECISION,
}

--[[--
Creates a new TimeVal object based on the current wall clock time.
(e.g., gettimeofday / clock_gettime(CLOCK_REALTIME).

This is a simple wrapper around util.gettime() to get all the niceties of a TimeVal object.
If you don't need sub-second precision, prefer os.time().
Which means that, yes, this is a fancier POSIX Epoch ;).

@usage
    local TimeVal = require("ui/timeval")
    local tv_start = fts:realtime()
    -- Do some stuff.
    -- You can add and substract `TimeVal` objects.
    local tv_duration = fts:realtime() - tv_start

@treturn TimeVal
]]
function fts:realtime()
    local sec, usec = util.gettime()
    return sec * fts.precision + usec
end

--[[--
Creates a new TimeVal object based on the current value from the system's MONOTONIC clock source.
(e.g., clock_gettime(CLOCK_MONOTONIC).)

POSIX guarantees that this clock source will *never* go backwards (but it *may* return the same value multiple times).
On Linux, this will not account for time spent with the device in suspend (unlike CLOCK_BOOTTIME).

@treturn TimeVal
]]
function fts:monotonic()
    local timespec = ffi.new("struct timespec")
    C.clock_gettime(C.CLOCK_MONOTONIC, timespec)

    -- TIMESPEC_TO_FTS
    return tonumber(timespec.tv_sec) * fts.precision +  math.floor(tonumber(timespec.tv_nsec / 1000))

end

--- Ditto, but w/ CLOCK_MONOTONIC_COARSE if it's available and has a 1ms resolution or better (uses CLOCK_MONOTONIC otherwise).
function fts:monotonic_coarse()
    local timespec = ffi.new("struct timespec")
    C.clock_gettime(PREFERRED_MONOTONIC_CLOCKID, timespec)

    -- TIMESPEC_TO_FTS
        return tonumber(timespec.tv_sec) * fts.precision +  math.floor(tonumber(timespec.tv_nsec / 1000))

end

-- Ditto, but w/ CLOCK_REALTIME_COARSE if it's available and has a 1ms resolution or better (uses CLOCK_REALTIME otherwise).
function fts:realtime_coarse()
    local timespec = ffi.new("struct timespec")
    C.clock_gettime(PREFERRED_REALTIME_CLOCKID, timespec)

    -- TIMESPEC_TO_FTS
    return tonumber(timespec.tv_sec) * TV_PRECISION +  math.floor(tonumber(timespec.tv_nsec / 1000))
    end

--- Since CLOCK_BOOTIME may not be supported, we offer a few aliases with automatic fallbacks to MONOTONIC or REALTIME
if HAVE_BOOTTIME then
    --- Ditto, but w/ CLOCK_BOOTTIME (will return a TimeVal set to 0, 0 if the clock source is unsupported, as it's 2.6.39+)
    --- Only use it if you *know* it's going to be supported, otherwise, prefer the four following aliases.
    function fts:boottime()
        local timespec = ffi.new("struct timespec")
        C.clock_gettime(C.CLOCK_BOOTTIME, timespec)

        -- TIMESPEC_TO_TIMEVAL
        return fts:new{ sec = tonumber(timespec.tv_sec), usec = math.floor(tonumber(timespec.tv_nsec / 1000)) }
    end

    fts.boottime_or_monotonic = fts.boottime
    fts.boottime_or_monotonic_coarse = fts.boottime
    fts.boottime_or_realtime = fts.boottime
    fts.boottime_or_realtime_coarse = fts.boottime
else
    function fts.boottime()
        logger.warn("fts: Attemped to call boottime on a platform where it's unsupported!")

        return 0
    end

    fts.boottime_or_monotonic = fts.monotonic
    fts.boottime_or_monotonic_coarse = fts.monotonic_coarse
    fts.boottime_or_realtime = fts.realtime
    fts.boottime_or_realtime_coarse = fts.realtime_coarse
end

--[[-- Alias for `monotonic_coarse`.

The assumption being anything that requires accurate timestamps expects a monotonic clock source.
This is certainly true for KOReader's UI scheduling.
]]
fts.now = fts.monotonic_coarse

--- Converts a TimeVal object to a Lua (decimal) number (sec.usecs) (accurate to the ms, rounded to 4 decimal places)
function fts.tonumber(time_fts)
    -- Round to 4 decimal places
    return math.floor(fts.toSec(time_fts) * 10000) / 10000
end

-- Converts an fts to seconds (with comma)
function fts.toSec(time_fts)
    return time_fts / fts.precision
end

--- Converts an fts to a Lua (int) number (resolution: 1µs)
function fts:touSecs(time_fts)
    return math.floor(fts.toSec(time_fts) * 1e6 + 0.5)
end

--[[-- Converts a fts to a Lua (int) number (resolution: 1ms).

(Mainly useful when computing a time lapse for benchmarking purposes).
]]
function fts.tomSecs(time_fts)
    return math.floor(fts.toSecs(time_fts) * 1e3 + 0.5)
end

--- Converts a Lua number (sec.usecs) to an fts
function fts.fromnumber(seconds)
    return math.floor(seconds * fts.precision)
end

--[[-- Compare a past *MONOTONIC* TimeVal object to *now*, returning the elapsed time between the two. (sec.usecs variant)

Returns a Lua (decimal) number (sec.usecs) (accurate to the ms, rounded to 4 decimal places) (i.e., :tonumber())
]]
function fts.getDuration(start_fts)
   return fts.tonumber(fts.now() - start_fts)
end

--[[-- Compare a past *MONOTONIC* TimeVal object to *now*, returning the elapsed time between the two. (µs variant)

Returns a Lua (int) number (resolution: 1µs)
]]
function fts.getDurationUs(start_fts)
   return fts.touSecs(fts.tonumber(start_fts))
end

--[[-- Compare a past *MONOTONIC* TimeVal object to *now*, returning the elapsed time between the two. (ms variant)

Returns a Lua (int) number (resolution: 1ms)
]]
function fts.getDurationMs(start_fts)
   return fts.tomSecs(fts:now() - start_fts)
end

--- Ditto for one set to math.huge
fts.huge = math.huge

function fts.fromTv(tv)
    return tv.sec * fts.precision + tv.usec
end

function fts.splitsus(time_fts)
    if not time_fts then return 0, 0 end
    local sec = math.floor(time_fts / fts.precision)
    local usec = math.floor(time_fts - sec * fts.precision)
    return sec, usec
end

function fts.toTv(time_fts)
    local TimeVal = require("ui/timeval")
    if not time_fts then return TimeVal.zero end
    local sec, usec = fts.splitsus(time_fts)
    return TimeVal:new{ sec = sec, usec = usec }
end

function fts.fromSec(seconds)
    return math.floor(seconds * fts.precision)
end

-- for debugging
function fts.format_fts(time_fts)
    return string.format("%.06f", time_fts / fts.precision)
end


return fts
