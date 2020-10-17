local BasePowerD = require("device/generic/powerd")
local ffi = require("ffi")
local inkview = ffi.load("inkview")

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
    if self.device:hasNaturalLight() then
        local color = inkview.GetFrontlightColor()
        self.fl_warmth = color >= 0 and color or 0
    end
end

function PocketBookPowerD:frontlightIntensityHW()
    -- Always update fl_intensity (and perhaps fl_warmth) from the OS value whenever queried (its fast).
    -- This way koreader setting can stay in sync even if the value is changed behind its back.
    self.fl_intensity = math.max(0, inkview.GetFrontlightState())
    if self.fl_warmth then
        self.fl_warmth = math.max(0, inkview.GetFrontlightColor())
    end
    return self.fl_intensity
end

function PocketBookPowerD:frontlightIntensity()
    if not self.device:hasFrontlight() then return 0 end
    if self:isFrontlightOff() then return 0 end
    return self:frontlightIntensityHW()
end

function PocketBookPowerD:setIntensityHW(intensity)
    local v2api = pcall(function()
        inkview.SetFrontlightEnabled(intensity == 0 and 0 or 1)
    end)
    if intensity == 0 then
        -- -1 is valid only for the old api, on newer firmwares that's just a bogus brightness level
        if not v2api then
            inkview.SetFrontlightState(-1)
        end
    else
        inkview.SetFrontlightState(intensity)
    end
end

function PocketBookPowerD:isFrontlightOn()
    if not self.device:hasFrontlight() then return false end
    -- Query directly instead of assuming from cached value.
    local enabled = inkview.GetFrontlightState() >= 0
    pcall(function()
        enabled = inkview.GetFrontlightEnabled() > 0
    end)
    return enabled
end

function PocketBookPowerD:setWarmth(level)
    if self.fl_warmth then
        self.fl_warmth = level or self.fl_warmth
        inkview.SetFrontlightColor(self.fl_warmth)
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
