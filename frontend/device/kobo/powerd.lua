local BasePowerD = require("device/generic/powerd")
local Math = require("optmath")
local NickelConf = require("device/kobo/nickel_conf")
local SysfsLight = require("device/sysfs_light")
local UIManager
local logger = require("logger")
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

    -- In case frontlight is off, ensure hw_intensity is non-zero so toggle on works
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
        self.device.frontlight_settings = self.device.frontlight_settings or {}
        -- Does this device require non-standard ramping behavior?
        self.device.frontlight_settings.ramp_off_delay = self.device.frontlight_settings.ramp_off_delay or 0.0
        --- @note: Newer devices (or at least some PWM controllers) appear to block slightly longer on FL ioctls/sysfs,
        ---        so we only really need a delay on older devices.
        self.device.frontlight_settings.ramp_delay = self.device.frontlight_settings.ramp_delay or (self.device:hasNaturalLight() and 0.0 or 0.025)
        -- Some PWM controllers *really* don't like being interleaved between screen refreshes,
        -- so we delay the *start* of the ramp on these.
        self.device.frontlight_settings.delay_ramp_start = self.device.frontlight_settings.delay_ramp_start or false

        -- If this device has natural light, use the sysfs interface, and ioctl otherwise.
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
            -- Generic does it *after* init, but we're going to need it *now*...
            self.warmth_scale = 100 / self.fl_warmth_max
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
               self:setWarmth(self.fl_warmth, true)
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
        -- Pass our initial state to BasePowerD,
        -- which will reset our self.hw_intensity to 0 if self.initial_is_fl_on is false
        local ret = self.initial_is_fl_on
        self.initial_is_fl_on = nil
        return ret
    end
    return self.hw_intensity > 0 and not self.fl_ramp_down_running
end

function KoboPowerD:_setIntensityHW(intensity)
    if self.fl == nil then return end
    if self.fl_warmth == nil or self.device:hasNaturalLightMixer() then
        -- We either don't have NL, or we have a mixer: we only want to set the intensity (c.f., #5429)
        self.fl:setBrightness(intensity)
    else
        -- Not having a mixer sucks, we always have to set intensity combined w/ warmth (#5465)
        self.fl:setNaturalBrightness(intensity, self.fl_warmth)
    end
    self.hw_intensity = intensity
    -- Now that we have set the intensity,
    -- we need to let BasePowerD know about the possibly new frontlight state
    -- (if we came from light toggled off to some intensity > 0).
    self:_decideFrontlightState()
end

function KoboPowerD:setIntensityHW(intensity)
    self:_stopFrontlightRamp()
    self:_setIntensityHW(intensity)
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

-- NOTE: When ramping down, we start from the *actual* intensity (hw_intensity),
--       instead of the expected one (fl_intensity),
--       in case a previously incomplete ramp was canceled and left us in an inconsistent state.
function KoboPowerD:_startRampDown(done_callback)
    self:turnOffFrontlightRamp(self.hw_intensity, self.fl_min, done_callback)
    self.fl_ramp_down_running = true
end

function KoboPowerD:_endRampDown(end_intensity, done_callback)
    self:_setIntensityHW(end_intensity)
    self.fl_ramp_down_running = false

    if done_callback then
        done_callback()
    end
end

function KoboPowerD:_stopFrontlightRamp()
    if self.fl_ramp_up_running or self.fl_ramp_down_running then
        -- Make sure we have no other ramp running.
        UIManager:unschedule(self.turnOffFrontlightRamp)
        UIManager:unschedule(self.turnOnFrontlightRamp)
        UIManager:unschedule(self._startRampDown)
        UIManager:unschedule(self._endRampDown)
        UIManager:unschedule(self._startRampUp)
        UIManager:unschedule(self._endRampUp)
        self.fl_ramp_up_running = false
        self.fl_ramp_down_running = false
    end
end

-- This will ramp down faster at high intensity values (i.e., start), and slower at lower intensity values (i.e., end).
-- That's an attempt at making the *perceived* effect appear as a more linear brightness change.
-- The whole function gets called at most log(100)/log(0.75) = 17 times,
-- leading to a 0.025*17 + 0.5 = 0.925s ramp down time (non blocking); can be aborted.
function KoboPowerD:turnOffFrontlightRamp(curr_ramp_intensity, end_intensity, done_callback)
    curr_ramp_intensity = math.floor(math.max(curr_ramp_intensity * .75, self.fl_min))

    if curr_ramp_intensity > end_intensity then
        self:_setIntensityHW(curr_ramp_intensity)
        UIManager:scheduleIn(self.device.frontlight_settings.ramp_delay, self.turnOffFrontlightRamp, self, curr_ramp_intensity, end_intensity, done_callback)
    else
        -- Some devices require delaying the final step, to prevent them from jumping straight to zero and messing up the ramp.
        UIManager:scheduleIn(self.device.frontlight_settings.ramp_off_delay, self._endRampDown, self, end_intensity, done_callback)
        -- no reschedule here, as we are done
    end
end

function KoboPowerD:turnOffFrontlightHW(done_callback)
    if not self:isFrontlightOnHW() then
        return
    end

    if UIManager then
        -- We've got nothing to do if we're already ramping down
        if not self.fl_ramp_down_running then
            self:_stopFrontlightRamp()
            -- NOTE: For devices with a ramp_off_delay, we only ramp if we start from > 2%,
            --       otherwise you just see a single delayed step (1%) or two stuttery ones (2%) ;).
            -- FWIW, modern devices with a different PWM controller (i.e., with no controller-specific ramp_off_delay workarounds)
            -- deal with our 2% ramp without stuttering.
            if self.device.frontlight_settings.ramp_off_delay > 0.0 and self.hw_intensity <= 2 then
                UIManager:scheduleIn(self.device.frontlight_settings.ramp_delay, self._endRampDown, self, self.fl_min, done_callback)
            else
                -- NOTE: Similarly, some controllers *really* don't like to be interleaved with screen refreshes,
                --       so we wait until the next UI frame for the refreshes to go through first...
                if self.device.frontlight_settings.delay_ramp_start then
                    UIManager:nextTick(self._startRampDown, self, done_callback)
                else
                    self:turnOffFrontlightRamp(self.hw_intensity, self.fl_min, done_callback)
                    self.fl_ramp_down_running = true
                end
            end
        end
    else
        -- If UIManager is not initialized yet, just turn it off immediately
        self:setIntensityHW(self.fl_min)
    end

    -- We consume done_callback ourselves, make sure Generic's PowerD gets the memo
    return true
