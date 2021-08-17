local BasePowerD = require("device/generic/powerd")
local NickelConf = require("device/kobo/nickel_conf")
local PluginShare = require("pluginshare")
local SysfsLight = require ("device/sysfs_light")
local ffiUtil = require("ffi/util")
local RTC = require("ffi/rtc")

-- Here, we only deal with the real hw intensity.
-- Dealing with toggling and remembering/restoring
-- previous intensity when toggling/untoggling is done
-- by BasePowerD.

local KoboPowerD = BasePowerD:new{
    fl_min = 0, fl_max = 100,
    fl = nil,

    battery_sysfs = nil,
    fl_warmth_min = 0, fl_warmth_max = 100,
    fl_warmth = nil,
    auto_warmth = false,
    max_warmth_hour = 23,
    fl_was_on = nil,
}

--- @todo Remove KOBO_LIGHT_ON_START
function KoboPowerD:_syncKoboLightOnStart()
    local new_intensity = nil
    local is_frontlight_on = nil
    local new_warmth = nil
    local auto_warmth = nil
    local kobo_light_on_start = tonumber(KOBO_LIGHT_ON_START)
    if kobo_light_on_start then
        if kobo_light_on_start > 0 then
            new_intensity = math.min(kobo_light_on_start, 100)
            is_frontlight_on = true
        elseif kobo_light_on_start == 0 then
            new_intensity = 0
            is_frontlight_on = false
        elseif kobo_light_on_start == -2 then -- get values from NickelConf
            new_intensity = NickelConf.frontLightLevel.get()
            is_frontlight_on = NickelConf.frontLightState:get()
            if self.fl_warmth ~= nil then
                local new_color = NickelConf.colorSetting.get()
                if new_color ~= nil then
                    -- ColorSetting is stored as a color temperature scale in Kelvin,
                    -- from 1500 to 6400
                    -- so normalize this to [0,100] on our end.
                    new_warmth = (100 - math.floor((new_color - 1500) / 49))
                end
                auto_warmth = NickelConf.autoColorEnabled.get()
            end
            if is_frontlight_on == nil then
                -- this device does not support frontlight toggle,
                -- we set the value based on frontlight intensity.
                if new_intensity > 0 then
                    is_frontlight_on = true
                else
                    is_frontlight_on = false
                end
            end
            if is_frontlight_on == false and new_intensity == 0 then
                -- frontlight was toggled off in nickel, and we have no
                -- level-before-toggle-off (firmware without "FrontLightState"):
                -- use the one from koreader settings
                new_intensity = G_reader_settings:readSetting("frontlight_intensity")
            end
        else -- if kobo_light_on_start == -1 or other unexpected value then
            -- As we can't read value from the OS or hardware, use last values
            -- stored in koreader settings
            new_intensity = G_reader_settings:readSetting("frontlight_intensity")
            is_frontlight_on = G_reader_settings:readSetting("is_frontlight_on")
            if self.fl_warmth ~= nil then
                new_warmth = G_reader_settings:readSetting("frontlight_warmth")
                auto_warmth = G_reader_settings:readSetting("frontlight_auto_warmth")
            end
        end
    end

    if new_intensity ~= nil then
        self.hw_intensity = new_intensity
    end
    if is_frontlight_on ~= nil then
        -- will only be used to give initial state to BasePowerD:_decideFrontlightState()
        self.initial_is_fl_on = is_frontlight_on
    end
    -- This is always read from G_reader_settings, since we do not
    -- support reading 'BedTime' from NickelConf.
    local max_warmth_hour =
        G_reader_settings:readSetting("frontlight_max_warmth_hour")
    if max_warmth_hour then
        self.max_warmth_hour = max_warmth_hour
    end
    if auto_warmth then
        self.auto_warmth = true
        self:calculateAutoWarmth()
    elseif new_warmth ~= nil then
        self.fl_warmth = new_warmth
    end

    -- In any case frontlight is off, ensure intensity is non-zero so untoggle works
    if self.initial_is_fl_on == false and self.hw_intensity == 0 then
        self.hw_intensity = 1
    end
end

