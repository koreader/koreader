local BasePowerD = require("ui/device/basepowerd")

local KoboPowerD = BasePowerD:new{
    fl_min = 1, fl_max = 100,
    flIntensity = 20,
    restore_settings = true,
    fl = nil,
    
    batt_capacity_file = "/sys/devices/platform/pmic_battery.1/power_supply/mc13892_bat/capacity",
    is_charging_file = "/sys/devices/platform/pmic_battery.1/power_supply/mc13892_bat/charge_now",
    battCapacity = nil,
    is_charging = nil,
}

function KoboPowerD:init()
    self.fl = kobolight.open()
end

function KoboPowerD:toggleFrontlight()
    if self.fl ~= nil then
        self.fl:toggle()
    end
end

function KoboPowerD:setIntensityHW()
    if self.fl ~= nil then
        self.fl:setBrightness(self.flIntensity)
    end
end

function KoboPowerD:setIntensitySW()
    if self.fl ~= nil then
        self.fl:restoreBrightness(self.flIntensity)
    end
end


function KoboPowerD:getCapacityHW()
    self.battCapacity = self:read_int_file(self.batt_capacity_file)
    return self.battCapacity
end

function KoboPowerD:isChargingHW()
    self.is_charging = self:read_int_file(self.is_charging_file)
    return self.is_charging == 1
end

return KoboPowerD
