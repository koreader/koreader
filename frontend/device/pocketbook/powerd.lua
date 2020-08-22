local BasePowerD = require("device/generic/powerd")
local ffi = require("ffi")
local inkview = ffi.load("inkview")

ffi.cdef[[
void OpenScreen();
int GetFrontlightState(void);
int GetFrontlightColor(void);
void SetFrontlightState(int flstate);
void SetFrontlightColor(int color);
int GetBatteryPower();
int IsCharging();
]]

local PocketBookPowerD = BasePowerD:new{
    is_charging = nil,
    fl_warmth = nil,

    fl_min = 0,
    fl_max = 100,
    fl_warmth_min = 0,
    fl_warmth_max = 100,
}

function PocketBookPowerD:init()
    -- needed for SetFrontlightState / GetFrontlightState
    inkview.OpenScreen()
    local color = inkview.GetFrontlightColor()
    self.fl_warmth = color >= 0 and color or 0
end

function PocketBookPowerD:frontlightIntensityHW()
    if not self.device:hasFrontlight() then return 0 end
    return inkview.GetFrontlightState()
end

function PocketBookPowerD:setIntensityHW(intensity)
    if intensity == 0 then
        inkview.SetFrontlightState(-1)
    else
        inkview.SetFrontlightState(intensity)
    end
end

function PocketBookPowerD:setWarmth(level)
    self.fl_warmth = level or self.fl_warmth
    inkview.SetFrontlightColor(self.fl_warmth)
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
