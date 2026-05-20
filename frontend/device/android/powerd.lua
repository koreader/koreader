local BasePowerD = require("device/generic/powerd")
local logger = require("logger")
local _, android = pcall(require, "android")

local AndroidPowerD = BasePowerD:new{
    fl_min = 0,
    fl_max = 100,
}

function AndroidPowerD:frontlightIntensityHW()
    return math.floor(android.getScreenBrightness() / self.bright_diff * self.fl_max)
end

function AndroidPowerD:setIntensityHW(intensity)
    -- If the frontlight switch was off, turn it on.
    android.enableFrontlightSwitch()

    self.fl_intensity = intensity
    android.setScreenBrightness(math.floor(intensity * self.bright_diff / self.fl_max))
    self:_decideFrontlightState()
end

function AndroidPowerD:init()
    local min_bright = android.getScreenMinBrightness()
    self.bright_diff = android.getScreenMaxBrightness() - min_bright

    -- if necessary scale fl_min:
    --    do not use fl_min==0 if getScreenMinBrightness!=0,
    --    because intenstiy==0 would mean to use system intensity
    if min_bright ~= self.fl_min then
        self.fl_min = math.ceil(min_bright * self.bright_diff / self.fl_max)
    end

    if self.device:hasNaturalLight() then
        self.fl_warmth_min = android.getScreenMinWarmth()
        self.fl_warmth_max = android.getScreenMaxWarmth()
        self.warm_diff = self.fl_warmth_max - self.fl_warmth_min
        -- The sysfs warmth node resets on every app start/resume, so push the
        -- saved value back to hardware now so frontlightWarmthHW() reads it correctly.
        local saved = G_reader_settings:readSetting("frontlight_warmth") or 0
        logger.warn("AndroidPowerD:init: saved frontlight_warmth=", saved, "warm_diff=", self.warm_diff)
        if saved > 0 then
            local native = math.floor(saved * self.warm_diff / 100)
            logger.warn("AndroidPowerD:init: setting native warmth=", native)
            android.setScreenWarmth(native)
        end
    end
end

function AndroidPowerD:setWarmthHW(warmth)
    logger.warn("AndroidPowerD:setWarmthHW: warmth=", warmth, "fl_warmth=", self.fl_warmth)
    android.setScreenWarmth(warmth)
    if self.fl_warmth then
        G_reader_settings:saveSetting("frontlight_warmth", self.fl_warmth)
        G_reader_settings:flush()
        logger.warn("AndroidPowerD:setWarmthHW: saved frontlight_warmth=", self.fl_warmth)
    end
end

function AndroidPowerD:frontlightWarmthHW()
    return android.getScreenWarmth() * self.warm_diff
end

function AndroidPowerD:getCapacityHW()
    return android.getBatteryLevel()
end

function AndroidPowerD:isChargingHW()
    return android.isCharging()
end

function AndroidPowerD:turnOffFrontlightHW()
    if not self:isFrontlightOnHW() then
        return
    end
    android.setScreenBrightness(self.fl_min)

    if android.hasStandaloneWarmth() then
        android.setScreenWarmth(self.fl_warmth_min)
    end
end

function AndroidPowerD:turnOnFrontlightHW(done_callback)
    logger.warn("AndroidPowerD:turnOnFrontlightHW: fl_warmth=", self.fl_warmth, "hasStandaloneWarmth=", android.hasStandaloneWarmth())
    if self:isFrontlightOn() and self:isFrontlightOnHW() then
        return
    end
    -- on devices with a software frontlight switch (e.g Tolinos), enable it
    android.enableFrontlightSwitch()

    android.setScreenBrightness(math.floor(self.fl_intensity * self.bright_diff / self.fl_max))

    if android.hasStandaloneWarmth() then
        android.setScreenWarmth(math.floor(self.fl_warmth / self.warm_diff))
    end
    return false
end

return AndroidPowerD
