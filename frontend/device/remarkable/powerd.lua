local BasePowerD = require("device/generic/powerd")

-- TODO older firmware doesn't have the -0 on the end of the file path
local base_path = '/sys/class/power_supply/bq27441-0/'

local Remarkable_PowerD = BasePowerD:new{
    is_charging = nil,
    capacity_file = base_path .. 'capacity',
    status_file = base_path .. 'status'
}

function Remarkable_PowerD:init()
end

function Remarkable_PowerD:frontlightIntensityHW()
    return 0
end

function Remarkable_PowerD:setIntensityHW(intensity)
end

function Remarkable_PowerD:getCapacityHW()
    return self:read_int_file(self.capacity_file)
end

function Remarkable_PowerD:isChargingHW()
    return self:read_str_file(self.status_file) == "Charging\n"
end

return Remarkable_PowerD
