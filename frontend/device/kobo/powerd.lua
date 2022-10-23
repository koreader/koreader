local BasePowerD = require("device/generic/powerd")
local Math = require("optmath")
local NickelConf = require("device/kobo/nickel_conf")
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
    aux_battery_sysfs = nil,
    fl_warmth_min = 0, fl_warmth_max = 100,
    fl_was_on = nil,
}

--- @todo Remove G_defaults:readSetting("KOBO_LIGHT_ON_START")
function KoboPowerD:_syncKoboLightOnStart()
    local new_intensity = nil
    local is_frontlight_on = nil
    local new_warmth = nil
    local kobo_light_on_start = tonumber(G_defaults:readSetting("KOBO_LIGHT_ON_START"))
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
                    -- so normalize this to [0, 100] on our end.
                    new_warmth = (100 - Math.round((new_color - 1500) * (1/49)))
                end
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

    if new_warmth ~= nil then
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

    if self.device:hasAuxBattery() then
        self.aux_batt_capacity_file = self.aux_battery_sysfs .. "/cilix_bat_capacity"
        self.aux_batt_connected_file = self.aux_battery_sysfs .. "/cilix_conn" -- or "active"
        self.aux_batt_charging_file = self.aux_battery_sysfs .. "/charge_status" -- "usb_conn" would not allow us to detect the "Full" state

        self.getAuxCapacityHW = function(this)
            -- NOTE: The first few reads after connecting to the PowerCover may fail, in which case,
            --       we pass that detail along to PowerD so that it may retry the call sooner.
            return this:unchecked_read_int_file(this.aux_batt_capacity_file)
        end

        self.isAuxBatteryConnectedHW = function(this)
            -- aux_batt_connected_file shows us:
            -- 0 if power cover is not connected
            -- 1 if the power cover is connected
            -- 1 or sometimes -1 if the power cover is connected without a charger
            return this:read_int_file(this.aux_batt_connected_file) ~= 0
        end

        self.isAuxChargingHW = function(this)
            -- 0 when discharging
            -- 3 when full
            -- 2 when charging via DCP
            return this:read_int_file(this.aux_batt_charging_file) ~= 0
        end

        self.isAuxChargedHW = function(this)
            return this:read_int_file(this.aux_batt_charging_file) == 3
        end
    end

    -- Default values in case self:_syncKoboLightOnStart() does not find
    -- any previously saved setting (and for unit tests where it will
    -- not be called)
    self.hw_intensity = 20
    self.initial_is_fl_on = true

    if self.device:hasFrontlight() then
        -- If this device has natural light (currently only KA1 & Forma)
        -- Use the SysFS interface, and ioctl otherwise.
        -- NOTE: On the Forma, nickel still appears to prefer using ntx_io to handle the FL,
        --       but it does use sysfs for the NL...
        if self.device:hasNaturalLight() then
            local nl_config = G_reader_settings:readSetting("natural_light_config")
            if nl_config then
                for key, val in pairs(nl_config) do
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
        -- Save intensity to koreader settings
        G_reader_settings:saveSetting("frontlight_intensity", cur_intensity)
        G_reader_settings:saveSetting("is_frontlight_on", cur_is_fl_on)
        if cur_warmth ~= nil then
            G_reader_settings:saveSetting("frontlight_warmth", cur_warmth)
        end
        -- And to "Kobo eReader.conf" if needed
        if G_defaults:readSetting("KOBO_SYNC_BRIGHTNESS_WITH_NICKEL") then
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

-- NOTE: We *can* actually read this from the system (as well as frontlight level, since Mk. 7),
--       but this is already a huge mess, so, keep ignoring it...
function KoboPowerD:frontlightWarmthHW()
    return self.fl_warmth
end

function KoboPowerD:setWarmthHW(warmth)
    if self.fl == nil then return end
    -- Don't turn the light back on on legacy NaturalLight devices just for the sake of setting the warmth!
    -- That's because we can only set warmth independently of brightness on devices with a mixer.
    -- On older ones, calling setWarmth *will* actually set the brightness, too!
    if self.device:hasNaturalLightMixer() or self:isFrontlightOnHW() then
        self.fl:setWarmth(warmth)
    end
end

function KoboPowerD:getCapacityHW()
    return self:read_int_file(self.batt_capacity_file)
end

-- NOTE: Match the behavior of the ntx_io _Is_USB_plugged ioctl!
--       (Otherwise, a device that is fully charged, but still plugged in will no longer be flagged as charging).
function KoboPowerD:isChargingHW()
    return self:read_str_file(self.is_charging_file) ~= "Discharging"
end

function KoboPowerD:isChargedHW()
    -- On sunxi, the proper "Full" status is reported, while older kernels (even Mk. 9) report "Not charging"
    -- c.f., POWER_SUPPLY_PROP_STATUS in ricoh61x_batt_get_prop @ drivers/power/ricoh619-battery.c
    --       (or drivers/power/supply/ricoh619-battery.c on newer kernels).
    local status = self:read_str_file(self.is_charging_file)
    if status == "Full" then
        return true
    elseif status == "Not charging" and self:getCapacity() == 100 then
        return true
    end

    return false
end

function KoboPowerD:turnOffFrontlightHW()
    if not self:isFrontlightOnHW() then
        return
    end
    ffiUtil.runInSubProcess(function()
        for i = 1, 5 do
            -- NOTE: Do *not* switch to (self.fl_intensity * (1/5) * i) here, it may lead to rounding errors,
            --       which is problematic paired w/ math.floor because it doesn't round towards zero,
            --       which means we may end up passing -1 to setIntensityHW, which will fail,
            --       because we're bypassing the clamping usually done by setIntensity...
            self:setIntensityHW(math.floor(self.fl_intensity - (self.fl_intensity / 5 * i)))
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
        for i = 1, 5 do
            self:setIntensityHW(math.ceil(self.fl_min + (self.fl_intensity / 5 * i)))
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
    -- Update warmth state
    if self.fl_warmth ~= nil then
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