function KoboPowerD:init()
    -- Setup the sysfs paths
    self.batt_capacity_file = self.battery_sysfs .. "/capacity"
    self.is_charging_file = self.battery_sysfs .. "/status"

    -- Default values in case self:_syncKoboLightOnStart() does not find
    -- any previously saved setting (and for unit tests where it will
    -- not be called)
    self.hw_intensity = 20
    self.initial_is_fl_on = true
    self.autowarmth_job_running = false

    if self.device:hasFrontlight() then
        -- If this device has natural light (currently only KA1 & Forma)
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
            self:_syncKoboLightOnStart()
        else
            local kobolight = require("ffi/kobolight")
            local ok, light = pcall(kobolight.open)
            if ok then
                self.fl = light
                self:_syncKoboLightOnStart()
            end
        end
        -- See discussion in https://github.com/koreader/koreader/issues/3118#issuecomment-334995879
        -- for the reasoning behind this bit of insanity.
        if self:isFrontlightOnHW() then
            -- On devices with a mixer, setIntensity will *only* set the FL, so, ensure we honor the warmth, too.
            if self.device:hasNaturalLightMixer() then
               self:setWarmth(self.fl_warmth)
            end
            -- Use setIntensity to ensure it sets fl_intensity, and because we don't want the ramping behavior of turnOn
            self:setIntensity(self:frontlightIntensityHW())
        else
            -- Use setBrightness so as *NOT* to set hw_intensity, so toggle will still (mostly) work.
            self.fl:setBrightness(0)
            -- And make sure the fact that we started with the FL off propagates as best as possible.
            self.initial_is_fl_on = false
            -- NOTE: BasePowerD's init sets fl_intensity to hw_intensity right after this,
            -- so, instead of simply setting hw_intensity to either 1 or fl_min or fl_intensity, depending on user preference,
            -- we jump through a couple of hoops in turnOnFrontlightHW to recover from the first quirky toggle...
        end
    end
end

function KoboPowerD:saveSettings()
    if self.device:hasFrontlight() then
        -- Store BasePowerD values into settings (and not our hw_intensity, so
        -- that if frontlight was toggled off, we save and restore the previous
        -- untoggled intensity and toggle state at next startup)
        local cur_intensity = self.fl_intensity
        -- If we're shutting down straight from suspend then the frontlight won't
        -- be turned on but we still want to save its state.
        local cur_is_fl_on = self.is_fl_on or self.fl_was_on or false
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
        -- And to "Kobo eReader.conf" if needed
        if KOBO_SYNC_BRIGHTNESS_WITH_NICKEL then
            if NickelConf.frontLightState.get() ~= nil then
                if NickelConf.frontLightState.get() ~= cur_is_fl_on then
                    NickelConf.frontLightState.set(cur_is_fl_on)
                end
            else -- no support for frontlight state
                if not cur_is_fl_on then -- if toggled off, save intensity as 0
                    cur_intensity = self.fl_min
                end
            end
            if NickelConf.frontLightLevel.get() ~= cur_intensity then
                NickelConf.frontLightLevel.set(cur_intensity)
            end
            if cur_warmth ~= nil then
                local warmth_rescaled = (100 - cur_warmth) * 49 + 1500
                if NickelConf.colorSetting.get() ~= warmth_rescaled then
                    NickelConf.colorSetting.set(warmth_rescaled)
                end
                if NickelConf.autoColorEnabled.get() ~= cur_auto_warmth then
                    NickelConf.autoColorEnabled.set(cur_auto_warmth)
                end
            end
        end
    end
end

function KoboPowerD:frontlightIntensityHW()
    return self.hw_intensity
end

function KoboPowerD:isFrontlightOnHW()
    if self.initial_is_fl_on ~= nil then -- happens only once after init()
        -- give initial state to BasePowerD, which will
        -- reset our self.hw_intensity to 0 if self.initial_is_fl_on is false
        local ret = self.initial_is_fl_on
        self.initial_is_fl_on = nil
        return ret
    end
    return self.hw_intensity > 0
end

