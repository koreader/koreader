--[[--
A simple module to module to compare and do arithmetic with time values.

@usage
    local TimeVal = require("ui/timeval")

    local tv_start = TimeVal:now()
    -- Do some stuff.
    -- You can add and subtract `TimeVal` objects.
    local tv_duration = TimeVal:now() - tv_start
    -- And convert that object to various more human-readable formats, e.g.,
    print(string.format("Stuff took %.3fms", tv_duration:tomsecs()))
]]

local ffi = require("ffi")
require("ffi/posix_h")
local logger = require("logger")
local util = require("ffi/util")

local C = ffi.C

-- We prefer CLOCK_MONOTONIC_COARSE if it's available and has a decent resolution,
-- as we generally don't need nano/micro second precision,
-- and it can be more than twice as fast as CLOCK_MONOTONIC/CLOCK_REALTIME/gettimeofday...
local PREFERRED_MONOTONIC_CLOCKID = C.CLOCK_MONOTONIC
-- Ditto for REALTIME (for :realtime_coarse only, :realtime uses gettimeofday ;)).
local PREFERRED_REALTIME_CLOCKID = C.CLOCK_REALTIME
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
    logger.dbg("TimeVal: Preferred MONOTONIC clock source is", PREFERRED_MONOTONIC_CLOCKID == C.CLOCK_MONOTONIC_COARSE and "CLOCK_MONOTONIC_COARSE" or "CLOCK_MONOTONIC")
    if C.clock_getres(C.CLOCK_REALTIME_COARSE, probe_ts) == 0 then
        if probe_ts.tv_sec == 0 and probe_ts.tv_nsec <= 1000000 then
            PREFERRED_REALTIME_CLOCKID = C.CLOCK_REALTIME_COARSE
        end
    end
    logger.dbg("TimeVal: Preferred REALTIME clock source is", PREFERRED_REALTIME_CLOCKID == C.CLOCK_REALTIME_COARSE and "CLOCK_REALTIME_COARSE" or "CLOCK_REALTIME")
    probe_ts = nil --luacheck: ignore
end

--[[--
TimeVal object. Maps to a POSIX struct timeval (<sys/time.h>).

@table TimeVal
@int sec floored number of seconds
@int usec number of microseconds past that second.
]]
local TimeVal = {
    sec = 0,
    usec = 0,
}

--[[--
Creates a new TimeVal object.

@usage
    local timev = TimeVal:new{
        sec = 10,
        usec = 10000,
    }

@treturn TimeVal
]]
function TimeVal:new(from_o)
    local o = from_o or {}
    if o.sec == nil then
        o.sec = 0
    end
    if o.usec == nil then
        o.usec = 0
    elseif o.usec > 1000000 then
        o.sec = o.sec + math.floor(o.usec / 1000000)
        o.usec = o.usec % 1000000
    end
    setmetatable(o, self)
    self.__index = self
    return o
end

-- Based on <bsd/sys/time.h>
function TimeVal:__lt(time_b)
    if self.sec == time_b.sec then
        return self.usec < time_b.usec
    else
        return self.sec < time_b.sec
    end
end

function TimeVal:__le(time_b)
    if self.sec == time_b.sec then
        return self.usec <= time_b.usec
    else
        return self.sec <= time_b.sec
    end
end

function TimeVal:__eq(time_b)
    if self.sec == time_b.sec then
        return self.usec == time_b.usec
    else
        return false
    end
end

-- If sec is negative, time went backwards!
function TimeVal:__sub(time_b)
    local diff = TimeVal:new{ sec = 0, usec = 0 }

    diff.sec = self.sec - time_b.sec
    diff.usec = self.usec - time_b.usec

    if diff.usec < 0 then
        diff.sec = diff.sec - 1
        diff.usec = diff.usec + 1000000
    end

    return diff
end

function TimeVal:__add(time_b)
    local sum = TimeVal:new{ sec = 0, usec = 0 }

    sum.sec = self.sec + time_b.sec
    sum.usec = self.usec + time_b.usec

    if sum.usec >= 1000000 then
        sum.sec = sum.sec + 1
        sum.usec = sum.usec - 1000000
    end

    return sum
end

--[[--
Creates a new TimeVal object based on the current wall clock time.
(e.g., gettimeofday / clock_gettime(CLOCK_REALTIME).

This is a simple wrapper around util.gettime() to get all the niceties of a TimeVal object.
If you don't need sub-second precision, prefer os.time().
Which means that, yes, this is a fancier POSIX Epoch ;).

@usage
    local TimeVal = require("ui/timeval")
    local tv_start = TimeVal:realtime()
    -- Do some stuff.
    -- You can add and substract `TimeVal` objects.
    local tv_duration = TimeVal:realtime() - tv_start

@treturn TimeVal
]]
function TimeVal:realtime()
    local sec, usec = util.gettime()
    return TimeVal:new{ sec = sec, usec = usec }
end

