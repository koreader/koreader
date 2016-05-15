local Event = require("ui/event")
local util = require("ffi/util")
local DEBUG = require("dbg")

local function yes() return true end
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
    needsTouchScreenProbe = no,

    -- use these only as a last resort. We should abstract the functionality
    -- and have device dependent implementations in the corresponting
    -- device/<devicetype>/device.lua file
    -- (these are functions!)
    isKindle = no,
    isKobo = no,
    isPocketBook = no,
    isAndroid = no,
    isSDL = no,

    -- some devices have part of their screen covered by the bezel
    viewport = nil,
    -- enforce portrait orientation on display, no matter how configured at
    -- startup
    isAlwaysPortrait = no,
    -- needs full screen refresh when resumed from screensaver?
    needsScreenRefreshAfterResume = yes,
}

function Device:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function Device:init()
    if not self.screen then
        error("screen/framebuffer must be implemented")
    end

    local is_eink = G_reader_settings:readSetting("eink")
    self.screen.eink = (is_eink == nil) or is_eink

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
        -- On FW >= 5.7.2, we sigstop awesome, but we need it to show stuff...
        if os.getenv("AWESOME_STOPPED") == "yes" then
            os.execute("killall -cont awesome")
        end
    end
    UIManager:sendEvent(Event:new("FlushSettings"))
end

-- ONLY used for Kindle devices
function Device:outofScreenSaver()
    if self.screen_saver_mode == true and self.charging_mode == false then
        -- On FW >= 5.7.2, put awesome to sleep again...
        if os.getenv("AWESOME_STOPPED") == "yes" then
            os.execute("killall -stop awesome")
        end
        -- wait for native system update screen before we recover saved
        -- Blitbuffer.
        util.usleep(1500000)
        self.screen:restoreFromSavedBB()
        self:resume()
        if self:needsScreenRefreshAfterResume() then
            self.screen:refreshFull()
        end
        self.powerd:refreshCapacity()
    end
    self.screen_saver_mode = false
end

-- ONLY used for Kobo and PocketBook devices
function Device:onPowerEvent(ev)
    local Screensaver = require("ui/screensaver")
    if (ev == "Power" or ev == "Suspend") and not self.screen_saver_mode then
        self.powerd:beforeSuspend()
        local UIManager = require("ui/uimanager")
        -- flushing settings first in case the screensaver takes too long time
        -- that flushing has no chance to run
        UIManager:sendEvent(Event:new("FlushSettings"))
        DEBUG("Suspending...")
        -- always suspend in portrait mode
        self.orig_rotation_mode = self.screen:getRotationMode()
        self.screen:setRotationMode(0)
        Screensaver:show()
        self.screen:refreshFull()
        self.screen_saver_mode = true
        UIManager:scheduleIn(10, self.suspend)
    elseif (ev == "Power" or ev == "Resume") and self.screen_saver_mode then
        DEBUG("Resuming...")
        local UIManager = require("ui/uimanager")
        UIManager:unschedule(self.suspend)
        self:resume()
        Screensaver:close()
        -- restore to previous rotation mode
        self.screen:setRotationMode(self.orig_rotation_mode)
        if self:needsScreenRefreshAfterResume() then
            self.screen:refreshFull()
        end
        self.screen_saver_mode = false
        self.powerd:refreshCapacity()
        self.powerd:afterResume()
    end
end

-- Hardware specific method to suspend the device
function Device:suspend() end

-- Hardware specific method to resume the device
function Device:resume() end

-- Hardware specific method to power off the device
function Device:powerOff() end

function Device:usbPlugIn()
    if self.charging_mode == false and self.screen_saver_mode == false then
        self.screen:saveCurrentBB()
        -- On FW >= 5.7.2, we sigstop awesome, but we need it to show stuff...
        if os.getenv("AWESOME_STOPPED") == "yes" then
            os.execute("killall -cont awesome")
        end
    end
    self.charging_mode = true
end

function Device:usbPlugOut()
    if self.charging_mode == true and self.screen_saver_mode == false then
        -- On FW >= 5.7.2, put awesome to sleep again...
        if os.getenv("AWESOME_STOPPED") == "yes" then
            os.execute("killall -stop awesome")
        end
        -- Same as when going out of screensaver, wait for the native system
        util.usleep(1500000)
        self.screen:restoreFromSavedBB()
        self.screen:refreshFull()
        self.powerd:refreshCapacity()
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
