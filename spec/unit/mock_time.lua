require("commonrequire")
local time = require("ui/time")
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
    original_tv_boottime_or_realtime_coarse = nil,
    original_tv_now = nil,
    monotonic = 0,
    realtime = 0,
    boottime = 0,
    boottime_or_realtime_coarse = 0,
    monotonic_time = 0,
    realtime_time = 0,
    boottime_time = 0,
    boottime_or_realtime_coarse_time = 0,
}

function MockTime:install()
    if self.original_util_time == nil then
        self.original_util_time = util.gettime
        assert(self.original_util_time ~= nil)
    end
    if self.original_tv_realtime == nil then
        self.original_tv_realtime = time.realtime
        assert(self.original_tv_realtime ~= nil)
    end
    if self.original_tv_realtime_coarse == nil then
        self.original_tv_realtime_coarse = time.realtime_coarse
        assert(self.original_tv_realtime_coarse ~= nil)
    end
    if self.original_tv_monotonic == nil then
        self.original_tv_monotonic = time.monotonic
        assert(self.original_tv_monotonic ~= nil)
    end
    if self.original_tv_monotonic_coarse == nil then
        self.original_tv_monotonic_coarse = time.monotonic_coarse
        assert(self.original_tv_monotonic_coarse ~= nil)
    end
    if self.original_tv_boottime == nil then
        self.original_tv_boottime = time.boottime
        assert(self.original_tv_boottime ~= nil)
    end
    if self.original_tv_boottime_or_realtime_coarse == nil then
        self.original_tv_boottime_or_realtime_coarse = time.boottime_or_realtime_coarse
        assert(self.original_tv_boottime_or_realtime_coarse ~= nil)
    end
    if self.original_tv_now == nil then
        self.original_tv_now = time.now
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
    time.realtime = function()
        logger.dbg("MockTime:Time.realtime: ", self.realtime)
        return time:new{ sec = self.realtime }
    end
    time.realtime_coarse = function()
        logger.dbg("MockTime:Time.realtime_coarse: ", self.realtime)
        return time:new{ sec = self.realtime }
    end
    time.monotonic = function()
        logger.dbg("MockTime:Time.monotonic: ", self.monotonic)
        return time:new{ sec = self.monotonic }
    end
    time.monotonic_coarse = function()
        logger.dbg("MockTime:Time.monotonic_coarse: ", self.monotonic)
        return time:new{ sec = self.monotonic }
    end
    time.boottime = function()
        logger.dbg("MockTime:Time.boottime: ", self.boottime)
        return time:new{ sec = self.boottime }
    end
    time.boottime_or_realtime_coarse = function()
        logger.dbg("MockTime:Time.boottime: ", self.boottime_or_realtime_coarse)
        return time:new{ sec = self.boottime_or_realtime_coarse }
    end
    time.now = function()
        logger.dbg("MockTime:Time.now: ", self.monotonic)
        return time:new{ sec = self.monotonic }
    end

    if self.original_tv_realtime_time == nil then
        self.original_tv_realtime_time = time.realtime
        assert(self.original_tv_realtime_time ~= nil)
    end
    if self.original_tv_realtime_coarse_time == nil then
        self.original_tv_realtime_coarse_time = time.realtime_coarse
        assert(self.original_tv_realtime_coarse_time ~= nil)
    end
    if self.original_tv_monotonic_time == nil then
        self.original_tv_monotonic_time = time.monotonic
        assert(self.original_tv_monotonic_time ~= nil)
    end
    if self.original_tv_monotonic_coarse_time == nil then
        self.original_tv_monotonic_coarse_time = time.monotonic_coarse
        assert(self.original_tv_monotonic_coarse_time ~= nil)
    end
    if self.original_tv_boottime_time == nil then
        self.original_tv_boottime_time = time.boottime
        assert(self.original_tv_boottime_time ~= nil)
    end
    if self.original_tv_boottime_or_realtime_coarse_time == nil then
        self.original_tv_boottime_or_realtime_coarse_time = time.boottime_or_realtime_coarse
        assert(self.original_tv_boottime_or_realtime_coarse_time ~= nil)
    end
    if self.original_tv_now == nil then
        self.original_tv_now = time.now
        assert(self.original_tv_now ~= nil)
    end

        -- Store both REALTIME & MONOTONIC clocks for fts
    self.realtime_time = os.time() * 1e6
    local timespec_time = ffi.new("struct timespec")
    C.clock_gettime(C.CLOCK_MONOTONIC_COARSE, timespec_time)
    self.monotonic = tonumber(timespec.tv_sec) * 1e6

    time.realtime = function()
        logger.dbg("MockTime:Time.realtime: ", self.realtime_time)
        return self.realtime_time
    end
    time.realtime_coarse = function()
        logger.dbg("MockTime:Time.realtime_coarse: ", self.realtime_coarse_time)
        return self.realtime_coarse_time
    end
    time.monotonic = function()
        logger.dbg("MockTime:Time.monotonic: ", self.monotonic)
        return self.monotonic_time
    end
    time.monotonic_coarse = function()
        logger.dbg("MockTime:Time.monotonic_coarse: ", self.monotonic)
        return self.monotonic_time
    end
    time.boottime = function()
        logger.dbg("MockTime:Time.boottime: ", self.boottime_time)
        return self.boottime_time
    end
    time.boottime_or_realtime_coarse = function()
        logger.dbg("MockTime:Time.boottime: ", self.boottime_or_realtime_coarse_time)
        return self.boottime_or_realtime_coarse_time
    end
    time.now = function()
        logger.dbg("MockTime:Time.now: ", self.monotonic)
        return self.monotonic_time
    end

 end

