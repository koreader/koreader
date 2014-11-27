local Generic = require("device/generic/device")
local isAndroid, android = pcall(require, "android")
local ffi = require("ffi")
local DEBUG = require("dbg")

local function yes() return true end

local Device = Generic:new{
    model = "Android",
    isAndroid = yes,
    firmware_rev = "none",
    display_dpi = ffi.C.AConfiguration_getDensity(android.app.config),
}

function Device:init()
    self.screen = require("ffi/framebuffer_android"):new{device = self, debug = DEBUG}
    self.powerd = require("device/android/powerd"):new{device = self}
    self.input = require("device/input"):new{
        device = self,
        event_map = require("device/android/event_map"),
        handleMiscEv = function(self, ev)
            DEBUG("Android application event", ev.code)
            if ev.code == ffi.C.APP_CMD_SAVE_STATE then
                return "SaveState"
            elseif ev.code == ffi.C.APP_CMD_GAINED_FOCUS then
                self.device.screen:refreshFull()
            elseif ev.code == ffi.C.APP_CMD_WINDOW_REDRAW_NEEDED then
                self.device.screen:refreshFull()
            end
        end,
    }

    -- check if we have a keyboard
    if ffi.C.AConfiguration_getKeyboard(android.app.config)
       == ffi.C.ACONFIGURATION_KEYBOARD_QWERTY
    then
        self.hasKeyboard = yes
    end
    -- check if we have a touchscreen
    if ffi.C.AConfiguration_getTouchscreen(android.app.config)
       ~= ffi.C.ACONFIGURATION_TOUCHSCREEN_NOTOUCH
    then
        self.isTouchDevice = yes
    end

    Generic.init(self)
end

return Device
