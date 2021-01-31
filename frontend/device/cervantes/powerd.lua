local BasePowerD = require("device/generic/powerd")
local SysfsLight = require ("device/sysfs_light")

local battery_sysfs = "/sys/devices/platform/pmic_battery.1/power_supply/mc13892_bat/"

local CervantesPowerD = BasePowerD:new{
    fl = nil,
    fl_warmth = nil,

    fl_min = 0,
    fl_max = 100,
    fl_warmth_min = 0,
    fl_warmth_max = 100,
    capacity_file = battery_sysfs .. 'capacity',
    status_file = battery_sysfs .. 'status'
}

function CervantesPowerD:_syncLightOnStart()
    -- We can't read value from the OS or hardware.
    -- Use last values stored in koreader settings.
    local new_intensity = G_reader_settings:readSetting("frontlight_intensity") or nil
    local is_frontlight_on = G_reader_settings:readSetting("is_frontlight_on") or nil
    local new_warmth = nil

    if self.fl_warmth ~= nil then
        new_warmth = G_reader_settings:readSetting("frontlight_warmth") or nil
    end

    if new_intensity ~= nil then
        self.hw_intensity = new_intensity
    end

    if is_frontlight_on ~= nil then
        self.initial_is_fl_on = is_frontlight_on
    end

    if new_warmth ~= nil then
        self.fl_warmth = new_warmth
    end

    if self.initial_is_fl_on == false and self.hw_intensity == 0 then
        self.hw_intensity = 1
    end
end

function CervantesPowerD:init()
    -- Default values in case self:_syncLightOnStart() does not find
    -- any previously saved setting (and for unit tests where it will
    -- not be called)
    self.hw_intensity = 20
    self.initial_is_fl_on = true

    if self.device:hasFrontlight() then
        if self.device:hasNaturalLight() then
            local nl_config = G_reader_settings:readSetting("natural_light_config")
            if nl_config then
                for key,val in pairs(nl_config) do
                    self.device.frontlight_settings[key] = val
                end
            end
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
            self:_syncLightOnStart()
        else
            local kobolight = require("ffi/kobolight")
            local ok, light = pcall(kobolight.open)
            if ok then
                self.fl = light
                self:_syncLightOnStart()
            end
        end
    end
end

function CervantesPowerD:saveSettings()
    if self.device:hasFrontlight() then
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
    end
end

function CervantesPowerD:frontlightIntensityHW()
    return self.hw_intensity
end

function CervantesPowerD:isFrontlightOnHW()
    if self.initial_is_fl_on ~= nil then -- happens only once after init()
        -- give initial state to BasePowerD, which will
        -- reset our self.hw_intensity to 0 if self.initial_is_fl_on is false
        local ret = self.initial_is_fl_on
        self.initial_is_fl_on = nil
        return ret
    end
    return self.hw_intensity > 0
end

function CervantesPowerD:setIntensityHW(intensity)
    if self.fl == nil then return end
    self.fl:setBrightness(intensity)
    self.hw_intensity = intensity
    -- Now that we have set intensity, we need to let BasePowerD
    -- know about possibly changed frontlight state (if we came
    -- from light toggled off to some intensity > 0).
    self:_decideFrontlightState()
end

function CervantesPowerD:setWarmth(warmth)
    if self.fl == nil then return end
    self.fl_warmth = warmth or self.fl_warmth
    self.fl:setWarmth(self.fl_warmth)
end

function CervantesPowerD:getCapacityHW()
    return self:read_int_file(self.capacity_file)
end

function CervantesPowerD:isChargingHW()
    return self:read_str_file(self.status_file) == "Charging"
end

function CervantesPowerD:beforeSuspend()
    if self.fl == nil then return end
    -- just turn off frontlight without remembering its state
    self.fl:setBrightness(0)
end

function CervantesPowerD:afterResume()
    if self.fl == nil then return end
    -- just re-set it to self.hw_intensity that we haven't change on Suspend
    if self.fl_warmth == nil then
        self.fl:setBrightness(self.hw_intensity)
    else
        self.fl:setNaturalBrightness(self.hw_intensity, self.fl_warmth)
    end
end

return CervantesPowerD
