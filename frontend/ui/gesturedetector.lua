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

GestureDetector = {
	track_id = {},
	ev_stack = {},
	cur_ev = {},
	state = function(self) 
		self.state = self.initialState
	end,
}

function GestureDetector:feedEvent(ev) 
	if ev.type == EV_SYN then
		if ev.code == SYN_REPORT then
			local re = self.state(self, self.cur_ev)
			if re ~= nil then
				return re
			end
			self.cur_ev = {}
		end
	elseif ev.type == EV_ABS then
		if ev.code == ABS_MT_SLOT then
			self.cur_ev.slot = ev.value
		elseif ev.code == ABS_MT_TRACKING_ID then
			self.cur_ev.id = ev.value
		elseif ev.code == ABS_MT_POSITION_X then
			self.cur_ev.x = ev.value
		elseif ev.code == ABS_MT_POSITION_Y then
			self.cur_ev.y = ev.value
		end
	end
end

function GestureDetector:initialState(ev)
	if ev.id then
		self.track_id[ev.id] = ev.slot
	end
	-- default to hold state
	if ev.x and ev.y then
		self.hold_x = ev.x
		self.hold_y = ev.y
		self.state = self.holdState
	end
end

function GestureDetector:holdState(ev)
	-- hold release, we send a tap event?
	if ev.id == -1 then
		local hold_x, hold_y = self.hold_x, self.hold_y
		self:clearState()
		return {
			ges = "tap", 
			pos = Geom:new{
				x = hold_x, 
				y = hold_y,
				w = 0, h = 0,
			}
		}
	elseif ev.x and ev.y then
		self.hold_x = ev.x
		self.hold_y = ev.y
		return {
			ges = "hold", 
			pos = Geom:new{
				x = self.hold_x, 
				y = self.hold_y,
				w = 0, h = 0,
			}
		}
	end
end

function GestureDetector:clearState()
	self.hold_x = nil
	self.hold_y = nil
	self.state = self.initialState
	self.cur_ev = {}
end
