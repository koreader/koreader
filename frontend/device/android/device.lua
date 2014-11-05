local Generic = require("device/generic/device")
local isAndroid, android = pcall(require, "android")
local ffi = require("ffi")

local function yes() return true end

local Device = Generic:new{
    model = "Android",
    isAndroid = yes,
    firmware_rev = "none",
    display_dpi = ffi.C.AConfiguration_getDensity(android.app.config),
}

function Device:init()
    self.screen = require("device/screen"):new{device = self}
    self.powerd = require("device/android/powerd"):new{device = self}
    self.input = require("device/input"):new{
        device = self,
        event_map = require("device/android/event_map"),
        handleMiscEv = function(self, ev)
            if ev.code == ffi.C.APP_CMD_SAVE_STATE then
                return "SaveState"
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

    Generic:init()
end

return Device
