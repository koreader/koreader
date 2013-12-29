local BaseFrontLight = {
	min = 1, max = 10,
	intensity = nil,
}

function BaseFrontLight:new(o)
	local o = o or {}
	setmetatable(o, self)
	self.__index = self
	if o.init then o:init() end
	return o
end

function BaseFrontLight:init() end
function BaseFrontLight:toggle() end
function BaseFrontLight:setIntensityHW() end

function BaseFrontLight:setIntensity(intensity)
	intensity = intensity < self.min and self.min or intensity
	intensity = intensity > self.max and self.max or intensity
	self.intensity = intensity
	self:setIntensityHW()
end

return BaseFrontLight
