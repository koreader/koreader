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

        -- BasePowerD:new() assigns warmth_scale to the class rather than the instance, and
        -- only *after* init() returns -- and the module-level BasePowerD:new{} that built
        -- this class already set it to 1, from the default fl_warmth_max of 100. setWarmth()
        -- below would otherwise scale with that stale 1 and hand the controller an
        -- unscaled value, so compute the real one here (c.f. KoboPowerD:init).
        self.warmth_scale = 100 / self.fl_warmth_max

        -- Nothing else restores warmth on Android. Brightness is restored by the framework,
        -- but warmth is only ever written when the user moves the slider, so whatever the
        -- hardware happens to hold at startup wins. That is harmless where the hardware
        -- keeps our value, but not where a vendor layer re-applies its own: on the Nook
        -- Glowlight 4 Plus, B&N's colour temperature service resets warmth to cold on every
        -- unlock. Push our saved value back so that ours is the one that sticks.
        local warmth = G_reader_settings:readSetting("frontlight_warmth")
        if warmth then
            self.fl_warmth = warmth
            self:setWarmth(warmth, true)
        end
    end
end

function AndroidPowerD:setWarmthHW(warmth)
    android.setScreenWarmth(warmth)
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
