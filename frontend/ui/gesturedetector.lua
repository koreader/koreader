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
	tev_stack = {},
	-- latest feeded touch event
	last_tev = {},
	is_on_detecting = false,
	first_tev = nil,
	state = function(self, tev) 
		self:switchState("initialState", tev)
	end,
	
	last_tap = nil, -- for single/double tap
}

function GestureDetector:feedEvent(tev) 
	if tev.id ~= -1 then
		self.last_tev = tev
	end
	return self.state(self, tev)
end

function GestureDetector:deepCopyEv(tev)
	return {
		x = tev.x,
		y = tev.y,
		id = tev.id,
		slot = tev.slot,
		timev = TimeVal:new{
			sec = tev.timev.sec,
			usec = tev.timev.usec,
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
compare last_pan with self.first_tev
if it is a swipe, return direction of swipe gesture.
--]]
function GestureDetector:isSwipe()
	local tv_diff = self.first_tev.timev - self.last_tev.timev
	if (tv_diff.sec == 0) and (tv_diff.usec < self.SWIPE_INTERVAL) then
		x_diff = self.last_tev.x - self.first_tev.x
		y_diff = self.last_tev.y - self.first_tev.y
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
function GestureDetector:switchState(state_new, tev)
	--@TODO do we need to check whether state is valid?    (houqp)
	return self[state_new](self, tev)
end

function GestureDetector:clearState()
	self.state = self.initialState
	self.last_tev = {}
	self.is_on_detecting = false
	self.first_tev = nil
end

function GestureDetector:initialState(tev)
	if tev.id then
		-- a event ends
		if tev.id == -1 then
			self.is_on_detecting = false
		else
			self.track_id[tev.id] = tev.slot
		end
	end
	if tev.x and tev.y then
		-- user starts a new touch motion
		if not self.is_on_detecting then
			self.is_on_detecting = true
			self.first_tev = self:deepCopyEv(tev)
			-- default to tap state
			return self:switchState("tapState", tev)
		end
	end
end

--[[
this method handles both single and double tap
--]]
function GestureDetector:tapState(tev)
	DEBUG("in tap state...", tev)
	if tev.id == -1 then
		-- end of tap event
		local ges_ev = {
			-- default to single tap
			ges = "tap", 
			pos = Geom:new{
				x = self.last_tev.x, 
				y = self.last_tev.y,
				w = 0, h = 0,
			}
		}
		-- cur_tap is used for double tap detection
		local cur_tap = {
			x = self.last_tev.x,
			y = self.last_tev.y,
			timev = tev.timev,
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
		local deadline = self.last_tev.timev + TimeVal:new{
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
		local deadline = self.last_tev.timev + TimeVal:new{
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
		if (tev.x and math.abs(tev.x - self.first_tev.x) >= self.PAN_THRESHOLD) or
		(tev.y and math.abs(tev.y - self.first_tev.y) >= self.PAN_THRESHOLD) then
			-- if user's finger moved long enough in X or
			-- Y distance, we switch to pan state 
			return self:switchState("panState", tev)
		end
	end
end

function GestureDetector:panState(tev)
	DEBUG("in pan state...")
	if tev.id == -1 then
		-- end of pan, signal swipe gesture if necessary
		swipe_direct = self:isSwipe()
		if swipe_direct then
			local start_pos = Geom:new{
					x = self.first_tev.x, 
					y = self.first_tev.y,
					w = 0, h = 0,
			}
			self:clearState()
			return {
				ges = "swipe", 
				direction = swipe_direct,
				-- use first pan tev coordination as swipe start point
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
		pan_ev.relative.x = tev.x - self.last_tev.x
		pan_ev.relative.y = tev.y - self.last_tev.y
		pan_ev.pos = Geom:new{
			x = self.last_tev.x, 
			y = self.last_tev.y,
			w = 0, h = 0,
		}
		self.last_tev = tev
		return pan_ev
	end
end

function GestureDetector:holdState(tev)
	DEBUG("in hold state...")
	-- when we switch to hold state, we pass no ev
	-- so ev = nil
	if not tev and self.last_tev.x and self.last_tev.y then
		self.state = self.holdState
		return {
			ges = "hold", 
			pos = Geom:new{
				x = self.last_tev.x, 
				y = self.last_tev.y,
				w = 0, h = 0,
			}
		}
	end
	if tev.id == -1 then
		-- end of hold, signal hold release
		self:clearState()
		return {
			ges = "hold_release", 
			pos = Geom:new{
				x = self.last_tev.x, 
				y = self.last_tev.y,
				w = 0, h = 0,
			}
		}
	end
end


