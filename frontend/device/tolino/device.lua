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

-- Tolino Vision 5
local TolinoVision5 = TolinoDevice:new{
    model = "Tolino_vision_5",
    hasEinkScreen = yes
}

if android.prop.hardwareType == "E70K00" then
    return TolinoVision5
else
    logger.warn("unrecognized Tolino model ".. android.prop.product.hardwareType.. " using generic android")
    return AndroidDevice
end
