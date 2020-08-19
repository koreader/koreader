local BasePowerD = require("device/generic/powerd")
local _, android = pcall(require, "android")

local AndroidPowerD = BasePowerD:new{
    fl_min = 0,
    fl_max = 100,
}

function AndroidPowerD:frontlightIntensityHW()
    return math.floor(android.getScreenBrightness() / self.bright_diff * self.fl_max)
end

function AndroidPowerD:setIntensityHW(intensity)
    self.fl_intensity = intensity
    android.setScreenBrightness(math.floor(intensity * self.bright_diff / self.fl_max))
end

function AndroidPowerD:init()
    self.bright_diff = android:getScreenMaxBrightness() - android:getScreenMinBrightness()
    
    -- if necessary scale fl_min:
    --    do not use fl_min==0 if getScreenMinBrightness!=0, 
    --    because intenstiy==0 would mean to use system intensity 
    if android:getScreenMinBrightness() ~= self.fl_min then
        self.fl_min = math.ceil(android:getScreenMinBrightness() * self.bright_diff /self.fl_max)
    end
    
    if self.device:hasNaturalLight() then
        self.warm_diff = android:getScreenMaxWarmth() - android:getScreenMinWarmth()
        self.fl_warmth = self:getWarmth()
        self.fl_warmth_min = android:getScreenMinWarmth()
        self.fl_warmth_max = android:getScreenMaxWarmth()
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

    android.setScreenBrightness(math.floor( self.fl_min))

    self.is_fl_on = false
    -- And let the footer know of the change
    if package.loaded["ui/uimanager"] ~= nil then
        local Event = require("ui/event")
        local UIManager = require("ui/uimanager")
        UIManager:broadcastEvent(Event:new("FrontlightStateChanged"))
    end
end

function AndroidPowerD:turnOnFrontlightHW()
    local logger = require("logger")
    logger.err("self.fl_intensity= " .. self.fl_intensity)
    if self:isFrontlightOn() and self:isFrontlightOnHW() then
        logger.err("isFrontlightOnHW() = true")
        return
    end
    android.setScreenBrightness(math.floor(self.fl_intensity * self.bright_diff / self.fl_max))

    self.is_fl_on = true
    -- And let the footer know of the change
    if package.loaded["ui/uimanager"] ~= nil then
        local Event = require("ui/event")
        local UIManager = require("ui/uimanager")
        UIManager:broadcastEvent(Event:new("FrontlightStateChanged"))
    end
end

return AndroidPowerD
