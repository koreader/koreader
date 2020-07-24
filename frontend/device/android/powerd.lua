local BasePowerD = require("device/generic/powerd")
local _, android = pcall(require, "android")

local AndroidPowerD = BasePowerD:new{
    fl_min = 0, fl_max = 25,
--    fl_intensity = 10,
}

function AndroidPowerD:frontlightIntensityHW()
    intensity = math.floor(android.getScreenBrightness() / 255 * self.fl_max)
    if intensity < 0 then
        intensity = 0
    end
    return intensity
end

function AndroidPowerD:setIntensityHW(intensity)
    self.fl_intensity = intensity
    android.setScreenBrightness(math.floor(255 * intensity / self.fl_max))
end

function AndroidPowerD:init()
    if self.device:hasNaturalLight() then
        self.fl_warmth = self.getWarmth()
    end
end

function AndroidPowerD:setWarmth(warmth)
    self.fl_warmth = warmth
    android.setScreenWarmth(warmth)
end

function AndroidPowerD:getWarmth()
    return android.getScreenWarmth()
end

function AndroidPowerD:getMaxWarmth()
    return android.getScreenMaxWarmth()
end

function AndroidPowerD:getMinWarmth()
    return android.getScreenMinWarmth()
end


function AndroidPowerD:getCapacityHW()
    return android.getBatteryLevel()
end

function AndroidPowerD:isChargingHW()
    return android.isCharging()
end

return AndroidPowerD
