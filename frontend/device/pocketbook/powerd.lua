local BasePowerD = require("device/generic/powerd")
local ffi = require("ffi")
local inkview = ffi.load("inkview")

ffi.cdef[[
void OpenScreen();
int GetFrontlightState(void);
void SetFrontlightState(int flstate);
]]

local PocketBookPowerD = BasePowerD:new{
    is_charging = nil,
    batt_capacity_file = "/sys/devices/platform/sun5i-i2c.0/i2c-0/0-0034/axp20-supplyer.28/power_supply/battery/capacity",
    is_charging_file = "/sys/devices/platform/sun5i-i2c.0/i2c-0/0-0034/axp20-supplyer.28/power_supply/battery/status",
}

function PocketBookPowerD:init()
-- needed for SetFrontlightState / GetFrontlightState
    inkview.OpenScreen()
end

function PocketBookPowerD:frontlightIntensityHW()
    if not self.device.hasFrontlight() then return 0 end
    local state = inkview.GetFrontlightState()
    return math.floor(state / 10)
end

function PocketBookPowerD:setIntensityHW(intensity)
    if intensity == 0 then
        inkview.SetFrontlightState(-1)
    else
        inkview.SetFrontlightState(10 * intensity)
    end
end

function PocketBookPowerD:getCapacityHW()
    return self:read_int_file(self.batt_capacity_file)
end

function PocketBookPowerD:isChargingHW()
    self.is_charging = self:read_str_file(self.is_charging_file)
    return self.is_charging == "Charging"
    -- or we can query using SDK method `IsCharging`
    --return inkview.IsCharging() == 1
end

return PocketBookPowerD
