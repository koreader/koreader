local BasePowerD = require("device/generic/powerd")
local ffi = require("ffi")
local inkview = ffi.load("inkview")

ffi.cdef[[
int IsCharging();
]]

local PocketBookPowerD = BasePowerD:new{
    battCapacity = nil,
    is_charging = nil,
    batt_capacity_file = "/sys/devices/platform/sun5i-i2c.0/i2c-0/0-0034/axp20-supplyer.28/power_supply/battery/capacity",
    is_charging_file = "/sys/devices/platform/sun5i-i2c.0/i2c-0/0-0034/axp20-supplyer.28/power_supply/battery/status",
}

function PocketBookPowerD:init()
end

function PocketBookPowerD:getCapacityHW()
    self.battCapacity = self:read_int_file(self.batt_capacity_file)
    return self.battCapacity
end

function PocketBookPowerD:isChargingHW()
    self.is_charging = self:read_str_file(self.is_charging_file)
    return self.is_charging == "Charging"
    -- or we can query using SDK method `IsCharging`
    --return inkview.IsCharging() == 1
end

return PocketBookPowerD
