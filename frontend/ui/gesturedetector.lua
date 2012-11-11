require "ui/geometry"

-- Synchronization events (SYN.code).
SYN_REPORT = 0
SYN_CONFIG = 1
SYN_MT_REPORT = 2

-- For multi-touch events (ABS.code).
ABS_MT_SLOT = 47
ABS_MT_POSITION_X = 53
ABS_MT_POSITION_Y = 54
ABS_MT_TRACKING_ID = 57
ABS_MT_PRESSURE = 58

GestureRange = {
	ges = nil,
	range = nil,
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

	if self.range:contains(gs.pos) then
	DEBUG(self, gs)
		return true
	end

	return false
end

GestureDetector = {
	ev_stack = {},
	cur_ev = {},
}

--[[
MT_TRACK_ID: 0
MT_X: 310
MT_Y: 174
SYN REPORT
MT_TRACK_ID: -1
SYN REPORT

MT_TRACK_ID: 0
MT_X: 222
MT_Y: 207
SYN REPORT
MT_TRACK_ID: -1
SYN REPORT
--]]

function GestureDetector:feedEvent(ev) 
	if ev.type == EV_SYN then
		if ev.code == SYN_REPORT then
			-- end of one event or release touch?
			if self.cur_ev.id == -1 then
				-- touch release?
				return self:guessGesture()
			else
				table.insert(self.ev_stack, self.cur_ev)
				self.cur_ev = {}
				--DEBUG(self.ev_stack)
			end
		end
	elseif ev.type == EV_ABS then
		if ev.code == ABS_MT_SLOT then
		elseif ev.code == ABS_MT_TRACKING_ID then
			self.cur_ev.id = ev.value
		elseif ev.code == ABS_MT_POSITION_X then
			self.cur_ev.x = ev.value
		elseif ev.code == ABS_MT_POSITION_Y then
			self.cur_ev.y = ev.value
		end
	end
end

function GestureDetector:guessGesture()
	local is_recognized = false
	local result = nil
	local last_ev = {pos = Geom:new{}}

	for k,ev in ipairs(self.ev_stack) do
		--@TODO do real recognization here    (houqp)
		is_recognized = true
		result = {
			ges = "tap",
			pos = Geom:new{
				x = ev.x or last_ev.x,
				y = ev.y or last_ev.x,
				w = 0,
				h = 0,
			}
		}
		last_ev = ev
	end

	if is_recognized then
		self.ev_stack = {}
		return result
	else
		DEBUG("Unknown gesture!!", self.ev_stack)
		self.ev_stack = {}
	end
end


