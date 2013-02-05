require "ui/geometry"

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
Currently supported gestures:
	* single tap
	* double tap
	* hold
	* pan
	* swipe

You change the state machine by feeding it touch events, i.e. calling
GestureDetector:feedEvent(tev).

a touch event should have following format: 
tev = {
	slot = 1,
	id = 46,
	x = 0,
	y = 1,
	timev = TimeVal:new{...},
}

Don't confuse tev with raw evs from kernel, tev is build according to ev.

GestureDetector:feedEvent(tev) will return a detection result when you
feed a touch release event to it.
--]]

GestureDetector = {
	-- all the time parameters are in us
	DOUBLE_TAP_INTERVAL = 300 * 1000,
	HOLD_INTERVAL = 1000 * 1000,
	SWIPE_INTERVAL = 900 * 1000,
	-- distance parameters
	DOUBLE_TAP_DISTANCE = 50,
	PAN_THRESHOLD = 50,

	track_id = {},
	ev_stack = {},
	-- latest feeded touch event
	last_ev = {},
	is_ev_start = false,
	first_ev = nil,
	state = function(self, ev) 
		self:switchState("initialState", ev)
	end,
	
	last_tap = nil, -- for single/double tap
}

function GestureDetector:feedEvent(tev) 
	if tev.id ~= -1 then
		self.last_ev = tev
	end
	return self.state(self, tev)
end

function GestureDetector:deepCopyEv(ev)
	return {
		x = ev.x,
		y = ev.y,
		id = ev.id,
		slot = ev.slot,
		timev = TimeVal:new{
			sec = ev.timev.sec,
			usec = ev.timev.usec,
		}
	}
end

--[[
tap2 is the later tap
--]]
function GestureDetector:isDoubleTap(tap1, tap2)
	local tv_diff = tap2.timev - tap1.timev
	return (
		math.abs(tap1.x - tap2.x) < self.DOUBLE_TAP_DISTANCE and
		math.abs(tap1.y - tap2.y) < self.DOUBLE_TAP_DISTANCE and
		(tv_diff.sec == 0 and (tv_diff.usec) < self.DOUBLE_TAP_INTERVAL)
	)
end

--[[
compare last_pan with self.first_ev
if it is a swipe, return direction of swipe gesture.
--]]
function GestureDetector:isSwipe()
	local tv_diff = self.first_ev.timev - self.last_ev.timev
	if (tv_diff.sec == 0) and (tv_diff.usec < self.SWIPE_INTERVAL) then
		x_diff = self.last_ev.x - self.first_ev.x
		y_diff = self.last_ev.y - self.first_ev.y
		if x_diff == 0 and y_diff == 0 then
			return nil
		end

		if (math.abs(x_diff) > math.abs(y_diff)) then
			-- left or right
			if x_diff < 0 then
				return "left"
			else
				return "right"
			end
		else
			-- up or down
			if y_diff < 0 then
				return "up"
			else
				return "down"
			end
		end
	end
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
	self.state = self.initialState
	self.last_ev = {}
	self.is_ev_start = false
	self.first_ev = nil
end

function GestureDetector:initialState(ev)
	if ev.id then
		-- a event ends
		if ev.id == -1 then
			self.is_ev_start = false
		else
			self.track_id[ev.id] = ev.slot
		end
	end
	if ev.x and ev.y then
		-- user starts a new touch motion
		if not self.is_ev_start then
			self.is_ev_start = true
			self.first_ev = self:deepCopyEv(ev)
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
				x = self.last_ev.x, 
				y = self.last_ev.y,
				w = 0, h = 0,
			}
		}
		-- cur_tap is used for double tap detection
		local cur_tap = {
			x = self.last_ev.x,
			y = self.last_ev.y,
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
		local deadline = self.last_ev.timev + TimeVal:new{
				sec = 0, usec = self.DOUBLE_TAP_INTERVAL,
			}
		Input:setTimeout(function()
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
		DEBUG("set up hold timer")
		local deadline = self.last_ev.timev + TimeVal:new{
				sec = 0, usec = self.HOLD_INTERVAL
			}
		Input:setTimeout(function()
			if self.state == self.tapState then
				-- timer set in tapState, so we switch to hold
				return self:switchState("holdState")
			end
		end, deadline)
	else
		-- it is not end of touch event, see if we need to switch to
		-- other states
		if (ev.x and math.abs(ev.x - self.first_ev.x) >= self.PAN_THRESHOLD) or
		(ev.y and math.abs(ev.y - self.first_ev.y) >= self.PAN_THRESHOLD) then
			-- if user's finger moved long enough in X or
			-- Y distance, we switch to pan state 
			return self:switchState("panState", ev)
		end
	end
end

function GestureDetector:panState(ev)
	DEBUG("in pan state...")
	if ev.id == -1 then
		-- end of pan, signal swipe gesture if necessary
		swipe_direct = self:isSwipe()
		if swipe_direct then
			local start_pos = Geom:new{
					x = self.first_ev.x, 
					y = self.first_ev.y,
					w = 0, h = 0,
			}
			self:clearState()
			return {
				ges = "swipe", 
				direction = swipe_direct,
				-- use first pan ev coordination as swipe start point
				pos = start_pos,
				--@TODO add start and end points?    (houqp)
			}
		end
		self:clearState()
	else
		if self.state ~= self.panState then
			self.state = self.panState
		end

		local pan_ev = {
			ges = "pan",
			relative = {
				-- default to pan 0
				x = 0,
				y = 0,
			},
			pos = nil,
		}
		pan_ev.relative.x = ev.x - self.last_ev.x
		pan_ev.relative.y = ev.y - self.last_ev.y
		pan_ev.pos = Geom:new{
			x = self.last_ev.x, 
			y = self.last_ev.y,
			w = 0, h = 0,
		}
		self.last_ev = ev
		return pan_ev
	end
end

function GestureDetector:holdState(ev)
	DEBUG("in hold state...")
	-- when we switch to hold state, we pass no ev
	-- so ev = nil
	if not ev and self.last_ev.x and self.last_ev.y then
		self.state = self.holdState
		return {
			ges = "hold", 
			pos = Geom:new{
				x = self.last_ev.x, 
				y = self.last_ev.y,
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
				x = self.last_ev.x, 
				y = self.last_ev.y,
				w = 0, h = 0,
			}
		}
	end
end


