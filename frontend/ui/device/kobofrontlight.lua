local BaseFrontLight = require("ui/device/basefrontlight")

local KoboFrontLight = {
	min = 1, max = 100,
	intensity = 20,
	restore_settings = true,
	fl = nil,
}

function KoboFrontLight:init()
	self.fl = kobolight.open()
end

function KoboFrontLight:toggle()
	if self.fl ~= nil then
		self.fl:toggle()
	end
end

KoboFrontLight.setIntensity = BaseFrontLight.setIntensity

function KoboFrontLight:setIntensityHW()
	if self.fl ~= nil then
		self.fl:setBrightness(self.intensity)
	end
end

return KoboFrontLight