--[[--
Creates a new TimeVal object based on the current value from the system's MONOTONIC clock source.
(e.g., clock_gettime(CLOCK_MONOTONIC).)

POSIX guarantees that this clock source will *never* go backwards (but it *may* return the same value multiple times).
On Linux, this will not account for time spent with the device in suspend (unlike CLOCK_BOOTTIME).

@treturn TimeVal
]]
function TimeVal:monotonic()
    local timespec = ffi.new("struct timespec")
    C.clock_gettime(C.CLOCK_MONOTONIC, timespec)

    -- TIMESPEC_TO_TIMEVAL
    return TimeVal:new{ sec = tonumber(timespec.tv_sec), usec = math.floor(tonumber(timespec.tv_nsec / 1000)) }
end

--- Ditto, but w/ CLOCK_MONOTONIC_COARSE if it's available and has a 1ms resolution or better (uses CLOCK_MONOTONIC otherwise).
function TimeVal:monotonic_coarse()
    local timespec = ffi.new("struct timespec")
    C.clock_gettime(PREFERRED_MONOTONIC_CLOCKID, timespec)

    -- TIMESPEC_TO_TIMEVAL
    return TimeVal:new{ sec = tonumber(timespec.tv_sec), usec = math.floor(tonumber(timespec.tv_nsec / 1000)) }
end

--- Ditto, but w/ CLOCK_REALTIME_COARSE if it's available and has a 1ms resolution or better (uses CLOCK_REALTIME otherwise).
function TimeVal:realtime_coarse()
    local timespec = ffi.new("struct timespec")
    C.clock_gettime(PREFERRED_REALTIME_CLOCKID, timespec)

    -- TIMESPEC_TO_TIMEVAL
    return TimeVal:new{ sec = tonumber(timespec.tv_sec), usec = math.floor(tonumber(timespec.tv_nsec / 1000)) }
end

--- Ditto, but w/ CLOCK_BOOTTIME (will return a TimeVal set to 0, 0 if the clock source is unsupported, as it's 2.6.39+)
function TimeVal:boottime()
    local timespec = ffi.new("struct timespec")
    C.clock_gettime(C.CLOCK_BOOTTIME, timespec)

    -- TIMESPEC_TO_TIMEVAL
    return TimeVal:new{ sec = tonumber(timespec.tv_sec), usec = math.floor(tonumber(timespec.tv_nsec / 1000)) }
end

--[[-- Alias for `monotonic_coarse`.

The assumption being anything that requires accurate timestamps expects a monotonic clock source.
This is certainly true for KOReader's UI scheduling.
]]
TimeVal.now = TimeVal.monotonic_coarse

--- Converts a TimeVal object to a Lua (decimal) number (sec.usecs) (accurate to the ms, rounded to 4 decimal places)
function TimeVal:tonumber()
    -- Round to 4 decimal places
    return math.floor((self.sec + self.usec / 1000000) * 10000) / 10000
end

--- Converts a TimeVal object to a Lua (int) number (resolution: 1µs)
function TimeVal:tousecs()
    return math.floor(self.sec * 1000000 + self.usec + 0.5)
end

--[[-- Converts a TimeVal object to a Lua (int) number (resolution: 1ms).

(Mainly useful when computing a time lapse for benchmarking purposes).
]]
function TimeVal:tomsecs()
    return self:tousecs() / 1000
end

--- Converts a Lua (decimal) number (sec.usecs) to a TimeVal object
function TimeVal:fromnumber(seconds)
    local sec = math.floor(seconds)
    local usec = math.floor((seconds - sec) * 1000000 + 0.5)
    return TimeVal:new{ sec = sec, usec = usec }
end

--[[-- Compare a past *MONOTONIC* TimeVal object to *now*, returning the elapsed time between the two. (sec.usecs variant)

Returns a Lua (decimal) number (sec.usecs) (accurate to the ms, rounded to 4 decimal places) (i.e., :tonumber())
]]
function TimeVal:getDuration(start_tv)
   return (TimeVal:now() - start_tv):tonumber()
end

--[[-- Compare a past *MONOTONIC* TimeVal object to *now*, returning the elapsed time between the two. (µs variant)

Returns a Lua (int) number (resolution: 1µs) (i.e., :tousecs())
]]
function TimeVal:getDurationUs(start_tv)
   return (TimeVal:now() - start_tv):tousecs()
end

--[[-- Compare a past *MONOTONIC* TimeVal object to *now*, returning the elapsed time between the two. (ms variant)

Returns a Lua (int) number (resolution: 1ms) (i.e., :tomsecs())
]]
function TimeVal:getDurationMs(start_tv)
   return (TimeVal:now() - start_tv):tomsecs()
end

--- Checks if a TimeVal object is positive
function TimeVal:isPositive()
    return self.sec >= 0
end

--- Checks if a TimeVal object is zero
function TimeVal:isZero()
    return self.sec == 0 and self.usec == 0
end

--- We often need a const TimeVal set to zero...
--- LuaJIT doesn't actually support const values (Lua 5.4+): Do *NOT* modify it.
TimeVal.zero = TimeVal:new{ sec = 0, usec = 0 }

--- Ditto for one set to math.huge
TimeVal.huge = TimeVal:new{ sec = math.huge, usec = 0 }

return TimeVal
