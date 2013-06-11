require "ui/geometry"
require "ui/device"

GestureRange = {
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

--[[
Current detectable gestures:
	* tap
	* pan
	* hold
	* swipe
	* pinch
	* spread
	* rotate
	* double_tap
	* inward_pan
	* outward_pan
	* pan_release
	* two_finger_tap
	* two_finger_pan
	* two_finger_swipe
	* two_finger_pan_release

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
	TWO_FINGER_TAP_DURATION = 300 * 1000,
	HOLD_INTERVAL = 1000 * 1000,
	SWIPE_INTERVAL = 900 * 1000,
	-- distance parameters
	DOUBLE_TAP_DISTANCE = 50,
	TWO_FINGER_TAP_REGION = 20,
	PAN_THRESHOLD = 50,
	-- pinch/spread direction table
	DIRECTION_TABLE = {
		east = "horizontal",
		west = "horizontal",
		north = "vertical",
		south = "vertical",
		northeast = "diagonal",
		northwest = "diagonal",
		southeast = "diagonal",
		southwest = "diagonal",
	},
	-- states are stored in separated slots
	states = {},
	track_ids = {},
	tev_stacks = {},
	-- latest feeded touch event in each slots
	last_tevs = {},
	first_tevs = {},
	-- detecting status on each slots
	detectings = {},
	-- for single/double tap
	last_taps = {},
}

function GestureDetector:feedEvent(tevs)
	repeat
		local tev = table.remove(tevs)
		if tev then
			local slot = tev.slot
			if not self.states[slot] then
				self:clearState(slot) -- initiate state
			end
			local ges = self.states[slot](self, tev)
			if tev.id ~= -1 then
				self.last_tevs[slot] = tev
			end
			-- return no more than one gesture
			if ges then return ges end
		end
	until tev == nil
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

function GestureDetector:isTwoFingerTap()
	if self.last_tevs[0] == nil or self.last_tevs[1] == nil then
		return false
	end
	local x_diff0 = math.abs(self.last_tevs[0].x - self.first_tevs[0].x)
	local x_diff1 = math.abs(self.last_tevs[1].x - self.first_tevs[1].x)
	local y_diff0 = math.abs(self.last_tevs[0].y - self.first_tevs[0].y)
	local y_diff1 = math.abs(self.last_tevs[1].y - self.first_tevs[1].y)
	local tv_diff0 = self.last_tevs[0].timev - self.first_tevs[0].timev
	local tv_diff1 = self.last_tevs[1].timev - self.first_tevs[1].timev
	return (
		x_diff0 < self.TWO_FINGER_TAP_REGION and
		x_diff1 < self.TWO_FINGER_TAP_REGION and
		y_diff0 < self.TWO_FINGER_TAP_REGION and
		y_diff1 < self.TWO_FINGER_TAP_REGION and
		tv_diff0.sec == 0 and tv_diff0.usec < self.TWO_FINGER_TAP_DURATION and
		tv_diff1.sec == 0 and tv_diff1.usec < self.TWO_FINGER_TAP_DURATION
	)
end

--[[
compare last_pan with first_tev in this slot
return pan direction and distance
--]]
function GestureDetector:getPath(slot)
	local x_diff = self.last_tevs[slot].x - self.first_tevs[slot].x
	local y_diff = self.last_tevs[slot].y - self.first_tevs[slot].y
	local direction = nil
	local distance = math.sqrt(x_diff*x_diff + y_diff*y_diff)
	if x_diff == 0 and y_diff == 0 then
	else
		local v_direction = y_diff < 0 and "north" or "south"
		local h_direction = x_diff < 0 and "west" or "east"
		if math.abs(y_diff) > 0.577*math.abs(x_diff)
			and math.abs(y_diff) < 1.732*math.abs(x_diff) then
			direction = v_direction..h_direction
		elseif (math.abs(x_diff) > math.abs(y_diff)) then
			direction = h_direction
		else
			direction = v_direction
		end
	end
	return direction, distance
end

function GestureDetector:isSwipe(slot)
	if not self.first_tevs[slot] or not self.last_tevs[slot] then return end
	local tv_diff = self.first_tevs[slot].timev - self.last_tevs[slot].timev
	if (tv_diff.sec == 0) and (tv_diff.usec < self.SWIPE_INTERVAL) then
		local x_diff = self.last_tevs[slot].x - self.first_tevs[slot].x
		local y_diff = self.last_tevs[slot].y - self.first_tevs[slot].y
		if x_diff ~= 0 or y_diff ~= 0 then
			return true
		end
	end
end

function GestureDetector:getRotate(orig_point, start_point, end_point)
	local a = orig_point:distance(start_point)
	local b = orig_point:distance(end_point)
	local c = start_point:distance(end_point)
	return math.acos((a*a + b*b - c*c)/(2*a*b))*180/math.pi
end

--[[
Warning! this method won't update self.state, you need to do it
in each state method!
--]]
function GestureDetector:switchState(state_new, tev, param)
	--@TODO do we need to check whether state is valid?    (houqp)
	return self[state_new](self, tev, param)
end

function GestureDetector:clearState(slot)
	self.states[slot] = self.initialState
	self.detectings[slot] = false
	self.first_tevs[slot] = nil
	self.last_tevs[slot] = nil
end

function GestureDetector:clearStates()
	self:clearState(0)
	self:clearState(1)
end

function GestureDetector:initialState(tev)
	local slot = tev.slot
	if tev.id then
		-- a event ends
		if tev.id == -1 then
			self.detectings[slot] = false
		else
			self.track_ids[slot] = tev.id
		end
	end
	if tev.x and tev.y then
		-- user starts a new touch motion
		if not self.detectings[slot] then
			self.detectings[slot] = true
			self.first_tevs[slot] = self:deepCopyEv(tev)
			-- default to tap state
			return self:switchState("tapState", tev)
		end
	end
end

--[[
this method handles both single and double tap
--]]
function GestureDetector:tapState(tev)
	DEBUG("in tap state...")
	local slot = tev.slot
	if tev.id == -1 then
		-- end of tap event
		if self.detectings[0] and self.detectings[1] then
			if self:isTwoFingerTap() then
				local pos0 = Geom:new{
					x = self.last_tevs[0].x,
					y = self.last_tevs[0].y,
					w = 0, h = 0,
				}
				local pos1 = Geom:new{
					x = self.last_tevs[1].x,
					y = self.last_tevs[1].y,
					w = 0, h = 0,
				}
				local tap_span = pos0:distance(pos1)
				DEBUG("two-finger tap detected with span", tap_span)
				self:clearStates()
				return {
					ges = "two_finger_tap",
					pos = pos0:midpoint(pos1),
					span = tap_span,
					time = tev.timev,
				}
			else
				self:clearState(slot)
			end
		elseif self.last_tevs[slot] ~= nil then
			return self:handleDoubleTap(tev)
		else
			-- last tev in this slot is cleared by last two finger tap
			self:clearState(slot)
			return {
				ges = "tap",
				pos = Geom:new{
					x = tev.x,
					y = tev.y,
					w = 0, h = 0,
				},
				time = tev.timev,
			}
		end
	else
		return self:handleNonTap(tev)
	end
end

function GestureDetector:handleDoubleTap(tev)
	local slot = tev.slot
	local ges_ev = {
		-- default to single tap
		ges = "tap",
		pos = Geom:new{
			x = self.last_tevs[slot].x,
			y = self.last_tevs[slot].y,
			w = 0, h = 0,
		},
		time = tev.timev,
	}
	-- cur_tap is used for double tap detection
	local cur_tap = {
		x = tev.x,
		y = tev.y,
		timev = tev.timev,
	}

	if self.last_taps[slot] ~= nil and
	self:isDoubleTap(self.last_taps[slot], cur_tap) then
		-- it is a double tap
		self:clearState(slot)
		ges_ev.ges = "double_tap"
		self.last_taps[slot] = nil
		DEBUG("double tap detected in slot", slot)
		return ges_ev
	end

	-- set current tap to last tap
	self.last_taps[slot] = cur_tap

	DEBUG("set up tap timer")
	-- deadline should be calculated by adding current tap time and the interval
	local deadline = cur_tap.timev + TimeVal:new{
		sec = 0, usec = self.DOUBLE_TAP_INTERVAL,
	}
	Input:setTimeout(function()
		DEBUG("in tap timer", self.last_taps[slot] ~= nil)
		-- double tap will set last_tap to nil so if it is not, then
		-- user must only tapped once
		if self.last_taps[slot] ~= nil then
			self.last_taps[slot] = nil
			-- we are using closure here
			DEBUG("single tap detected in slot", slot)
			return ges_ev
		end
	end, deadline)
	-- we are already at the end of touch event
	-- so reset the state
	self:clearState(slot)
end

function GestureDetector:handleNonTap(tev)
	local slot = tev.slot
	if self.states[slot] ~= self.tapState then
		-- switched from other state, probably from initialState
		-- we return nil in this case
		self.states[slot] = self.tapState
		DEBUG("set up hold timer")
		local deadline = tev.timev + TimeVal:new{
			sec = 0, usec = self.HOLD_INTERVAL
		}
		Input:setTimeout(function()
			if self.states[slot] == self.tapState then
				-- timer set in tapState, so we switch to hold
				DEBUG("hold gesture detected in slot", slot)
				return self:switchState("holdState", tev, true)
			end
		end, deadline)
	else
		-- it is not end of touch event, see if we need to switch to
		-- other states
		if (tev.x and math.abs(tev.x - self.first_tevs[slot].x) >= self.PAN_THRESHOLD) or
		(tev.y and math.abs(tev.y - self.first_tevs[slot].y) >= self.PAN_THRESHOLD) then
			-- if user's finger moved long enough in X or
			-- Y distance, we switch to pan state
			return self:switchState("panState", tev)
		end
	end
end

function GestureDetector:panState(tev)
	DEBUG("in pan state...")
	local slot = tev.slot
	if tev.id == -1 then
		-- end of pan, signal swipe gesture if necessary
		if self:isSwipe(slot) then
			if self.detectings[0] and self.detectings[1] then
				local ges_ev = self:handleTwoFingerPan(tev)
				self:clearStates()
				if ges_ev then
					if ges_ev.ges == "two_finger_pan" then
						ges_ev.ges = "two_finger_swipe"
					elseif ges_ev.ges == "inward_pan" then
						ges_ev.ges = "pinch"
					elseif ges_ev.ges == "outward_pan" then
						ges_ev.ges = "spread"
					end
					DEBUG(ges_ev.ges, ges_ev.direction, ges_ev.distance, "detected")
				end
				return ges_ev
			else
				return self:handleSwipe(tev)
			end
		else -- if end of pan is not swipe then it must be pan release.
			return self:handlePanRelease(tev)
		end
	else
		if self.states[slot] ~= self.panState then
			self.states[slot] = self.panState
		end
		return self:handlePan(tev)
	end
end

function GestureDetector:handleSwipe(tev)
	local slot = tev.slot
	local swipe_direction, swipe_distance = self:getPath(slot)
	local start_pos = Geom:new{
		x = self.first_tevs[slot].x,
		y = self.first_tevs[slot].y,
		w = 0, h = 0,
	}
	DEBUG("swipe", swipe_direction, swipe_distance, "detected in slot", slot)
	self:clearState(slot)
	return {
		ges = "swipe",
		-- use first pan tev coordination as swipe start point
		pos = start_pos,
		direction = swipe_direction,
		distance = swipe_distance,
		time = tev.timev,
	}
end

function GestureDetector:handlePan(tev)
	local slot = tev.slot
	if self.detectings[0] and self.detectings[1] then
		return self:handleTwoFingerPan(tev)
	else
		local pan_direction, pan_distance = self:getPath(slot)
		local pan_ev = {
			ges = "pan",
			relative = {
				-- default to pan 0
				x = 0,
				y = 0,
			},
			pos = nil,
			direction = pan_direction,
			distance = pan_distance,
			time = tev.timev,
		}
		pan_ev.relative.x = tev.x - self.last_tevs[slot].x
		pan_ev.relative.y = tev.y - self.last_tevs[slot].y
		pan_ev.pos = Geom:new{
			x = self.last_tevs[slot].x,
			y = self.last_tevs[slot].y,
			w = 0, h = 0,
		}
		return pan_ev
	end
end

function GestureDetector:handleTwoFingerPan(tev)
	-- triggering slot
	local tslot = tev.slot
	-- reference slot
	local rslot = tslot and 0 or 1
	local tpan_dir, tpan_dis = self:getPath(tslot)
	local tstart_pos = Geom:new{
		x = self.first_tevs[tslot].x,
		y = self.first_tevs[tslot].y,
		w = 0, h = 0,
	}
	local tend_pos = Geom:new{
		x = self.last_tevs[tslot].x,
		y = self.last_tevs[tslot].y,
		w = 0, h = 0,
	}
	local rstart_pos = Geom:new{
		x = self.first_tevs[rslot].x,
		y = self.first_tevs[rslot].y,
		w = 0, h = 0,
	}
	if self.states[rslot] == self.panState then
		local rpan_dir, rpan_dis = self:getPath(rslot)
		local rend_pos = Geom:new{
			x = self.last_tevs[rslot].x,
			y = self.last_tevs[rslot].y,
			w = 0, h = 0,
		}
		local start_distance = tstart_pos:distance(rstart_pos)
		local end_distance = tend_pos:distance(rend_pos)
		local ges_ev = {
			ges = "two_finger_pan",
			-- use midpoint of tstart and rstart as swipe start point
			pos = tstart_pos:midpoint(rstart_pos),
			distance = tpan_dis + rpan_dis,
			direction = tpan_dir,
			time = tev.timev,
		}
		if tpan_dir ~= rpan_dir then
			if start_distance > end_distance then
				ges_ev.ges = "inward_pan"
			else
				ges_ev.ges = "outward_pan"
			end
			ges_ev.direction = self.DIRECTION_TABLE[tpan_dir]
		end
		DEBUG(ges_ev.ges, ges_ev.direction, ges_ev.distance, "detected")
		return ges_ev
	elseif self.states[rslot] == self.holdState then
		local angle = self:getRotate(rstart_pos, tstart_pos, tend_pos)
		DEBUG("rotate", angle, "detected")
		return {
			ges = "rotate",
			pos = rstart_pos,
			angle = angle,
			time = tev.timev,
		}
	end
end

function GestureDetector:handlePanRelease(tev)
	local slot = tev.slot
	local release_pos = Geom:new{
		x = self.last_tevs[slot].x,
		y = self.last_tevs[slot].y,
		w = 0, h = 0,
	}
	local pan_ev = {
		ges = "pan_release",
		pos = release_pos,
		time = tev.timev,
	}
	if self.detectings[0] and self.detectings[1] then
		DEBUG("two finger pan release detected")
		pan_ev.ges = "two_finger_pan_release"
		self:clearStates()
	else
		DEBUG("pan release detected in slot", slot)
		self:clearState(slot)
	end
	return pan_ev
end

function GestureDetector:holdState(tev, hold)
	DEBUG("in hold state...")
	local slot = tev.slot
	-- when we switch to hold state, we pass additional param "hold"
	if tev.id ~= -1 and hold and self.last_tevs[slot].x and self.last_tevs[slot].y then
		self.states[slot] = self.holdState
		return {
			ges = "hold",
			pos = Geom:new{
				x = self.last_tevs[slot].x,
				y = self.last_tevs[slot].y,
				w = 0, h = 0,
			},
			time = tev.timev,
		}
	end
	if tev.id == -1 and self.last_tevs[slot] ~= nil then
		-- end of hold, signal hold release
		DEBUG("hold_release detected in slot", slot)
		local last_x = self.last_tevs[slot].x
		local last_y = self.last_tevs[slot].y
		self:clearState(slot)
		return {
			ges = "hold_release",
			pos = Geom:new{
				x = last_x,
				y = last_y,
				w = 0, h = 0,
			},
			time = tev.timev,
		}
	end
end

--[[
  @brief change gesture's x and y coordinates according to screen view mode

  @param ges gesture that you want to adjust
  @return adjusted gesture.
--]]
function GestureDetector:adjustGesCoordinate(ges)
	local dev_mod = Device:getModel()
	if dev_mod == "Kobo" then
		ges.pos.x, ges.pos.y = (Screen.width - ges.pos.y), (ges.pos.x)
	end
	if Screen.cur_rotation_mode == 1 then
		-- in landscape mode
		if ges.pos then
			ges.pos.x, ges.pos.y = (Screen.width - ges.pos.y), (ges.pos.x)
		end
		if ges.ges == "swipe" or ges.ges == "pan"
			or ges.ges == "two_finger_swipe"
			or ges.ges == "two_finger_pan" then
			if ges.direction == "north" then
				ges.direction = "east"
			elseif ges.direction == "south" then
				ges.direction = "west"
			elseif ges.direction == "east" then
				ges.direction = "south"
			elseif ges.direction == "west" then
				ges.direction = "north"
			elseif ges.direction == "northeast" then
				ges.direction = "southeast"
			elseif ges.direction == "northwest" then
				ges.direction = "northeast"
			elseif ges.direction == "southeast" then
				ges.direction = "southwest"
			elseif ges.direction == "southwest" then
				ges.direction = "northwest"
			end
		elseif ges.ges == "pinch" or ges.ges == "spread"
			or ges.ges == "inward_pan"
			or ges.ges == "outward_pan" then
			if ges.direction == "horizontal" then
				ges.direction = "vertical"
			elseif ges.direction == "vertical" then
				ges.direction = "horizontal"
			end
		end
	end
	return ges
end
