local BasePowerD = require("device/generic/powerd")
local _, android = pcall(require, "android")

local AndroidPowerD = BasePowerD:new{
    fl_min = 0, fl_max = 25,
    fl_intensity = 10,
    batt_capacity_file = "/sys/class/power_supply/battery/capacity",
    is_charging_file = "/sys/class/power_supply/battery/charging_enabled",
    battCapacity = nil,
    is_charging = nil,
}

function AndroidPowerD:init()
end

function AndroidPowerD:setIntensityHW()
    android.setScreenBrightness(math.floor(255 * self.fl_intensity / 25))
end

function AndroidPowerD:getCapacityHW()
    self.battCapacity = android.getBatteryLevel()
    return self.battCapacity
end

function AndroidPowerD:isChargingHW()
    self.is_charging = android.isCharging()
    return self.is_charging
end

return AndroidPowerD
