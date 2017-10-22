local BasePowerD = require("device/generic/powerd")
local ffi = require("ffi")
local inkview = ffi.load("inkview")

ffi.cdef[[
void OpenScreen();
int GetFrontlightState(void);
void SetFrontlightState(int flstate);
int GetBatteryPower();
int IsCharging();
]]

local PocketBookPowerD = BasePowerD:new{
    is_charging = nil,
    fl_min = 0,
    fl_max = 100,
}

function PocketBookPowerD:init()
    -- needed for SetFrontlightState / GetFrontlightState
    inkview.OpenScreen()
end

function PocketBookPowerD:frontlightIntensityHW()
    if not self.device.hasFrontlight() then return 0 end
    return inkview.GetFrontlightState()
end

function PocketBookPowerD:setIntensityHW(intensity)
    if intensity == 0 then
        inkview.SetFrontlightState(-1)
    else
        inkview.SetFrontlightState(intensity)
    end
end

function PocketBookPowerD:getCapacityHW()
    return inkview.GetBatteryPower()
end

function PocketBookPowerD:isChargingHW()
    if inkview.IsCharging() > 0 then
        return true
    else
        return false
    end
end

return PocketBookPowerD
