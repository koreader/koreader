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
    -- if frontlight switch was toggled of, turn it on
    if not self.is_fl_sw_on then
        android:enableFrontlightSwitch()
        self.is_fl_sw_on = true
    end

    self.fl_intensity = intensity
    android.setScreenBrightness(math.floor(intensity * self.bright_diff / self.fl_max))
end

function AndroidPowerD:init()
    self.bright_diff = android:getScreenMaxBrightness() - android:getScreenMinBrightness()

    -- if necessary scale fl_min:
    --    do not use fl_min==0 if getScreenMinBrightness!=0,
    --    because intenstiy==0 would mean to use system intensity
    if android:getScreenMinBrightness() ~= self.fl_min then
        self.fl_min = math.ceil(android:getScreenMinBrightness() * self.bright_diff / self.fl_max)
    end

    if self.device:hasNaturalLight() then
        self.warm_diff = android:getScreenMaxWarmth() - android:getScreenMinWarmth()
        self.fl_warmth = self:getWarmth()
        self.fl_warmth_min = android:getScreenMinWarmth()
        self.fl_warmth_max = android:getScreenMaxWarmth()
    end

    self.is_fl_sw_on = android:getFrontlightSwitchState()
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

function BasePowerD:isFrontlightOn()
    assert(self ~= nil)
    return self.is_fl_on and self.is_fl_sw_on
end

function AndroidPowerD:turnOffFrontlightHW()
    if not self:isFrontlightOnHW() then
        return
    end
    android.setScreenBrightness(self.fl_min)
    self.is_fl_on = false

    self:broadcastLightChanges()
end

function AndroidPowerD:turnOnFrontlightHW()
    if not self.is_fl_sw_on then -- on devices with a software frontlight switch (e.g Tolinos), enable it
        android:enableFrontlightSwitch()
        self.is_fl_sw_on = true
    end

    if self:isFrontlightOn() and self:isFrontlightOnHW() then
        return
    end

    android.setScreenBrightness(math.floor(self.fl_intensity * self.bright_diff / self.fl_max))
    self.is_fl_on = true

    self:broadcastLightChanges()
end

function AndroidPowerD:getFrontlightSwitchState()
    return self.is_fl_sw_on
end

function AndroidPowerD:detectedFrontlightSwitchToggle()
    if self.is_fl_sw_on and not android:getFrontlightSwitchState() then
        android:enableFrontlightSwitch() --this sends keypress to android (and KOReader)
        self.is_fl_on = not self.is_fl_on
    elseif not self.is_fl_sw_on then -- only then frontlight switch was off at start
        self.is_fl_sw_on = true
    end

    if self.is_fl_on then
        android.setScreenBrightness(math.floor(self.fl_intensity * self.bright_diff / self.fl_max))
    else
        self:turnOffFrontlightHW()
    end

    self:broadcastLightChanges()
end

return AndroidPowerD
