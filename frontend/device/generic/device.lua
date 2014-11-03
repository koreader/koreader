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
    isTouchDevice = no,
    hasFrontlight = no,

    -- use these only as a last resort. We should abstract the functionality
    -- and have device dependent implementations in the corresponting
    -- device/<devicetype>/device.lua file
    -- (these are functions!)
    isKindle = no,
    isKobo = no,
    isAndroid = no,
    isEmulator = no,

    -- some devices have part of their screen covered by the bezel
    viewport = nil,
}

function Device:new(o)
    local o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function Device:init()
    if not self.screen then
        self.screen = require("device/screen"):new{device = self}
    end
    if not self.input then
        self.input = require("device/input"):new{device = self}
    end
    if not self.powerd then
        self.powerd = require("device/generic/powerd"):new{device = self}
    end

    if self.viewport then
        self.screen:setViewport(self.viewport)
        self.input:registerEventAdjustHook(
            self.input.adjustTouchTranslate,
            {x = 0 - self.viewport.x, y = 0 - self.viewport.y})
    end
end

function Device:getPowerDevice()
    return self.powerd
end

function Device:intoScreenSaver()
    if self.charging_mode == false and self.screen_saver_mode == false then
        self.screen:saveCurrentBB()
        self.screen_saver_mode = true
    end
end

function Device:outofScreenSaver()
    if self.screen_saver_mode == true and self.charging_mode == false then
        -- wait for native system update screen before we recover saved
        -- Blitbuffer.
        util.usleep(1500000)
        self.screen:restoreFromSavedBB()
        self.screen:refresh(0)
        self.survive_screen_saver = true
    end
    self.screen_saver_mode = false
end

function Device:onPowerEvent(ev)
    local Screensaver = require("ui/screensaver")
    if (ev == "Power" or ev == "Suspend") and not self.screen_saver_mode then
        local UIManager = require("ui/uimanager")
        DEBUG("Suspending...")
        -- always suspend in portrait mode
        self.orig_rotation_mode = self.screen:getRotationMode()
        self.screen:setRotationMode(0)
        Screensaver:show()
        self:prepareSuspend()
        UIManager:scheduleIn(2, function() self:Suspend() end)
    elseif (ev == "Power" or ev == "Resume") and self.screen_saver_mode then
        DEBUG("Resuming...")
        -- restore to previous rotation mode
        self.screen:setRotationMode(self.orig_rotation_mode)
        self:Resume()
        Screensaver:close()
    end
end

function Device:prepareSuspend()
    if self.powerd and self.powerd.fl ~= nil then
        -- in no case should the frontlight be turned on in suspend mode
        self.powerd.fl:sleep()
    end
    self.screen:refresh(0)
    self.screen_saver_mode = true
end

function Device:Suspend()
end

function Device:Resume()
    self.screen:refresh(1)
    self.screen_saver_mode = false
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
        self.screen:refresh(0)
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
