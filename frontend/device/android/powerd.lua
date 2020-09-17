local BasePowerD = require("device/generic/powerd")
local _, android = pcall(require, "android")

local AndroidPowerD = BasePowerD:new{
    fl_min = 0,
    fl_max = 100,
}

-- Let the footer know of the change
local function broadcastLightChanges()
    if package.loaded["ui/uimanager"] ~= nil then
        local Event = require("ui/event")
        local UIManager = require("ui/uimanager")
        UIManager:broadcastEvent(Event:new("FrontlightStateChanged"))
    end
end

function AndroidPowerD:frontlightIntensityHW()
    return math.floor(android.getScreenBrightness() / self.bright_diff * self.fl_max)
end

function AndroidPowerD:setIntensityHW(intensity)
    -- if frontlight switch was toggled of, turn it on
    android.enableFrontlightSwitch()

    self.fl_intensity = intensity
    android.setScreenBrightness(math.floor(intensity * self.bright_diff / self.fl_max))
end

function AndroidPowerD:init()
    local min_bright = android.getScreenMinBrightness()
    self.bright_diff = android.getScreenMaxBrightness() - min_bright

    -- if necessary scale fl_min:
    --    do not use fl_min==0 if getScreenMinBrightness!=0,
    --    because intenstiy==0 would mean to use system intensity
    if min_bright ~= self.fl_min then
        self.fl_min = math.ceil(min_bright * self.bright_diff / self.fl_max)
    end

    if self.device:hasNaturalLight() then
        self.fl_warmth_min = android.getScreenMinWarmth()
        self.fl_warmth_max = android.getScreenMaxWarmth()
        self.warm_diff = self.fl_warmth_max - self.fl_warmth_min
        self.fl_warmth = self:getWarmth()
    end
end

function AndroidPowerD:setWarmth(warmth)
    self.fl_warmth = warmth
    android.setScreenWarmth(warmth / self.warm_diff)
end

function AndroidPowerD:getWarmth()
    return android.getScreenWarmth() * self.warm_diff
end

function AndroidPowerD:getCapacityHW()
    return android.getBatteryLevel()
end

function AndroidPowerD:isChargingHW()
    return android.isCharging()
end

function AndroidPowerD:turnOffFrontlightHW()
    if not self:isFrontlightOnHW() then
        return
    end
    android.setScreenBrightness(self.fl_min)
    self.is_fl_on = false
    broadcastLightChanges()
end

function AndroidPowerD:turnOnFrontlightHW()
    if self:isFrontlightOn() and self:isFrontlightOnHW() then
        return
    end
    -- on devices with a software frontlight switch (e.g Tolinos), enable it
    android.enableFrontlightSwitch()

    android.setScreenBrightness(math.floor(self.fl_intensity * self.bright_diff / self.fl_max))

    self.is_fl_on = true
    broadcastLightChanges()
end

return AndroidPowerD
