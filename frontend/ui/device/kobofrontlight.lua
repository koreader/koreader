local BaseFrontLight = require("ui/device/basefrontlight")

local KoboFrontLight = BaseFrontLight:new{
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

function KoboFrontLight:setIntensityHW()
	if self.fl ~= nil then
		self.fl:setBrightness(self.intensity)
	end
end

return KoboFrontLight
