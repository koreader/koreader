local BaseFrontLight = {
	min = 1, max = 10,
	intensity = nil,
}

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
