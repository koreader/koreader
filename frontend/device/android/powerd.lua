local BasePowerD = require("device/generic/powerd")
local _, android = pcall(require, "android")

local AndroidPowerD = BasePowerD:new{
    fl_min = 0, fl_max = 25,
    fl_intensity = 10,
}

function AndroidPowerD:frontlightIntensityHW()
    return android.getScreenBrightness()
end

function AndroidPowerD:setIntensityHW(intensity)
    android.setScreenBrightness(math.floor(255 * intensity / 25))
end

function AndroidPowerD:getCapacityHW()
    return android.getBatteryLevel()
end

function AndroidPowerD:isChargingHW()
    return android.isCharging()
end

return AndroidPowerD
