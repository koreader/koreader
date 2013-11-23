local BaseFrontLight = require("ui/device/basefrontlight")
-- liblipclua, see require below

local KindleFrontLight = {
	min = 0, max = 24,
	-- FIXME: Check how to handle this on the PW2, initial reports on IRC suggest that this isn't possible anymore
	kpw_fl = "/sys/devices/system/fl_tps6116x/fl_tps6116x0/fl_intensity",
	intensity = nil,
	lipc_handle = nil,
}

function KindleFrontLight:init()
	require "liblipclua"
	self.lipc_handle = lipc.init("com.github.koreader")
	if self.lipc_handle then
		self.intensity = self.lipc_handle:get_int_property("com.lab126.powerd", "flIntensity")
	end
end

function KindleFrontLight:toggle()
	local f =  io.open(self.kpw_fl, "r")
	local sysint = tonumber(f:read("*all"):match("%d+"))
	f:close()
	if sysint == 0 then
		self:setIntensity(self.intensity)
	else
		os.execute("echo -n 0 > " .. self.kpw_fl)
	end
end

KindleFrontLight.setIntensity = BaseFrontLight.setIntensity

function KindleFrontLight:setIntensityHW()
	if self.lipc_handle ~= nil then
		self.lipc_handle:set_int_property("com.lab126.powerd", "flIntensity", self.intensity)
	end
end

return KindleFrontLight
