local BasePowerD = require("device/generic/powerd")
local _, android = pcall(require, "android")

local AndroidPowerD = BasePowerD:new{
    fl_min = 0,
    fl_max = 100,
    -- Set to true on devices whose sysfs warmth node resets on every app start/resume
    -- (e.g. Nook GL4 Plus). Enables restore-on-init and per-change flush for crash safety.
    volatile_warmth = false,
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
        if self.volatile_warmth then
            -- Warmth node resets on every app start; restore the saved value now
            -- so frontlightWarmthHW() returns the correct state immediately.
            local saved = G_reader_settings:readSetting("frontlight_warmth") or 0
            if saved > 0 then
                android.setScreenWarmth(math.floor(saved * self.warm_diff / 100))
            end
        end
    end
end

function AndroidPowerD:setWarmthHW(warmth)
    android.setScreenWarmth(warmth)
    if self.volatile_warmth and self.fl_warmth then
        -- Flush immediately so the value survives a process kill before the
        -- normal settings flush on exit (needed for the restore-on-init path).
        G_reader_settings:saveSetting("frontlight_warmth", self.fl_warmth)
        G_reader_settings:flush()
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
