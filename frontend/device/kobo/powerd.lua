local BasePowerD = require("device/generic/powerd")
local NickelConf = require("device/kobo/nickel_conf")

local batt_state_folder =
        "/sys/devices/platform/pmic_battery.1/power_supply/mc13892_bat/"

local KoboPowerD = BasePowerD:new{
    -- Do not actively set front light to 0, it may confuse users -- pressing
    -- hardware button won't take any effect.
    fl_min = 1, fl_max = 100,
    flIntensity = 20,
    restore_settings = true,
    fl = nil,

    flState = false,
    batt_capacity_file = batt_state_folder .. "capacity",
    is_charging_file = batt_state_folder .. "status",
    battCapacity = nil,
    is_charging = nil,
}

function KoboPowerD:init()
    if self.device.hasFrontlight() then
        local kobolight = require("ffi/kobolight")
        local ok, light = pcall(kobolight.open)
        if ok then self.fl = light end
    end
end

function KoboPowerD:toggleFrontlight()
    if self.fl ~= nil then
        if self.flState then
            self.fl:setBrightness(0)
        else
            self.fl:setBrightness(self.flIntensity)
        end
        self.flState = not self.flState
        if KOBO_SYNC_BRIGHTNESS_WITH_NICKEL then
            NickelConf.frontLightState.set(self.flState)
        end
    end
end

function KoboPowerD:setIntensityHW()
    if self.fl ~= nil then
        self.fl:setBrightness(self.flIntensity)
        if KOBO_SYNC_BRIGHTNESS_WITH_NICKEL then
            NickelConf.frontLightLevel.set(self.flIntensity)
        end
    end
end

function KoboPowerD:getCapacityHW()
    self.battCapacity = self:read_int_file(self.batt_capacity_file)
    return self.battCapacity
end

function KoboPowerD:isChargingHW()
    self.is_charging = self:read_str_file(self.is_charging_file) == "Charging\n"
    return self.is_charging
end

-- Turn off front light before suspend.
function KoboPowerD:beforeSuspend()
    if self.fl ~= nil then
        self.fl:setBrightness(0)
    end
end

-- Restore front light state after resume.
function KoboPowerD:afterResume()
    if self.fl ~= nil then
        if KOBO_LIGHT_ON_START and tonumber(KOBO_LIGHT_ON_START) > -1 then
            self:setIntensity(math.min(KOBO_LIGHT_ON_START, 100))
        else
            self.fl:setBrightness(self.flIntensity)
        end
    end
end

return KoboPowerD
