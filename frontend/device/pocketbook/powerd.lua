local BasePowerD = require("device/generic/powerd")
local ffi = require("ffi")
local inkview = ffi.load("inkview")
local logger = require("logger")

local PocketBookPowerD = BasePowerD:new{
    is_charging = nil,

    fl_min = 0,
    fl_max = 100,
    fl_warmth_min = 0,
    fl_warmth_max = 100,
}

function PocketBookPowerD:frontlightIntensityHW()
    -- Always update fl_intensity (and perhaps fl_warmth) from the OS value whenever queried (it's fast).
    -- This way koreader settings can stay in sync even if the value is changed behind its back.
    self.fl_intensity = math.max(0, inkview.GetFrontlightState())
    if self.device:hasNaturalLight() then
        self.fl_warmth = math.max(0, inkview.GetFrontlightColor())
    end
    return self.fl_intensity
end

function PocketBookPowerD:frontlightIntensity()
    if not self.device:hasFrontlight() then return 0 end
    if self:isFrontlightOff() then return 0 end
    --- @note: We actually have a working frontlightIntensityHW implementation,
    ---        use it instead of returning a cached self.fl_intensity like BasePowerD.
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

    -- We have a custom isFrontlightOn implementation, so this is redundant
    self:_decideFrontlightState()
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

function PocketBookPowerD:setWarmthHW(level)
    return inkview.SetFrontlightColor(level)
end

function PocketBookPowerD:frontlightWarmthHW()
    return inkview.GetFrontlightColor()
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

function PocketBookPowerD:beforeSuspend()
    -- Inhibit user input and emit the Suspend event.
    self.device:_beforeSuspend()
end

function PocketBookPowerD:afterResume()
    self:invalidateCapacityCache()

    -- Restore user input and emit the Resume event.
    self.device:_afterResume()

    -- PB700 / PBEraColor: Sync orientation after resume to fix hibernation rotation bug
    -- c.f., https://github.com/koreader/koreader/issues/11033
    if self.device.model == "PB700" or self.device.model == "PBEraColor" then
        logger.dbg("afterResume: Running orientation sync for PB700 / PBEraColor")

        local current_orientation = inkview.GetGSensorOrientation()
        local current_rotation = self.device.screen:getRotationMode()

        -- Without this we end up with inverted screen orientation after resume
        inkview.iv_update_orientation(current_orientation)

        local gyro_value = self.device.input.input.translateInkViewOrientation(current_orientation)
        logger.dbg("afterResume: GSensor:", current_orientation, "Current:", current_rotation, "Target:", gyro_value)

        -- Create a synthetic MSC_GYRO event and let the existing handler process it
        local synthetic_event = { value = gyro_value }
        local Event = self.device.input:handleMiscGyroEv(synthetic_event)

        if Event then
            local UIManager = require("ui/uimanager")
            UIManager:sendEvent(Event)
        end
    end
end

return PocketBookPowerD
