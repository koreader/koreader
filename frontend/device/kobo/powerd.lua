local BasePowerD = require("device/generic/powerd")
local NickelConf = require("device/kobo/nickel_conf")

local KoboPowerD = BasePowerD:new{
    fl_min = 0, fl_max = 99,
    flIntensity = 20,
    restore_settings = true,
    fl = nil,

    flState = false,
    batt_capacity_file = "/sys/devices/platform/pmic_battery.1/power_supply/mc13892_bat/capacity",
    is_charging_file = "/sys/devices/platform/pmic_battery.1/power_supply/mc13892_bat/status",
    battCapacity = nil,
    is_charging = nil,
}

function KoboPowerD:front_light_intensity() return self.flIntensity + 1 end

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
            self.fl:setBrightness(self.front_light_intensity())
        end
        self.flState = not self.flState
        if KOBO_SYNC_BRIGHTNESS_WITH_NICKEL then
            NickelConf.frontLightState.set(self.flState)
        end
    end
end

function KoboPowerD:setIntensityHW()
    if self.fl ~= nil then
        self.fl:setBrightness(self.front_light_intensity())
        if KOBO_SYNC_BRIGHTNESS_WITH_NICKEL then
            NickelConf.frontLightLevel.set(self.front_light_intensity())
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

return KoboPowerD
