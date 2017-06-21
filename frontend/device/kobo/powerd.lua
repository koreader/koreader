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

function KoboPowerD:init()
    if self.device.hasFrontlight() then
        local kobolight = require("ffi/kobolight")
        local ok, light = pcall(kobolight.open)
        if ok then
            self.fl = light
            if NickelConf.frontLightState.get() ~= nil then
                self.has_fl_state_cfg = true
            else
                self.has_fl_state_cfg = false
            end
        end
    end
end

function KoboPowerD:_syncNickelConf()
    if self.has_fl_state_cfg and KOBO_SYNC_BRIGHTNESS_WITH_NICKEL then
        NickelConf.frontLightState.set(self:isFrontlightOn())
        NickelConf.frontLightLevel.set(self:frontlightIntensity())
    end
end

function KoboPowerD:frontlightIntensityHW()
    if self.has_fl_state_cfg then
        return NickelConf.frontLightLevel.get()
    end
    return 20
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
