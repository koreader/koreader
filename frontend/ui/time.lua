--[[--
A runtime optimized module to compare and do simple arithmetic with fixed point time values (which are called fts in here).

Also implements functions to retrieve time from various system clocks (monotonic, monotonic_coarse, realtime, realtime_coarse, boottime ...).

**Encode:**

Don't store a numerical constant in an fts encoded time. Use the functions provided here!

To convert real world units to an fts, you can use the following functions: time.s(seconds), time.ms(milliseconds), time.us(microseconds).

You can calculate an fts encoded time of 3 s with `time.s(3)`.

Special values: `0` can be used for a zero time and `time.huge` can be used for the longest possible time.

Beware of float encoding precision, though. For instance, take 2.1s: 2.1 cannot be encoded with full precision, so time.s(2.1) would be slightly inaccurate.
(For small values (under 10 secs) the error will be ±1µs, for values below a minute the error will be below ±2µs, for values below an hour the error will be ±100µs.)

When full precision is necessary, use `time.s(2) + time.ms(100)` or `time.s(2) + time.us(100000)` instead.

(For more information about floating-point-representation see: https://stackoverflow.com/questions/3448777/how-to-represent-0-1-in-floating-point-arithmetic-and-decimal)

**Decode:**

You can get the number of seconds in an fts encoded time with `time.to_s(time_fts)`.

You can get the number of milliseconds in an fts encoded time with `time.to_ms(time_fts)`.

You can get the number of microseconds in an fts encoded time with `time.to_us(time_fts)`.

Please be aware, that `time.to_number` is the same as a `time.to_s` with a precision of four decimal places.

**Supported calculations:**

You can add and subtract all fts encoded times, without any problems.

You can multiply or divide fts encoded times by numerical constants. So if you need the half of a time, `time_fts/2` is correct.

A division of two fts encoded times would give you a number. (e.g., `time.s(2.5)/time.s(0.5)` equals `5`).

The functions `math.abs()`, `math.min()`, `math.max()` and `math.huge` will work as expected.

Comparisons (`>`, `>=`, `==`, `<`, `<=` and `~=`) of two fts encoded times work as expected.

If you want a duration form a given time_fts to *now*, `time.since(time_fts)` as a shortcut (or simply use `fts.now - time_fts`) will return an fts encoded time. If you need milliseconds use `time.to_ms(time.since(time_fts))`.

**Unsupported calculations:**

Don't add a numerical constant to an fts time (in the best case, the numerical constant is interpreted as µs).

Don't multiply two fts_encoded times (the position of the comma is wrong).

But please be aware that _all other not explicitly supported_ math on fts encoded times (`math.xxx()`) won't work as expected. (If you really, really need that, you have to shift the position of the comma yourself!)

**Background:**
Numbers in Lua are double float which have a mantissa (precision) of 53 bit (plus sign + exponent)
We won't use the exponent here.

So we can store 2^53 = 9.0072E15 different values. If we use the lower 6 digits for µs, we can store
up to 9.0072E9 seconds.

A year has 365.25*24*3600 = 3.15576E7 s, so we can store up to 285 years (9.0072E9/3.15576E7) with µs precision.

The module has been tested with the fixed point comma at 10^6 (other values might work, but are not really tested).

**Recommendations:**
If the name of a variable implies a time (now, when, until, xxxdeadline, xxxtime, getElapsedTimeSinceBoot, lastxxxtimexxx, ...) we assume this value to be a time (fts encoded).

Other objects which are times (like `last_tap`, `tap_interval_override`, ...) shall be renamed to something like `last_tap_time` (so to make it clear that they are fts encoded).

All other time variables (a handful) get the appropriate suffix `_ms`, `_us`, `_s` (`_m`, `_h`, `_d`) denoting their status as plain Lua numbers and their resolution.

@module time

@usage
    local time = require("ui/time")

    local start_time = time.now()
    -- Do some stuff.
    -- You can add and subtract `fts times` objects
    local duration = time.now() - start_time
    -- and convert that object to various more human-readable formats, e.g.,
    print(string.format("Stuff took %.3fms", time.to_ms(duration)))

    local offset = time.s(100)
    print(string.format("Stuff plus 100s took %.3fms", time.to_ms(duration + offset)))
]]

local ffi = require("ffi")
require("ffi/posix_h")
local logger = require("logger")

local C = ffi.C

-- An FTS_PRECISION of 1e6 will give us a µs precision.
local FTS_PRECISION = 1e6

local S2FTS = FTS_PRECISION
local MS2FTS = FTS_PRECISION / 1e3
local US2FTS = FTS_PRECISION / 1e6
local NS2FTS = FTS_PRECISION / 1e9

local FTS2S = 1 / S2FTS
local FTS2MS = 1 / MS2FTS
local FTS2US = 1 / US2FTS

-- Fixed point time
local time = {}

--- Sometimes we need a very large time.
time.huge = math.huge

--- Creates a time (fts) from a number in seconds.
function time.s(seconds)
    return math.floor(seconds * S2FTS)
end

--- Creates a time (fts) from a number in milliseconds.
function time.ms(msec)
    return math.floor(msec * MS2FTS)
end

--- Creates a time (fts) from a number in microseconds.
function time.us(usec)
    return math.floor(usec * US2FTS)
end

--- Creates a time (fts) from a structure similar to timeval.
function time.timeval(tv)
    return tv.sec * S2FTS + tv.usec * US2FTS
end

--- Converts an fts time to a Lua (decimal) number (sec.usecs) (accurate to the ms, rounded to 4 decimal places)
function time.to_number(time_fts)
    -- Round to 4 decimal places
    return math.floor(time.to_s(time_fts) * 10000 + 0.5) * (1/10000)
end

--- Converts an fts to a Lua (int) number (resolution: 1µs)
function time.to_s(time_fts)
    -- Time in seconds with µs precision (without decimal places)
    return time_fts * FTS2S
end

--[[-- Converts a fts to a Lua (int) number (resolution: 1ms, rounded).

(Mainly useful when computing a time lapse for benchmarking purposes).
]]
function time.to_ms(time_fts)
    -- Time in milliseconds ms (without decimal places)
    return math.floor(time_fts * FTS2MS + 0.5)
end

--- Converts an fts to a Lua (int) number (resolution: 1µs, rounded)
function time.to_us(time_fts)
    -- Time in microseconds µs (without decimal places)
    return math.floor(time_fts * FTS2US + 0.5)
end

--[[-- Compare a past *MONOTONIC* fts time to *now*, returning the elapsed time between the two. (sec.usecs variant)

Returns a Lua (decimal) number (sec.usecs, with decimal places) (accurate to the µs).
]]
function time.since(start_time)
    -- Time difference
   return time.now() - start_time
end

--- Splits an fts to seconds and microseconds.
-- If argument is nil, returns nil,nil.
function time.split_s_us(time_fts)
    if not time_fts then return nil, nil end
    local sec = math.floor(time_fts * FTS2S)
    local usec = math.floor((time_fts - sec * S2FTS) * FTS2US)
    -- Seconds and µs
    return sec, usec
end

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
Returns an fts time based on the current wall clock time.
(e.g., gettimeofday / clock_gettime(CLOCK_REALTIME).

This is a simple wrapper around clock_gettime(CLOCK_REALTIME) to get all the niceties of a time.
If you don't need sub-second precision, prefer os.time().
Which means that, yes, this is a fancier POSIX Epoch ;).

@usage
    local time = require("ui/time")
    local fts_start = time.realtime()
    -- Do some stuff.
    -- You can add and subtract fts times
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

@treturn fts fixed point time
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
        logger.warn("fts: Attempted to call boottime on a platform where it's unsupported!")
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

--- Converts an fts time to a string (seconds with 6 decimal places)
function time.format_time(time_fts)
    return string.format("%.06f", time_fts * FTS2S)
end

return time
