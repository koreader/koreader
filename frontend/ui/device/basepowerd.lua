local BasePowerD = {
	fl_min = 0,      -- min frontlight intensity
	fl_max = 10,     -- max frontlight intensity
	flIntensity = nil,   -- frontlight intensity
	battCapacity = nil,  -- battery capacity
	model = nil   -- device model
}

function BasePowerD:new(o)
	local o = o or {}
	setmetatable(o, self)
	self.__index = self
	if o.init then o:init() end
	return o
end

function BasePowerD:init() end
function BasePowerD:toggleFrontlight() end
function BasePowerD:setIntensityHW() end
function BasePowerD:getCapacityHW() end
function BasePowerD:isChargingHW() end
function BasePowerD:suspendHW() end
function BasePowerD:wakeUpHW() end

function BasePowerD:read_int_file(file)
	local f =  io.open(file, "r")
	local sysint = tonumber(f:read("*all"):match("%d+"))
	f:close()
	return sysint
end

function BasePowerD:setIntensity(intensity)
	intensity = intensity < self.fl_min and self.fl_min or intensity
	intensity = intensity > self.fl_max and self.fl_max or intensity
	self.flIntensity = intensity
	self:setIntensityHW()
end

function BasePowerD:getCapacity()
	return self:getCapacityHW()
end

function BasePowerD:isCharging()
	return self:isChargingHW()
end

function BasePowerD:suspend()
	return self:suspendHW()
end

function BasePowerD:wakeUp()
	return self:wakeUpHW()
end

return BasePowerD
