local Generic = require("device/generic/device")
local _, android = pcall(require, "android")
local ffi = require("ffi")
local logger = require("logger")

local function yes() return true end
local function no() return false end

local Device = Generic:new{
    model = "Android",
    hasKeys = yes,
    hasDPad = no,
    isAndroid = yes,
    hasFrontlight = yes,
    firmware_rev = "none",
    display_dpi = android.lib.AConfiguration_getDensity(android.app.config),
    hasColorScreen = yes,
}

function Device:init()
    self.screen = require("ffi/framebuffer_android"):new{device = self, debug = logger.dbg}
    self.powerd = require("device/android/powerd"):new{device = self}
    self.input = require("device/input"):new{
        device = self,
        event_map = require("device/android/event_map"),
        handleMiscEv = function(this, ev)
            logger.dbg("Android application event", ev.code)
            if ev.code == ffi.C.APP_CMD_SAVE_STATE then
                return "SaveState"
            elseif ev.code == ffi.C.APP_CMD_GAINED_FOCUS then
                this.device.screen:refreshFull()
            elseif ev.code == ffi.C.APP_CMD_WINDOW_REDRAW_NEEDED then
                this.device.screen:refreshFull()
            end
        end,
    }

    -- check if we have a keyboard
    if android.lib.AConfiguration_getKeyboard(android.app.config)
       == ffi.C.ACONFIGURATION_KEYBOARD_QWERTY
    then
        self.hasKeyboard = yes
    end
    -- check if we have a touchscreen
    if android.lib.AConfiguration_getTouchscreen(android.app.config)
       ~= ffi.C.ACONFIGURATION_TOUCHSCREEN_NOTOUCH
    then
        self.isTouchDevice = yes
    end

    Generic.init(self)
end

function Device:initNetworkManager(NetworkMgr)
    NetworkMgr.turnOnWifi = function()
        android.setWifiEnabled(true)
    end

    NetworkMgr.turnOffWifi = function()
        android.setWifiEnabled(false)
    end
    NetworkMgr.isWifiOn = function()
        return android.isWifiEnabled()
    end
end

return Device
