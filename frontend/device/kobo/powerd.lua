local BasePowerD = require("device/generic/powerd")
local NickelConf = require("device/kobo/nickel_conf")

local batt_state_folder =
        "/sys/devices/platform/pmic_battery.1/power_supply/mc13892_bat/"

local KoboPowerD = BasePowerD:new{
    -- Do not actively set front light to 0, it may confuse users -- pressing
    -- hardware button won't take any effect.
    fl_min = 1, fl_max = 100,
    fl = nil,

    batt_capacity_file = batt_state_folder .. "capacity",
    is_charging_file = batt_state_folder .. "status",
}

-- TODO: Remove KOBO_LIGHT_ON_START
function KoboPowerD:_syncKoboLightOnStart()
    local kobo_light_on_start = tonumber(KOBO_LIGHT_ON_START)
    if kobo_light_on_start then
        local new_intensity
        local is_frontlight_on
        if kobo_light_on_start > 0 then
            new_intensity = math.min(kobo_light_on_start, 100)
            is_frontlight_on = true
        elseif kobo_light_on_start == 0 then
            new_intensity = 0
            is_frontlight_on = false
        elseif kobo_light_on_start == -2 then
            return
        else -- if kobo_light_on_start == -1 or other unexpected value then
            -- TODO(Hzj-jie): Read current frontlight states from OS.
            return
        end
        NickelConf.frontLightLevel.set(new_intensity)
        NickelConf.frontLightState.set(is_frontlight_on)
    end
end

function KoboPowerD:init()
    if self.device.hasFrontlight() then
        local kobolight = require("ffi/kobolight")
        local ok, light = pcall(kobolight.open)
        if ok then
            self.fl = light
            self:_syncKoboLightOnStart()
        end
    end
end

function KoboPowerD:_syncIntensity(intensity)
    if NickelConf.frontLightLevel.get() ~= intensity then
        NickelConf.frontLightLevel.set(intensity)
    end
end

function KoboPowerD:_syncNickelConf()
    if not KOBO_SYNC_BRIGHTNESS_WITH_NICKEL then return end
    if NickelConf.frontLightState.get() == nil then
        self:_syncIntensity(self:frontlightIntensity())
    else
        if NickelConf.frontLightState.get() ~= self:isFrontlightOn() then
            NickelConf.frontLightState.set(self:isFrontlightOn())
        end
        self:_syncIntensity(self.fl_intensity)
    end
end

function KoboPowerD:frontlightIntensityHW()
    return NickelConf.frontLightLevel.get()
end

function KoboPowerD:isFrontlightOnHW()
    local result = NickelConf.frontLightState.get()
    if result == nil then
        return self.fl_intensity > 0
    end
    return result
end

function KoboPowerD:turnOffFrontlightHW() self:_setIntensity(0) end

function KoboPowerD:setIntensityHW(intensity)
    if self.fl == nil then return end
    self.fl:setBrightness(intensity)
    self:_syncNickelConf()
end

function KoboPowerD:getCapacityHW()
    return self:read_int_file(self.batt_capacity_file)
end

function KoboPowerD:isChargingHW()
    return self:read_str_file(self.is_charging_file) == "Charging\n"
end

-- Turn off front light before suspend.
function KoboPowerD:beforeSuspend()
    self:turnOffFrontlightHW()
end

-- Restore front light state after resume.
function KoboPowerD:afterResume()
    if KOBO_LIGHT_ON_START and tonumber(KOBO_LIGHT_ON_START) > -1 then
        self:setIntensity(math.min(KOBO_LIGHT_ON_START, 100))
    elseif self:isFrontlightOn() then
        self:turnOnFrontlightHW()
    end
end

return KoboPowerD
