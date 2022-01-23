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
    original_tv_realtime = nil,
    original_tv_realtime_coarse = nil,
    original_tv_monotonic = nil,
    original_tv_monotonic_coarse = nil,
    original_tv_boottime = nil,
    original_tv_now = nil,
    monotonic = 0,
    realtime = 0,
    boottime = 0,
}

function MockTime:install()
    assert(self ~= nil)
    if self.original_util_time == nil then
        self.original_util_time = util.gettime
        assert(self.original_util_time ~= nil)
    end
    if self.original_tv_realtime == nil then
        self.original_tv_realtime = TimeVal.realtime
        assert(self.original_tv_realtime ~= nil)
    end
    if self.original_tv_realtime_coarse == nil then
        self.original_tv_realtime_coarse = TimeVal.realtime_coarse
        assert(self.original_tv_realtime_coarse ~= nil)
    end
    if self.original_tv_monotonic == nil then
        self.original_tv_monotonic = TimeVal.monotonic
        assert(self.original_tv_monotonic ~= nil)
    end
    if self.original_tv_monotonic_coarse == nil then
        self.original_tv_monotonic_coarse = TimeVal.monotonic_coarse
        assert(self.original_tv_monotonic_coarse ~= nil)
    end
    if self.original_tv_boottime == nil then
        self.original_tv_boottime = TimeVal.boottime
        assert(self.original_tv_boottime ~= nil)
    end
    if self.original_tv_now == nil then
        self.original_tv_now = TimeVal.now
        assert(self.original_tv_now ~= nil)
    end

    -- Store both REALTIME & MONOTONIC clocks
    self.realtime = os.time()
    local timespec = ffi.new("struct timespec")
    C.clock_gettime(C.CLOCK_MONOTONIC_COARSE, timespec)
    self.monotonic = tonumber(timespec.tv_sec)

    os.time = function() --luacheck: ignore
        logger.dbg("MockTime:os.time: ", self.realtime)
        return self.realtime
    end
    util.gettime = function()
        logger.dbg("MockTime:util.gettime: ", self.realtime)
        return self.realtime, 0
    end
    TimeVal.realtime = function()
        logger.dbg("MockTime:TimeVal.realtime: ", self.realtime)
        return TimeVal:new{ sec = self.realtime }
    end
    TimeVal.realtime_coarse = function()
        logger.dbg("MockTime:TimeVal.realtime_coarse: ", self.realtime)
        return TimeVal:new{ sec = self.realtime }
    end
    TimeVal.monotonic = function()
        logger.dbg("MockTime:TimeVal.monotonic: ", self.monotonic)
        return TimeVal:new{ sec = self.monotonic }
    end
    TimeVal.monotonic_coarse = function()
        logger.dbg("MockTime:TimeVal.monotonic_coarse: ", self.monotonic)
        return TimeVal:new{ sec = self.monotonic }
    end
    TimeVal.boottime = function()
        logger.dbg("MockTime:TimeVal.boottime: ", self.boottime)
        return TimeVal:new{ sec = self.boottime }
    end
    TimeVal.now = function()
        logger.dbg("MockTime:TimeVal.now: ", self.monotonic)
        return TimeVal:new{ sec = self.monotonic }
    end
end

function MockTime:uninstall()
    assert(self ~= nil)
    os.time = self.original_os_time --luacheck: ignore
    if self.original_util_time ~= nil then
        util.gettime = self.original_util_time
    end
    if self.original_tv_realtime ~= nil then
        TimeVal.realtime = self.original_tv_realtime
    end
    if self.original_tv_realtime_coarse ~= nil then
        TimeVal.realtime_coarse = self.original_tv_realtime_coarse
    end
    if self.original_tv_monotonic ~= nil then
        TimeVal.monotonic = self.original_tv_monotonic
    end
    if self.original_tv_monotonic_coarse ~= nil then
        TimeVal.monotonic_coarse = self.original_tv_monotonic_coarse
    end
    if self.original_tv_boottime ~= nil then
        TimeVal.boottime = self.original_tv_boottime
    end
    if self.original_tv_now ~= nil then
        TimeVal.now = self.original_tv_now
    end
end

function MockTime:set_realtime(value)
    assert(self ~= nil)
    if type(value) ~= "number" then
        return false
    end
    self.realtime = math.floor(value)
    logger.dbg("MockTime:set_realtime ", self.realtime)
    return true
end

function MockTime:increase_realtime(value)
    assert(self ~= nil)
    if type(value) ~= "number" then
        return false
    end
    self.realtime = math.floor(self.realtime + value)
    logger.dbg("MockTime:increase_realtime ", self.realtime)
    return true
end

function MockTime:set_monotonic(value)
    assert(self ~= nil)
    if type(value) ~= "number" then
        return false
    end
    self.monotonic = math.floor(value)
    logger.dbg("MockTime:set_monotonic ", self.monotonic)
    return true
end

function MockTime:increase_monotonic(value)
    assert(self ~= nil)
    if type(value) ~= "number" then
        return false
    end
    self.monotonic = math.floor(self.monotonic + value)
    logger.dbg("MockTime:increase_monotonic ", self.monotonic)
    return true
end

function MockTime:set_boottime(value)
    assert(self ~= nil)
    if type(value) ~= "number" then
        return false
    end
    self.boottime = math.floor(value)
    logger.dbg("MockTime:set_boottime ", self.boottime)
    return true
end

function MockTime:increase_boottime(value)
    assert(self ~= nil)
    if type(value) ~= "number" then
        return false
    end
    self.boottime = math.floor(self.boottime + value)
    logger.dbg("MockTime:increase_boottime ", self.boottime)
    return true
end

function MockTime:set(value)
    assert(self ~= nil)
    if type(value) ~= "number" then
        return false
    end
    self.realtime = math.floor(value)
    logger.dbg("MockTime:set (realtime) ", self.realtime)
    self.monotonic = math.floor(value)
    logger.dbg("MockTime:set (monotonic) ", self.monotonic)
    self.boottime = math.floor(value)
    logger.dbg("MockTime:set (boottime) ", self.boottime)
    return true
end

function MockTime:increase(value)
    assert(self ~= nil)
    if type(value) ~= "number" then
        return false
    end
    self.realtime = math.floor(self.realtime + value)
    logger.dbg("MockTime:increase (realtime) ", self.realtime)
    self.monotonic = math.floor(self.monotonic + value)
    logger.dbg("MockTime:increase (monotonic) ", self.monotonic)
    self.boottime = math.floor(self.boottime + value)
    logger.dbg("MockTime:increase (boottime) ", self.boottime)
    return true
end

return MockTime
