local AndroidPowerD = require("device/android/powerd")
local _, android = pcall(require, "android")

-- iReader Neo 3 Ultra specific frontlight behaviour.
--
-- The dual-channel LM3630A driver exposes no reliable software on/off flag, so
-- use the raw brightness value to decide the state. A gesture that dims the
-- light to 0 also leaves fl_intensity at fl_min, which would make
-- BasePowerD:turnOnFrontlight bail out; remember the user's brightness/warmth
-- across toggles so turning the light back on restores their previous levels.
local IReaderPowerD = setmetatable({}, { __index = AndroidPowerD })

IReaderPowerD.default_fl_intensity = 40
IReaderPowerD.default_fl_warmth = 50

function IReaderPowerD:isFrontlightOnHW()
    return android.getScreenBrightness() > 0
end

function IReaderPowerD:frontlightIntensityHW()
    local hw = math.floor(android.getScreenBrightness() / self.bright_diff * self.fl_max)
    if hw > 0 then
        return hw
    end
    -- Light is off: report the last-known intensity (or the default) so that
    -- turning the light back on restores the user's previous level instead of
    -- staying dark.
    return G_reader_settings:readSetting("frontlight_intensity") or self.default_fl_intensity
end

function IReaderPowerD:setIntensityHW(intensity)
    -- If the frontlight switch was off, turn it on.
    android.enableFrontlightSwitch()

    self.fl_intensity = intensity
    android.setScreenBrightness(math.floor(intensity * self.bright_diff / self.fl_max))
    if intensity > 0 then
        G_reader_settings:saveSetting("frontlight_intensity", intensity)
    end
    self:_decideFrontlightState()
end

function IReaderPowerD:setWarmthHW(warmth)
    android.setScreenWarmth(warmth)
    G_reader_settings:saveSetting("frontlight_warmth", self.fl_warmth)
end

function IReaderPowerD:frontlightWarmthHW()
    local hw = self:fromNativeWarmth(android.getScreenWarmth())
    if hw > 0 then
        return hw
    end
    -- Light is off: restore the last-known warmth (or the default).
    return G_reader_settings:readSetting("frontlight_warmth") or self.default_fl_warmth
end

function IReaderPowerD:turnOnFrontlight(done_callback)
    if not self.device:hasFrontlight() then return end
    if self:isFrontlightOn() then return false end
    -- BasePowerD would bail out here when fl_intensity == fl_min, which happens
    -- after a gesture setIntensity(0) turns the light off. Skip that check:
    -- turnOnFrontlightHW restores the last-on level from settings/defaults.
    local cb_handled = self:turnOnFrontlightHW(done_callback)
    self.is_fl_on = true
    self:stateChanged()
    if not cb_handled and done_callback then
        done_callback()
    end
    return true
end

function IReaderPowerD:turnOnFrontlightHW(done_callback)
    if self:isFrontlightOn() and self:isFrontlightOnHW() then
        return
    end
    -- on devices with a software frontlight switch (e.g Tolinos), enable it
    android.enableFrontlightSwitch()

    -- Restore brightness from the saved value (or the default) when the
    -- in-memory level is unset/zero (e.g. after a fresh start with the light off).
    local intensity = self.fl_intensity
    if not intensity or intensity <= self.fl_min then
        intensity = G_reader_settings:readSetting("frontlight_intensity") or self.default_fl_intensity
        self.fl_intensity = intensity
    end
    android.setScreenBrightness(math.floor(intensity * self.bright_diff / self.fl_max))

    -- Restore warmth as well, so toggling the light keeps the user's color mix.
    if self.device:hasNaturalLight() then
        local warmth = self.fl_warmth
        if not warmth or warmth <= 0 then
            warmth = G_reader_settings:readSetting("frontlight_warmth") or self.default_fl_warmth
            self.fl_warmth = warmth
        end
        android.setScreenWarmth(self:toNativeWarmth(warmth))
    end
    return false
end

return IReaderPowerD