end

function KoboPowerD:_startRampUp(done_callback)
    self:turnOnFrontlightRamp(self.fl_min, self.fl_intensity, done_callback)
    self.fl_ramp_up_running = true
end

function KoboPowerD:_endRampUp(end_intensity, done_callback)
    self:_setIntensityHW(end_intensity)
    self.fl_ramp_up_running = false

    if done_callback then
        done_callback()
    end
end

-- Similar functionality as `Kobo:turnOffFrontlightRamp`, but the other way around ;).
function KoboPowerD:turnOnFrontlightRamp(curr_ramp_intensity, end_intensity, done_callback)
    if curr_ramp_intensity == 0 then
        curr_ramp_intensity = 1
    else
        curr_ramp_intensity = math.ceil(math.min(curr_ramp_intensity * 1.5, self.fl_max))
    end

    if curr_ramp_intensity < end_intensity then
        self:_setIntensityHW(curr_ramp_intensity)
        UIManager:scheduleIn(self.device.frontlight_settings.ramp_delay, self.turnOnFrontlightRamp, self, curr_ramp_intensity, end_intensity, done_callback)
    else
        UIManager:scheduleIn(self.device.frontlight_settings.ramp_delay, self._endRampUp, self, end_intensity, done_callback)
        -- no reschedule here, as we are done
    end
end

