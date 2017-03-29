local BasePowerD = require("device/generic/powerd")
local _, android = pcall(require, "android")

local AndroidPowerD = BasePowerD:new{
    fl_min = 0, fl_max = 25,
    fl_intensity = 10,
}

function AndroidPowerD:init()
end

function AndroidPowerD:setIntensityHW()
    android.setScreenBrightness(math.floor(255 * self.fl_intensity / 25))
end

function AndroidPowerD:getCapacityHW()
    return android.getBatteryLevel()
end

function AndroidPowerD:isChargingHW()
    return android.isCharging()
end

return AndroidPowerD
