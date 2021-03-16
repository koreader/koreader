--[[--
A simple module to module to compare and do arithmetic with time values.

@usage
    local TimeVal = require("ui/timeval")

    local tv_start = TimeVal:now()
    -- Do some stuff.
    -- You can add and subtract `TimeVal` objects.
    local tv_duration = TimeVal:now() - tv_start
    -- If you need more precision (like 2.5 s),
    -- you can add the milliseconds to the seconds.
    local tv_duration_seconds_float = tv_duration.sec + tv_duration.usec/1000000
]]

local ffi = require("ffi")
local dummy = require("ffi/posix_h")
local util = require("ffi/util")

local C = ffi.C

--[[--
TimeVal object.

@table TimeVal
@int sec floored number of seconds
@int usec remaining number of milliseconds
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
        o.sec = o.sec + math.floor(o.usec/1000000)
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
    local diff = TimeVal:new{}

    diff.sec = self.sec - time_b.sec
    diff.usec = self.usec - time_b.usec

    if diff.usec < 0 then
        diff.sec = diff.sec - 1
        diff.usec = diff.usec + 1000000
    end

    return diff
end

function TimeVal:__add(time_b)
    local sum = TimeVal:new{}

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

@usage
    local TimeVal = require("ui/timeval")
    local tv_start = TimeVal:now()
    -- Do some stuff.
    -- You can add and substract `TimeVal` objects.
    local tv_duration = TimeVal:now() - tv_start

@treturn TimeVal
]]
function TimeVal:realtime()
    local sec, usec = util.gettime()
    return TimeVal:new{sec = sec, usec = usec}
end

--[[--
Creates a new TimeVal object based on the current value from the system's MONOTONIC clock source.
(e.g., clock_gettime(CLOCK_MONOTONIC).

@treturn TimeVal
]]
function TimeVal:monotonic()
    local timespec = ffi.new("struct timespec")
    C.clock_gettime(C.CLOCK_MONOTONIC, timespec)

    -- TIMESPEC_TO_TIMEVAL
    return TimeVal:new{sec = tonumber(timespec.tv_sec), usec = tonumber(timespec.tv_nsec / 1000)}
end

-- Assume anything that requires timestamps expects a monotonic clock source
-- (e.g., subsequent calls *may* return identical values, but it will *never* go backward).
TimeVal.now = TimeVal.monotonic

-- Converts a TimeVal object to a Lua (float) number (sec.usecs)
function TimeVal:tonumber()
    return tonumber(self.sec + self.usec/1000000)
end

-- Converts a TimeVal object to a Lua (int) number (usecs)
function TimeVal:tousecs()
    return tonumber(self.sec * 1000000 + self.usec)
end

-- Converts a Lua (float) number (sec.usecs) to a TimeVal object
function TimeVal:fromnumber(seconds)
    local sec = math.floor(seconds)
    local usec = (seconds - sec) * 1000000
    return TimeVal:new{sec = sec, usec = usec}
end

return TimeVal
