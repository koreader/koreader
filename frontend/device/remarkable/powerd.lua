local BasePowerD = require("device/generic/powerd")

local Remarkable_PowerD = BasePowerD:new{
    is_charging = nil,
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
    return self:read_str_file(self.status_file) == "Charging"
end

return Remarkable_PowerD
