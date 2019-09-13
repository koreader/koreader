local BasePowerD = require("device/generic/powerd")
local PluginShare = require("pluginshare")
local SysfsLight = require("device/sysfs_light")
local _, android = pcall(require, "android")

local AndroidPowerD = BasePowerD:new{
    fl_min = 0, fl_max = 25,
    fl_warmth_min = 0, fl_warmth_max = 100,
    fl_intensity = 10,
    fl = nil,
    fl_warmth = nil,
    auto_warmth = false,
    max_warmth_hour = 23,
}

function AndroidPowerD:init()
    self.hw_intensity = 20
    self.initial_is_fl_on = true
    self.autowarmth_job_running = false

    if self.device:hasNaturalLight() then
        local nl_config = G_reader_settings:readSetting("natural_light_config")
        if nl_config then
            for key,val in pairs(nl_config) do
                self.device.frontlight_settings[key] = val
            end
        end
        -- Does this device's NaturalLight use a custom scale?
        self.fl_warmth_min = self.device.frontlight_settings["nl_min"] or self.fl_warmth_min
        self.fl_warmth_max = self.device.frontlight_settings["nl_max"] or self.fl_warmth_max
        self.fl = SysfsLight:new(self.device.frontlight_settings)
        self.fl_warmth = 0
        --- @todo Sync sysfs backlight?
    end
end

function AndroidPowerD:saveSettings()
    if self.device:hasNaturalLight() then
        local cur_intensity = self.fl_intensity
        local cur_is_fl_on = self.is_fl_on
        local cur_warmth = self.fl_warmth
        local cur_auto_warmth = self.auto_warmth
        local cur_max_warmth_hour = self.max_warmth_hour
        -- Save intensity to koreader settings
        G_reader_settings:saveSetting("frontlight_intensity", cur_intensity)
        G_reader_settings:saveSetting("is_frontlight_on", cur_is_fl_on)
        if cur_warmth ~= nil then
            G_reader_settings:saveSetting("frontlight_warmth", cur_warmth)
            G_reader_settings:saveSetting("frontlight_auto_warmth", cur_auto_warmth)
            G_reader_settings:saveSetting("frontlight_max_warmth_hour", cur_max_warmth_hour)
        end
    end
end

function AndroidPowerD:frontlightIntensityHW()
    if self.fl == nil then
        return math.floor(android.getScreenBrightness() / 255 * self.fl_max)
    else
        return self.hw_intensity
    end
end

function AndroidPowerD:isFrontlightOnHW()
    if self.device:hasNaturalLight() then
        local white = self.fl:_get_light_value(self.fl.frontlight_white) or 0
        local green = self.fl:_get_light_value(self.fl.frontlight_green) or 0
        local red = self.fl:_get_light_value(self.fl.frontlight_red) or 0
        return (white + green + red) > 0
    else
        return self.hw_intensity > 0
    end
end

function AndroidPowerD:setIntensityHW(intensity)
    if self.device:hasNaturalLight() then
        if self.fl_warmth == nil then
            self.fl:setBrightness(intensity)
        else
            self.fl:setNaturalBrightness(intensity, self.fl_warmth)
        end
        self.hw_intensity = intensity
        self:_decideFrontlightState()
    else
        android.setScreenBrightness(math.floor(255 * intensity / self.fl_max))
    end
end

function AndroidPowerD:setWarmth(warmth)
    if self.fl == nil then return end
    if not warmth and self.auto_warmth then
        self.calculateAutoWarmth()
    end
    self.fl_warmth = warmth or self.fl_warmth
    if self.device:hasNaturalLightMixer() or self:isFrontlightOnHW() then
        self.fl:setWarmth(self.fl_warmth)
    end
end

-- Sets fl_warmth according to current hour and max_warmth_hour
-- and starts background job if necessary.
function AndroidPowerD:calculateAutoWarmth()
    local current_time = os.date("%H") + os.date("%M")/60
    local max_hour = self.max_warmth_hour
    local diff_time = max_hour - current_time
    if diff_time < 0 then
        diff_time = diff_time + 24
    end
    if diff_time < 12 then
        -- We are before bedtime. Use a slower progression over 5h.
        self.fl_warmth = math.max(20 * (5 - diff_time), 0)
    elseif diff_time > 22 then
        -- Keep warmth at maximum for two hours after bedtime.
        self.fl_warmth = 100
    else
        -- Between 2-4h after bedtime, return to zero.
        self.fl_warmth = math.max(100 - 50 * (22 - diff_time), 0)
    end
    self.fl_warmth = math.floor(self.fl_warmth + 0.5)
    -- Make sure sysfs_light actually picks that new value up without an explicit setWarmth call...
    -- This avoids having to bypass the ramp-up on resume w/ an explicit setWarmth call on devices where brightness & warmth
    -- are linked (i.e., when there's no mixer) ;).
    -- NOTE: A potentially saner solution would be to ditch the internal sysfs_light current_* values,
    --       and just pass it a pointer to this powerd instance, so it has access to fl_warmth & hw_intensity.
    --       It seems harmless enough for warmth, but brightness might be a little trickier because of the insanity
    --       that is hw_intensity handling because we can't actually *read* the frontlight status...
    --       (Technically, we could, on Mk. 7 devices, but we don't,
    --       because this is already messy enough without piling on special cases.)
    if self.fl then
        self.fl.current_warmth = self.fl_warmth
    end
    -- Enable background job for setting Warmth, if not already done.
    if not self.autowarmth_job_running then
        table.insert(PluginShare.backgroundJobs, {
                         when = 180,
                         repeated = true,
                         executable = function()
                             if self.auto_warmth then
                                 self:setWarmth()
                             end
                         end,
        })
        self.autowarmth_job_running = true
    end
end

function AndroidPowerD:getCapacityHW()
    return android.getBatteryLevel()
end

function AndroidPowerD:isChargingHW()
    return android.isCharging()
end

function AndroidPowerD:afterResume()
    if self.fl == nil then return end
    self:_decideFrontlightState()
    -- Update AutoWarmth state
    if self.fl_warmth ~= nil and self.auto_warmth then
        self:calculateAutoWarmth()
        -- And we need an explicit setWarmth if the device has a mixer, because turnOn won't touch the warmth on those ;).
        if self.device:hasNaturalLightMixer() then
            self:setWarmth(self.fl_warmth)
        end
    end
    -- Turn the frontlight back on
    self:turnOnFrontlight()
end

return AndroidPowerD
