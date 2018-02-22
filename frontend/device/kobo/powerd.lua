local BasePowerD = require("device/generic/powerd")
local NickelConf = require("device/kobo/nickel_conf")
local SysfsLight = require ("device/kobo/sysfs_light")

local batt_state_folder =
        "/sys/devices/platform/pmic_battery.1/power_supply/mc13892_bat/"

-- Here, we only deal with the real hw intensity.
-- Dealing with toggling and remembering/restoring
-- previous intensity when toggling/untoggling is done
-- by BasePowerD.

local KoboPowerD = BasePowerD:new{
    fl_min = 0, fl_max = 100,
    fl = nil,

    batt_capacity_file = batt_state_folder .. "capacity",
    is_charging_file = batt_state_folder .. "status",
    fl_warmth = nil,
}

-- TODO: Remove KOBO_LIGHT_ON_START
function KoboPowerD:_syncKoboLightOnStart()
    local new_intensity = nil
    local is_frontlight_on = nil
    local new_warmth = nil
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
                    -- ColorSetting is in [1500,6400], with '1500'
                    -- being maximum warmth, so normalize this to [0,100]
                    new_warmth = (100 - math.floor((new_color - 1500) / 49))
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
    -- Default values in case self:_syncKoboLightOnStart() does not find
    -- any previously saved setting (and for unit tests where it will
    -- not be called)
    self.hw_intensity = 20
    self.initial_is_fl_on = true

    if self.device.hasFrontlight() then
        -- If this device has natural light (currently only KA1)
        -- use the SysFS interface, and ioctl otherwise.
        if self.device.hasNaturalLight() then
            self.fl = SysfsLight
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
    end
end

function KoboPowerD:saveSettings()
    if self.device.hasFrontlight() then
        -- Store BasePowerD values into settings (and not our hw_intensity, so
        -- that if frontlight was toggled off, we save and restore the previous
        -- untoggled intensity and toggle state at next startup)
        local cur_intensity = self.fl_intensity
        local cur_is_fl_on = self.is_fl_on
        local cur_warmth = self.fl_warmth
        -- Save intensity to koreader settings
        G_reader_settings:saveSetting("frontlight_intensity", cur_intensity)
        G_reader_settings:saveSetting("is_frontlight_on", cur_is_fl_on)
        if cur_warmth ~= nil then
            G_reader_settings:saveSetting("frontlight_warmth", cur_warmth)
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

function KoboPowerD:turnOffFrontlightHW()
    self:_setIntensity(0) -- will call setIntensityHW(0)
end

function KoboPowerD:setIntensityHW(intensity)
    if self.fl == nil then return end
    if self.fl_warmth == nil then
        self.fl:setBrightness(intensity)
    else
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
    self.fl_warmth = warmth
    self.fl:setWarmth(warmth)
end

function KoboPowerD:getCapacityHW()
    return self:read_int_file(self.batt_capacity_file)
end

function KoboPowerD:isChargingHW()
    return self:read_str_file(self.is_charging_file) == "Charging\n"
end

-- Turn off front light before suspend.
function KoboPowerD:beforeSuspend()
    if self.fl == nil then return end
    -- just turn off frontlight without remembering its state
    self.fl:setBrightness(0)
end

-- Restore front light state after resume.
function KoboPowerD:afterResume()
    if self.fl == nil then return end
    -- just re-set it to self.hw_intensity that we haven't change on Suspend
    if self.fl_warmth == nil then
        self.fl:setBrightness(self.hw_intensity)
    else
        self.fl:setNaturalBrightness(self.hw_intensity, self.fl_warmth)
    end
end

return KoboPowerD
