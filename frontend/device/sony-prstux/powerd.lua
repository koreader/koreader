local BasePowerD = require("device/generic/powerd")

local base_path = '/sys/devices/platform/imx-i2c.1/i2c-1/1-0049/twl6030_bci/power_supply/twl6030_battery/'

local SonyPRSTUX_PowerD = BasePowerD:new{
    is_charging = nil,
    fl_min = 0,
    fl_max = 100,
    capacity_file = base_path .. 'capacity',
    status_file = base_path .. 'status'
}

function SonyPRSTUX_PowerD:init()
end

function SonyPRSTUX_PowerD:frontlightIntensityHW()
    if not self.device:hasFrontlight() then return 0 end
end

function SonyPRSTUX_PowerD:setIntensityHW(intensity)
end

function SonyPRSTUX_PowerD:getCapacityHW()
    return self:read_int_file(self.capacity_file)
end

function SonyPRSTUX_PowerD:isChargingHW()
    return self:read_str_file(self.status_file) == "Charging"
end

function SonyPRSTUX_PowerD:beforeSuspend()
    -- Inhibit user input and emit the Suspend event.
    self.device:_beforeSuspend()
end

function SonyPRSTUX_PowerD:afterResume()
    self:invalidateCapacityCache()

    -- Restore user input and emit the Resume event.
    self.device:_afterResume()
end

return SonyPRSTUX_PowerD
