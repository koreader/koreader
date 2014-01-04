local BasePowerD = require("ui/device/basepowerd")

local KoboPowerD = BasePowerD:new{
	fl_min = 1, fl_max = 100,
	flIntensity = 20,
	restore_settings = true,
	fl = nil,
}

function KoboPowerD:init()
	self.fl = kobolight.open()
end

function KoboPowerD:toggleFrontlight()
	if self.fl ~= nil then
		self.fl:toggle()
	end
end

function KoboPowerD:setIntensityHW()
	if self.fl ~= nil then
		self.fl:setBrightness(self.flIntensity)
	end
end

return KoboPowerD