function KoboPowerD:turnOnFrontlightHW(done_callback)
    -- NOTE: Insane workaround for the first toggle after a startup with the FL off.
    -- The light is actually off, but hw_intensity couldn't have been set to a sane value because of a number of interactions.
    -- So, fix it now, so we pass the isFrontlightOnHW check (which checks if hw_intensity > fl_min).
    if (self.is_fl_on == false and self.hw_intensity > self.fl_min and self.hw_intensity == self.fl_intensity) then
        self.hw_intensity = self.fl_min
    end
    if self:isFrontlightOnHW() then
        return
    end

    if UIManager then
        -- We've got nothing to do if we're already ramping up
        if not self.fl_ramp_up_running then
            self:_stopFrontlightRamp()
            if self.device.frontlight_settings.ramp_off_delay > 0.0 and self.fl_intensity <= 2 then
                -- NOTE: Match the ramp down behavior on devices with a ramp_off_delay: jump straight to 1 or 2% intensity.
                UIManager:scheduleIn(self.device.frontlight_settings.ramp_delay, self._endRampUp, self, self.fl_intensity, done_callback)
            else
                -- Same deal as in turnOffFrontlightHW
                if self.device.frontlight_settings.delay_ramp_start then
                    UIManager:nextTick(self._startRampUp, self, done_callback)
                else
                    self:turnOnFrontlightRamp(self.fl_min, self.fl_intensity, done_callback)
                    self.fl_ramp_up_running = true
                end
            end
        end
    else
        -- If UIManager is not initialized yet, just turn it on immediately
        self:setIntensityHW(self.fl_intensity)
    end

    -- We consume done_callback ourselves, make sure Generic's PowerD gets the memo
    return true
end

function KoboPowerD:_suspendFrontlight()
    self:turnOffFrontlight()
end

-- Turn off front light before suspend.
function KoboPowerD:beforeSuspend()
    -- Inhibit user input and emit the Suspend event.
    self.device:_beforeSuspend()

    -- Handle the frontlight last,
    -- to prevent as many things as we can from interfering with the smoothness of the ramp
    if self.fl then
        -- We only want the *last* scheduled suspend/resume frontlight task to run to avoid ramps running amok...
        UIManager:unschedule(self._suspendFrontlight)
        UIManager:unschedule(self._resumeFrontlight)
        self:_stopFrontlightRamp()

        -- Turn off the frontlight
        -- NOTE: Funky delay mainly to yield to the EPDC's refresh on UP systems.
        --       (Neither yieldToEPDC nor nextTick & friends quite cut it here)...
        UIManager:scheduleIn(0.001, self._suspendFrontlight, self)
    end
end

function KoboPowerD:_resumeFrontlight()
    -- Don't bother if the light was already off on suspend
    -- NOTE: Things gan go sideways quick when you mix the userland ramp,
    --       delays all over the place, and quick successions of suspend/resume requests (e.g., jittery sleepcovers),
    --       so trust fl_was_on over the actual state on beforeSuspend,
    --       as said state might no longer actually represent the pre-suspend reality...
    --       c.f., #12246
    -- Note that fl_was_on is updated by *interactive* callers via `BasePowerD:updateResumeFrontlightState`
    if self.fl_was_on then
        -- If the frontlight is currently on because of madness resulting from multiple concurrent suspend/resume requests,
        -- but at the wrong intensity, turn it straight off first so that turnOnFrontlight doesn't abort early...
        if self.is_fl_on and self.hw_intensity ~= self.fl_intensity then
            logger.warn("KoboPowerD:_resumeFrontlight: frontlight intensity is at", self.hw_intensity, "instead of the expected", self.fl_intensity)
            self:setIntensityHW(self.fl_min)
        end
        -- Turn the frontlight back on
        self:turnOnFrontlight()
    end
end

-- Restore front light state after resume.
function KoboPowerD:afterResume()
    -- Set the system clock to the hardware clock's time.
    RTC:HCToSys()

    self:invalidateCapacityCache()

    -- Restore user input and emit the Resume event.
    self.device:_afterResume()

    -- There's a whole bunch of stuff happening before us in Generic:onPowerEvent,
    -- so we'll delay this ever so slightly so as to appear as smooth as possible...
    if self.fl then
        -- Same reasoning as on suspend
        UIManager:unschedule(self._suspendFrontlight)
        UIManager:unschedule(self._resumeFrontlight)
        self:_stopFrontlightRamp()

        -- Turn the frontlight back on
        -- NOTE: There's quite likely *more* resource contention than on suspend here :/.
        UIManager:scheduleIn(0.001, self._resumeFrontlight, self)
    end
end

function KoboPowerD:UIManagerReadyHW(uimgr)
    UIManager = uimgr
end

return KoboPowerD
