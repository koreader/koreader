local Event = require("ui/event")
local util = require("ffi/util")
local DEBUG = require("dbg")

local function no() return false end

local Device = {
    screen_saver_mode = false,
    charging_mode = false,
    survive_screen_saver = false,
    model = nil,
    powerd = nil,
    screen = nil,
    input = nil,

    -- hardware feature tests: (these are functions!)
    hasKeyboard = no,
    hasKeys = no,
    hasDPad = no,
    isTouchDevice = no,
    hasFrontlight = no,

    -- use these only as a last resort. We should abstract the functionality
    -- and have device dependent implementations in the corresponting
    -- device/<devicetype>/device.lua file
    -- (these are functions!)
    isKindle = no,
    isKobo = no,
    isPocketBook = no,
    isAndroid = no,
    isEmulator = no,

    -- some devices have part of their screen covered by the bezel
    viewport = nil,
    -- enforce portrait orientation on display, no matter how configured at startup
    isAlwaysPortrait = no,
}

function Device:new(o)
    local o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function Device:init()
    if not self.screen then
        error("screen/framebuffer must be implemented")
    end

    DEBUG("initializing for device", self.model)
    DEBUG("framebuffer resolution:", self.screen:getSize())

    if not self.input then
        self.input = require("device/input"):new{device = self}
    end
    if not self.powerd then
        self.powerd = require("device/generic/powerd"):new{device = self}
    end

    if self.viewport then
        DEBUG("setting a viewport:", self.viewport)
        self.screen:setViewport(self.viewport)
        self.input:registerEventAdjustHook(
            self.input.adjustTouchTranslate,
            {x = 0 - self.viewport.x, y = 0 - self.viewport.y})
    end
end

function Device:getPowerDevice()
    return self.powerd
end

-- ONLY used for Kindle devices
function Device:intoScreenSaver()
    local UIManager = require("ui/uimanager")
    if self.charging_mode == false and self.screen_saver_mode == false then
        self.screen:saveCurrentBB()
        self.screen_saver_mode = true
    end
    UIManager:sendEvent(Event:new("FlushSettings"))
end

-- ONLY used for Kindle devices
function Device:outofScreenSaver()
    if self.screen_saver_mode == true and self.charging_mode == false then
        -- wait for native system update screen before we recover saved
        -- Blitbuffer.
        util.usleep(1500000)
        self.screen:restoreFromSavedBB()
        self:resume()
    end
    self.screen_saver_mode = false
end

-- ONLY used for Kobo and PocketBook devices
function Device:onPowerEvent(ev)
    local Screensaver = require("ui/screensaver")
    if (ev == "Power" or ev == "Suspend") and not self.screen_saver_mode then
        local UIManager = require("ui/uimanager")
        -- flushing settings first in case the screensaver takes too long time that
        -- flushing has no chance to run
        UIManager:sendEvent(Event:new("FlushSettings"))
        DEBUG("Suspending...")
        -- always suspend in portrait mode
        self.orig_rotation_mode = self.screen:getRotationMode()
        self.screen:setRotationMode(0)
        Screensaver:show()
        self:prepareSuspend()
        UIManager:scheduleIn(10, self.suspend)
    elseif (ev == "Power" or ev == "Resume") and self.screen_saver_mode then
        DEBUG("Resuming...")
        -- restore to previous rotation mode
        self.screen:setRotationMode(self.orig_rotation_mode)
        self:resume()
        Screensaver:close()
    end
end

function Device:prepareSuspend()
    if self.powerd and self.powerd.fl ~= nil then
        -- in no case should the frontlight be turned on in suspend mode
        self.powerd.fl:sleep()
    end
    self.screen:refreshFull()
    self.screen_saver_mode = true
end

function Device:suspend()
end

function Device:resume()
    local UIManager = require("ui/uimanager")
    UIManager:unschedule(self.suspend)
    self.screen:refreshFull()
    self.screen_saver_mode = false
    self.powerd:refreshCapacity()
end

function Device:usbPlugIn()
    if self.charging_mode == false and self.screen_saver_mode == false then
        self.screen:saveCurrentBB()
    end
    self.charging_mode = true
end

function Device:usbPlugOut()
    if self.charging_mode == true and self.screen_saver_mode == false then
        self.screen:restoreFromSavedBB()
        self.screen:refreshFull()
    end

    --@TODO signal filemanager for file changes  13.06 2012 (houqp)
    self.charging_mode = false
end

--[[
prepare for application shutdown
--]]
function Device:exit()
    require("ffi/input"):closeAll()
    self.screen:close()
end

return Device