function KoboPowerD:setIntensityHW(intensity)
    if self.fl == nil then return end
    if self.fl_warmth == nil or self.device:hasNaturalLightMixer() then
        -- We either don't have NL, or we have a mixer: we only want to set the intensity (c.f., #5429)
        self.fl:setBrightness(intensity)
    else
        -- Not having a mixer sucks, we always have to set intensity combined w/ warmth (#5465)
        self.fl:setNaturalBrightness(intensity, self.fl_warmth)
    end
    self.hw_intensity = intensity
    -- Now that we have set intensity, we need to let BasePowerD
    -- know about possibly changed frontlight state (if we came
    -- from light toggled off to some intensity > 0).
    self:_decideFrontlightState()
end

function KoboPowerD:setWarmth(warmth)
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
function KoboPowerD:calculateAutoWarmth()
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
        if package.loaded["ui/uimanager"] ~= nil then
            local Event = require("ui/event")
            local UIManager = require("ui/uimanager")
            UIManager:broadcastEvent(Event:new("BackgroundJobsUpdated"))
        end
        self.autowarmth_job_running = true
    end
end

function KoboPowerD:getCapacityHW()
    return self:read_int_file(self.batt_capacity_file)
end

function KoboPowerD:isChargingHW()
    return self:read_str_file(self.is_charging_file) == "Charging"
end

function KoboPowerD:turnOffFrontlightHW()
    if not self:isFrontlightOnHW() then
        return
    end
    ffiUtil.runInSubProcess(function()
        for i = 1,5 do
            self:setIntensityHW(math.floor(self.fl_intensity - ((self.fl_intensity / 5) * i)))
            --- @note: Newer devices appear to block slightly longer on FL ioctls/sysfs, so only sleep on older devices,
            ---        otherwise we get a jump and not a ramp ;).
            if not self.device:hasNaturalLight() then
                if (i < 5) then
                    ffiUtil.usleep(35 * 1000)
                end
            end
        end
    end, false, true)
    -- NOTE: This is essentially what setIntensityHW does, except we don't actually touch the FL,
    --       we only sync the state of the main process with the final state of what we're doing in the forks.
    -- And update hw_intensity in our actual process ;).
    self.hw_intensity = self.fl_min
    -- NOTE: And don't forget to update sysfs_light, too, as a real setIntensityHW would via setBrightness
    if self.fl then
        self.fl.current_brightness = self.fl_min
    end
    self:_decideFrontlightState()
end

function KoboPowerD:turnOnFrontlightHW()
    -- NOTE: Insane workaround for the first toggle after a startup with the FL off.
    -- The light is actually off, but hw_intensity couldn't have been set to a sane value because of a number of interactions.
    -- So, fix it now, so we pass the isFrontlightOnHW check (which checks if hw_intensity > fl_min).
    if (self.is_fl_on == false and self.hw_intensity > self.fl_min and self.hw_intensity == self.fl_intensity) then
        self.hw_intensity = self.fl_min
    end
    if self:isFrontlightOnHW() then
        return
    end
    ffiUtil.runInSubProcess(function()
        for i = 1,5 do
            self:setIntensityHW(math.ceil(self.fl_min + ((self.fl_intensity / 5) * i)))
            --- @note: Newer devices appear to block slightly longer on FL ioctls/sysfs, so only sleep on older devices,
            ---        otherwise we get a jump and not a ramp ;).
            if not self.device:hasNaturalLight() then
                if (i < 5) then
                    ffiUtil.usleep(35 * 1000)
                end
            end
        end
    end, false, true)
    -- NOTE: This is essentially what setIntensityHW does, except we don't actually touch the FL,
    --       we only sync the state of the main process with the final state of what we're doing in the forks.
    -- And update hw_intensity in our actual process ;).
    self.hw_intensity = self.fl_intensity
    -- NOTE: And don't forget to update sysfs_light, too, as a real setIntensityHW would via setBrightness
    if self.fl then
        self.fl.current_brightness = self.fl_intensity
    end
    self:_decideFrontlightState()
end

-- Turn off front light before suspend.
function KoboPowerD:beforeSuspend()
    if self.fl == nil then return end
    -- Remember the current frontlight state
    self.fl_was_on = self.is_fl_on
    -- Turn off the frontlight
    self:turnOffFrontlight()
end

-- Restore front light state after resume.
function KoboPowerD:afterResume()
    if self.fl == nil then return end
    -- Don't bother if the light was already off on suspend
    if not self.fl_was_on then return end
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

    -- Set the system clock to the hardware clock's time.
    RTC:HCToSys()
end

return KoboPowerD
