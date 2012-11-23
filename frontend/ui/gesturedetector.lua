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
		return true
	end

	return false
end


--[[
Single tap event from kernel example:

MT_TRACK_ID: 0
MT_X: 222
MT_Y: 207
SYN REPORT
MT_TRACK_ID: -1
SYN REPORT
--]]

GestureDetector = {
	-- all the time parameters are in us
	DOUBLE_TAP_INTERVAL = 300 * 1000,
	HOLD_INTERVAL = 1000 * 1000,
	-- distance parameters
	DOUBLE_TAP_DISTANCE = 50,
	PAN_THRESHOLD = 50,

	track_id = {},
	ev_stack = {},
	cur_ev = {},
	ev_start = false,
	state = function(self, ev) 
		self:switchState("initialState", ev)
	end,
	
	last_ev_timev = nil,

	-- for tap
	last_tap = nil,
}

function GestureDetector:feedEvent(ev) 
	--DEBUG(ev.type, ev.code, ev.value, ev.time)
	if ev.type == EV_SYN then
		if ev.code == SYN_REPORT then
			self.cur_ev.timev = TimeVal:new(ev.time)
			local re = self.state(self, self.cur_ev)
			self.last_ev_timev = self.cur_ev.timev
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

--[[
tap2 is the later tap
]]
function GestureDetector:isDoubleTap(tap1, tap2)
	local tv_diff = tap2.timev - tap1.timev
	return (
		math.abs(tap1.x - tap2.x) < self.DOUBLE_TAP_DISTANCE and
		math.abs(tap1.y - tap2.y) < self.DOUBLE_TAP_DISTANCE and
		(tv_diff.sec == 0 and (tv_diff.usec) < self.DOUBLE_TAP_INTERVAL)
	)
end

--[[
Warning! this method won't update self.state, you need to do it
in each state method!
--]]
function GestureDetector:switchState(state_new, ev)
	--@TODO do we need to check whether state is valid?    (houqp)
	return self[state_new](self, ev)
end

function GestureDetector:clearState()
	self.cur_x = nil
	self.cur_y = nil
	self.state = self.initialState
	self.cur_ev = {}
	self.ev_start = false
end

function GestureDetector:initialState(ev)
	if ev.id then
		-- a event ends
		if ev.id == -1 then
			self.ev_start = false
		else
			self.track_id[ev.id] = ev.slot
		end
	end
	if ev.x and ev.y then
		-- user starts a new touch motion
		if not self.ev_start then
			self.ev_start = true
			-- default to tap state
			return self:switchState("tapState", ev)
		end
	end
end

--[[
this method handles both single and double tap
--]]
function GestureDetector:tapState(ev)
	DEBUG("in tap state...", ev)
	if ev.id == -1 then
		-- end of tap event
		local ges_ev = {
			-- default to single tap
			ges = "tap", 
			pos = Geom:new{
				x = self.cur_x, 
				y = self.cur_y,
				w = 0, h = 0,
			}
		}
		-- cur_tap is used for double tap detection
		local cur_tap = {
			x = self.cur_x,
			y = self.cur_y,
			timev = ev.timev,
		}

		if self.last_tap ~= nil and 
		self:isDoubleTap(self.last_tap, cur_tap) then
			-- it is a double tap
			self:clearState()
			ges_ev.ges = "double_tap"
			self.last_tap = nil
			return ges_ev
		end

		-- set current tap to last tap
		self.last_tap = cur_tap

		DEBUG("set up tap timer")
		local deadline = self.cur_ev.timev + TimeVal:new{
				sec = 0, usec = self.DOUBLE_TAP_INTERVAL,
			}
		Input:setTimeOut(function()
			DEBUG("in tap timer", self.last_tap ~= nil)
			-- double tap will set last_tap to nil so if it is not, then
			-- user must only tapped once
			if self.last_tap ~= nil then
				self.last_tap = nil
				-- we are using closure here
				return ges_ev
			end
		end, deadline)
		-- we are already at the end of touch event
		-- so reset the state
		self:clearState()
	elseif self.state ~= self.tapState then
		-- switched from other state, probably from initialState
		-- we return nil in this case
		self.state = self.tapState
		self.cur_x = ev.x
		self.cur_y = ev.y
		DEBUG("set up hold timer")
		local deadline = self.cur_ev.timev + TimeVal:new{
				sec = 0, usec = self.HOLD_INTERVAL
			}
		Input:setTimeOut(function()
			print("hold timer", self.state == self.tapState)
			if self.state == self.tapState then
				-- timer set in tapState, so we switch to hold
				return self:switchState("holdState")
			end
		end, deadline)
	else
		-- it is not end of touch event, see if we need to switch to
		-- other states
		if (ev.x and math.abs(ev.x - self.cur_x) >= self.PAN_THRESHOLD) or
		(ev.y and math.abs(ev.y - self.cur_y) >= self.PAN_THRESHOLD) then
			-- if user's finger moved long enough in X or
			-- Y distance, we switch to pan state 
			return self:switchState("panState", ev)
		end
	end
end

function GestureDetector:panState(ev)
	DEBUG("in pan state...")
	if ev.id == -1 then
		-- end of pan, signal swipe gesture
		self:clearState()
	elseif self.state ~= self.panState then
		self.state = self.panState
		--@TODO calculate direction here    (houqp)
	else
	end
	self.cur_x = ev.x
	self.cur_y = ev.y
end

function GestureDetector:holdState(ev)
	DEBUG("in hold state...")
	-- when we switch to hold state, we pass no ev
	-- so ev = nil
	if not ev and self.cur_x and self.cur_y then
		self.state = self.holdState
		return {
			ges = "hold", 
			pos = Geom:new{
				x = self.cur_x, 
				y = self.cur_y,
				w = 0, h = 0,
			}
		}
	end
	if ev.id == -1 then
		-- end of hold, signal hold release
		self:clearState()
		return {
			ges = "hold_release", 
			pos = Geom:new{
				x = self.cur_x, 
				y = self.cur_y,
				w = 0, h = 0,
			}
		}
	end
end