function MockTime:uninstall()
    os.time = self.original_os_time --luacheck: ignore
    if self.original_util_time ~= nil then
        util.gettime = self.original_util_time
    end
    if self.original_tv_realtime ~= nil then
        time.realtime = self.original_tv_realtime
    end
    if self.original_tv_realtime_coarse ~= nil then
        time.realtime_coarse = self.original_tv_realtime_coarse
    end
    if self.original_tv_monotonic ~= nil then
        time.monotonic = self.original_tv_monotonic
    end
    if self.original_tv_monotonic_coarse ~= nil then
        time.monotonic_coarse = self.original_tv_monotonic_coarse
    end
    if self.original_tv_boottime ~= nil then
        time.boottime = self.original_tv_boottime
    end
    if self.original_tv_boottime_or_realtime_coarse ~= nil then
        time.boottime_or_realtime_coarse = self.original_tv_boottime_or_realtime_coarse
    end
    if self.original_tv_now ~= nil then
        time.now = self.original_tv_now
    end
end

function MockTime:set_realtime(value)
    if type(value) ~= "number" then
        return false
    end
    self.realtime = math.floor(value)
    logger.dbg("MockTime:set_realtime ", self.realtime)
    return true
end

function MockTime:increase_realtime(value)
    if type(value) ~= "number" then
        return false
    end
    self.realtime = math.floor(self.realtime + value)
    logger.dbg("MockTime:increase_realtime ", self.realtime)
    return true
end

function MockTime:set_monotonic(value)
    if type(value) ~= "number" then
        return false
    end
    self.monotonic = math.floor(value)
    logger.dbg("MockTime:set_monotonic ", self.monotonic)
    return true
end

function MockTime:increase_monotonic(value)
    if type(value) ~= "number" then
        return false
    end
    self.monotonic = math.floor(self.monotonic + value)
    logger.dbg("MockTime:increase_monotonic ", self.monotonic)
    return true
end

function MockTime:set_boottime(value)
    if type(value) ~= "number" then
        return false
    end
    self.boottime = math.floor(value)
    logger.dbg("MockTime:set_boottime ", self.boottime)
    return true
end

function MockTime:increase_boottime(value)
    if type(value) ~= "number" then
        return false
    end
    self.boottime = math.floor(self.boottime + value)
    logger.dbg("MockTime:increase_boottime ", self.boottime)
    return true
end

function MockTime:set_boottime_or_realtime_coarse(value)
    if type(value) ~= "number" then
        return false
    end
    self.boottime_or_realtime_coarse = math.floor(value)
    logger.dbg("MockTime:set_boottime ", self.boottime_or_realtime_coarse)
    return true
end

function MockTime:increase_boottime_or_realtime_coarse(value)
    if type(value) ~= "number" then
        return false
    end
    self.boottime_or_realtime_coarse = math.floor(self.boottime_or_realtime_coarse + value)
    logger.dbg("MockTime:increase_boottime ", self.boottime_or_realtime_coarse)
    return true
end

function MockTime:set(value)
    if type(value) ~= "number" then
        return false
    end
    self.realtime = math.floor(value)
    logger.dbg("MockTime:set (realtime) ", self.realtime)
    self.monotonic = math.floor(value)
    logger.dbg("MockTime:set (monotonic) ", self.monotonic)
    self.boottime = math.floor(value)
    logger.dbg("MockTime:set (boottime) ", self.boottime)
    self.boottime_or_realtime_coarse = math.floor(value)
    logger.dbg("MockTime:set (boottime) ", self.boottime_or_realtime_coarse)
    return true
end

function MockTime:increase(value)
    if type(value) ~= "number" then
        return false
    end
    self.realtime = math.floor(self.realtime + value)
    logger.dbg("MockTime:increase (realtime) ", self.realtime)
    self.monotonic = math.floor(self.monotonic + value)
    logger.dbg("MockTime:increase (monotonic) ", self.monotonic)
    self.boottime = math.floor(self.boottime + value)
    logger.dbg("MockTime:increase (boottime) ", self.boottime)
    self.boottime_or_realtime_coarse = math.floor(self.boottime_or_realtime_coarse + value)
    logger.dbg("MockTime:increase (boottime) ", self.boottime_or_realtime_coarse)

    local value_time = value * 1e6
    self.realtime_time = math.floor(self.realtime_time + value_time)
    logger.dbg("MockTime:increase (realtime) ", self.realtime_time)
    self.monotonic_time = math.floor(self.monotonic_time + value_time)
    logger.dbg("MockTime:increase (monotonic) ", self.monotonic)
    self.boottime_time = math.floor(self.boottime_time + value_time)
    logger.dbg("MockTime:increase (boottime) ", self.boottime_time)
    self.boottime_or_realtime_coarse_time = math.floor(self.boottime_or_realtime_coarse_time + value_time)
    logger.dbg("MockTime:increase (boottime) ", self.boottime_or_realtime_coarse_time)

    return true
end

return MockTime
