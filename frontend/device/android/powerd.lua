local BasePowerD = require("device/generic/powerd")
local _, android = pcall(require, "android")

local AndroidPowerD = BasePowerD:new{
    fl_min = 0,
    fl_max = 100,
}

function AndroidPowerD:frontlightIntensityHW()
    return math.floor(android.getScreenBrightness() / self.bright_diff * self.fl_max)
end

function AndroidPowerD:setIntensityHW(intensity)
    self.fl_intensity = intensity
    android.setScreenBrightness(math.floor(intensity * self.bright_diff / self.fl_max))
end

function AndroidPowerD:init()
    self.bright_diff = android:getScreenMaxBrightness() - android:getScreenMinBrightness()
    if self.device:hasNaturalLight() then
        self.warm_diff = android:getScreenMaxWarmth() - android:getScreenMinWarmth()
        self.fl_warmth = self:getWarmth()
    end
end

function AndroidPowerD:setWarmth(warmth)
    self.fl_warmth = warmth
    android.setScreenWarmth(warmth / self.warm_diff)
end

function AndroidPowerD:getWarmth()
   return android.getScreenWarmth() * self.warm_diff
end

function AndroidPowerD:getCapacityHW()
    return android.getBatteryLevel()
end

function AndroidPowerD:isChargingHW()
    return android.isCharging()
end

return AndroidPowerD
