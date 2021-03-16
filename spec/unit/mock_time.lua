require("commonrequire")
local TimeVal = require("ui/timeval")
local ffi = require("ffi")
local dummy = require("ffi/posix_h")
local logger = require("logger")
local util = require("ffi/util")

local C = ffi.C

local MockTime = {
    original_os_time = os.time,
    original_util_time = nil,
    original_tv_now = nil,
    original_tv_monotonic = nil,
    monotonic = 0,
    realtime = 0,
}

function MockTime:install()
    assert(self ~= nil)
    if self.original_util_time == nil then
        self.original_util_time = util.gettime
        assert(self.original_util_time ~= nil)
    end
    if original_tv_now == nil then
        original_tv_now = TimeVal.now
        assert(original_tv_now ~= nil)
    end
    if original_tv_monotonic == nil then
        original_tv_monotonic = TimeVal.monotonic
        assert(original_tv_monotonic ~= nil)
    end

    -- Store both REALTIME & MONOTONIC clocks
    self.realtime = os.time()
    local timespec = ffi.new("struct timespec")
    C.clock_gettime(C.CLOCK_MONOTONIC, timespec)
    self.monotonic = tonumber(timespec.tv_sec)

    os.time = function() --luacheck: ignore
        logger.dbg("MockTime:os.time: ", self.realtime)
        return self.realtime
    end
    util.gettime = function()
        logger.dbg("MockTime:util.gettime: ", self.realtime)
        return self.realtime, 0
    end
    TimeVal.now = function()
        logger.dbg("MockTime:TimeVal.now: ", self.realtime)
        return TimeVal:new{ sec = self.realtime }
    end
    TimeVal.monotonic = function()
        logger.dbg("MockTime:TimeVal.monotonic: ", self.monotonic)
        return TimeVal:new{ sec = self.monotonic }
    end
end

function MockTime:uninstall()
    assert(self ~= nil)
    os.time = self.original_os_time --luacheck: ignore
    if self.original_util_time ~= nil then
        util.gettime = self.original_util_time
    end
    if self.original_tv_now ~= nil then
        TimeVal.now = self.original_tv_now
    end
    if self.original_tv_monotonic ~= nil then
        TimeVal.monotonic = self.original_tv_monotonic
    end
end

function MockTime:set_realtime(value)
    assert(self ~= nil)
    if type(value) ~= "number" then
        return false
    end
    self.realtime = math.floor(value)
    logger.dbg("MockTime:set realtime ", self.realtime)
    return true
end

function MockTime:increase_realtime(value)
    assert(self ~= nil)
    if type(value) ~= "number" then
        return false
    end
    self.realtime = math.floor(self.realtime + value)
    logger.dbg("MockTime:increase realtime ", self.realtime)
    return true
end

function MockTime:set_monotonic(value)
    assert(self ~= nil)
    if type(value) ~= "number" then
        return false
    end
    self.monotonic = math.floor(value)
    logger.dbg("MockTime:set monotonic ", self.monotonic)
    return true
end

function MockTime:increase_monotonic(value)
    assert(self ~= nil)
    if type(value) ~= "number" then
        return false
    end
    self.monotonic = math.floor(self.monotonic + value)
    logger.dbg("MockTime:increase monotonic ", self.monotonic)
    return true
end

return MockTime
