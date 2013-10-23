local TimeVal = require("ui/timeval")

local GestureRange = {
	ges = nil,
	-- spatial range limits the gesture emitting position
	range = nil,
	-- temproal range limits the gesture emitting rate
	rate = nil,
	-- span limits of this gesture
	scale = nil,
}

function GestureRange:new(o)
	local o = o or {}
	setmetatable(o, self)
	self.__index = self
	return o
end

function GestureRange:match(gs)
	if gs.ges ~= self.ges then
		return false
	end
	if self.range then
		if not self.range:contains(gs.pos) then
			return false
		end
	end
	if self.rate then
		local last_time = self.last_time or TimeVal:new{}
		if gs.time - last_time > TimeVal:new{usec = 1000000 / self.rate} then
			self.last_time = gs.time
		else
			return false
		end
	end
	if self.scale then
		if self.scale[1] > gs.span or self.scale[2] < gs.span then
			return false
		end
	end
	return true
end

return GestureRange
