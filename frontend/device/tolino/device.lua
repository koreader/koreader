local logger = require("logger")
local A, android = pcall(require, "android")  -- luacheck: ignore
local AndroidDevice = require("device/android/device")

local function yes() return true end
local function no() return false end

local TolinoDevice = AndroidDevice:new{
    model = "Tolino"
}

function TolinoDevice:init()
    AndroidDevice.init(self)
    self.input.event_map = require("device/tolino/event_map")
end

-- Tolino Vision 5, hardware model "E70K00"
local TolinoE70K00 = TolinoDevice:new{
    model = "Tolino_E70K00",
    hasEinkScreen = yes,
    frontlight_settings = {
        frontlight_white = "/sys/class/backlight/lm3630a_led",
        frontlight_red = "/sys/class/backlight/lm3630a_leda",
        frontlight_green = "/sys/class/backlight/lm3630a_ledb",
    },
}

if android.prop.hardwareType == "E70K00" then
    return TolinoE70K00
else
    logger.warn("unrecognized Tolino model ".. android.prop.product.hardwareType.. " using generic android")
    return AndroidDevice
end
