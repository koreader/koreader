local BasePowerD = require("device/generic/powerd")

local AndroidPowerD = BasePowerD:new{
    batt_capacity_file = "/sys/class/power_supply/battery/capacity",
    is_charging_file = "/sys/class/power_supply/battery/charging_enabled",
    battCapacity = nil,
    is_charging = nil,
}

function AndroidPowerD:init()
end

function AndroidPowerD:setIntensityHW()
end

function AndroidPowerD:getCapacityHW()
    self.battCapacity = self:read_int_file(self.batt_capacity_file)
    return self.battCapacity
end

function AndroidPowerD:isChargingHW()
    self.is_charging = self:read_int_file(self.is_charging_file)
    return self.is_charging == 1
end

return AndroidPowerD
