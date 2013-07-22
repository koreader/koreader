require "ui/device"

ReaderFrontLight = InputContainer:new{
	steps = {0,1,2,3,4,5,6,7,8,9,10},
	intensity = nil,
}

function ReaderFrontLight:init()
	local dev_mod = Device:getModel()
	if dev_mod == "KindlePaperWhite" then
		require "liblipclua"
		self.lipc_handle = lipc.init("com.github.koreader")
		if self.lipc_handle then
			self.intensity = self.lipc_handle:get_int_property("com.lab126.powerd", "flIntensity")
		end
	end
	self.ges_events = {
		Adjust = {
			GestureRange:new{
				ges = "two_finger_pan",
				range = Geom:new{
					x = 0, y = 0,
					w = Screen:getWidth(),
					h = Screen:getHeight(),
				},
				rate = 2.0,
			}
		},
	}
end

function ReaderFrontLight:onAdjust(arg, ges)
	if self.lipc_handle and self.intensity ~=nil then
		local rel_proportion = ges.distance / Screen:getWidth()
		local delta_int = self.steps[math.ceil(#self.steps*rel_proportion)] or self.steps[#self.steps]
		local msg = ""
		if ges.direction == "north" then
			msg = _("Increase front light intensity to ")
			self.intensity = self.intensity + delta_int
			self:setIntensity(self.intensity, msg)
		elseif ges.direction == "south" then
			msg = _("Decrease front light intensity to ")
			self.intensity = self.intensity - delta_int
			self:setIntensity(self.intensity, msg)
		end
	end
	return true
end

function ReaderFrontLight:setIntensity(intensity, msg)
	if self.lipc_handle then 
		intensity = intensity < 0 and 0 or intensity
		intensity = intensity > 24 and 24 or intensity
		self.intensity = intensity
		self.lipc_handle:set_int_property("com.lab126.powerd", "flIntensity", intensity)
		UIManager:show(Notification:new{
			text = msg..intensity,
			timeout = 1
		})
	end
	return true
end
