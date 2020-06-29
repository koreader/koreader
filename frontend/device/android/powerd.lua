local BasePowerD = require("device/generic/powerd")
local SysfsLight = require ("device/sysfs_light") -- for android eInk devices using natural light
local PluginShare = require("pluginshare")
local _, android = pcall(require, "android")

local AndroidPowerD = BasePowerD:new{
    fl_min = 0, fl_max = 100,
    fl_intensity = 10,
    
    fl_warmth_min = 0, fl_warmth_max = 10,
    fl_warmth = nil,
    auto_warmth = false,
    max_warmth_hour = 23,
    fl_was_on = nil,
}

function AndroidPowerD:frontlightIntensityHW()
    return math.floor(android.getScreenBrightness() / 255 * self.fl_max)
end

function AndroidPowerD:setIntensityHW(intensity)
    android.setScreenBrightness(math.floor(255 * intensity / self.fl_max))
end

function AndroidPowerD:getCapacityHW()
    return android.getBatteryLevel()
end

function AndroidPowerD:isChargingHW()
    return android.isCharging()
end

function AndroidPowerD:init()
    if self.device:hasFrontlight() then
        -- If this device has natural light (currently only Android on Tolino Epos 2)
        -- Use the SysFS interface, and ioctl otherwise.
        -- NOTE: On the Forma, nickel still appears to prefer using ntx_io to handle the FL,
        --       but it does use sysfs for the NL...
        if self.device:hasNaturalLight() then
            local nl_config = G_reader_settings:readSetting("natural_light_config")
            if nl_config then
                for key,val in pairs(nl_config) do
                    self.device.frontlight_settings[key] = val
                end
            end
            -- Does this device's NaturalLight use a custom scale?
            self.fl_warmth_min = self.device.frontlight_settings.nl_min or self.fl_warmth_min
            self.fl_warmth_max = self.device.frontlight_settings.nl_max or self.fl_warmth_max
            -- If this device has a mixer, we can use the ioctl for brightness control, as it's much lower latency.
            if self.device:hasNaturalLightMixer() then
                local kobolight = require("ffi/kobolight")
                local ok, light = pcall(kobolight.open)
                if ok then
                    self.device.frontlight_settings.frontlight_ioctl = light
                end
            end
            self.fl = SysfsLight:new(self.device.frontlight_settings)
            self.fl_warmth = 0
        else
            local kobolight = require("ffi/kobolight")
            local ok, light = pcall(kobolight.open)
            if ok then
                self.fl = light
            end
        end
    end
end


function AndroidPowerD:setWarmth(warmth)
    if self.fl == nil then return end
    if not warmth and self.auto_warmth then
        self:calculateAutoWarmth()
    end
    self.fl_warmth = warmth or self.fl_warmth
    -- Don't turn the light back on on legacy NaturalLight devices just for the sake of setting the warmth!
    -- That's because we can only set warmth independently of brightness on devices with a mixer.
    -- On older ones, calling setWarmth *will* actually set the brightness, too!
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


return AndroidPowerD
