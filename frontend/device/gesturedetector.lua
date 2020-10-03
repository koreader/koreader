--[[--
This module detects gestures.

Current detectable gestures:

* `touch` (user touched screen)
* `tap` (touch action detected as single tap)
* `pan`
* `hold`
* `swipe`
* `pinch`
* `spread`
* `rotate`
* `hold_pan`
* `double_tap`
* `inward_pan`
* `outward_pan`
* `pan_release`
* `hold_release`
* `two_finger_tap`
* `two_finger_pan`
* `two_finger_swipe`
* `two_finger_pan_release`

You change the state machine by feeding it touch events, i.e. calling
@{GestureDetector:feedEvent|GestureDetector:feedEvent(tev)}.


a touch event should have following format:

    tev = {
        slot = 1,
        id = 46,
        x = 0,
        y = 1,
        timev = TimeVal:new{...},
    }

Don't confuse `tev` with raw evs from kernel, `tev` is build according to ev.

@{GestureDetector:feedEvent|GestureDetector:feedEvent(tev)} will return a
detection result when you feed a touch release event to it.
--]]

local Geom = require("ui/geometry")
local TimeVal = require("ui/timeval")
local logger = require("logger")
local util = require("util")

-- all the time parameters are in us
local ges_double_tap_interval = G_reader_settings:readSetting("ges_double_tap_interval") or 300 * 1000
local ges_two_finger_tap_duration = G_reader_settings:readSetting("ges_two_finger_tap_duration") or 300 * 1000
local ges_hold_interval = G_reader_settings:readSetting("ges_hold_interval") or 500 * 1000
local ges_pan_delayed_interval = G_reader_settings:readSetting("ges_pan_delayed_interval") or 500 * 1000
local ges_swipe_interval = G_reader_settings:readSetting("ges_swipe_interval") or 900 * 1000

local GestureDetector = {
    -- must be initialized with the Input singleton class
    input = nil,
    -- default values (all the time parameters are in us)
    DOUBLE_TAP_INTERVAL = 300 * 1000,
    TWO_FINGER_TAP_DURATION = 300 * 1000,
    HOLD_INTERVAL = 500 * 1000,
    PAN_DELAYED_INTERVAL = 500 * 1000,
    SWIPE_INTERVAL = 900 * 1000,
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
    hold_timer_id = {},
    track_ids = {},
    tev_stacks = {},
    -- latest feeded touch event in each slots
    last_tevs = {},
    first_tevs = {},
    -- for multiswipe gestures
    multiswipe_directions = {},
    -- detecting status on each slots
    detectings = {},
    -- for single/double tap
    last_taps = {},
}

function GestureDetector:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    if o.init then o:init() end
    return o
end

function GestureDetector:init()
    local scaler = self.screen:getDPI() / 167
    -- distance parameters
    self.TWO_FINGER_TAP_REGION = 20 * scaler
    self.DOUBLE_TAP_DISTANCE = 50 * scaler
    self.PAN_THRESHOLD = self.DOUBLE_TAP_DISTANCE
    self.MULTISWIPE_THRESHOLD = self.DOUBLE_TAP_DISTANCE
end

--[[--
Feeds touch events to state machine.
--]]
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
        (tv_diff.sec == 0 and (tv_diff.usec) < ges_double_tap_interval)
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
        tv_diff0.sec == 0 and tv_diff0.usec < ges_two_finger_tap_duration and
        tv_diff1.sec == 0 and tv_diff1.usec < ges_two_finger_tap_duration
    )
end

--[[--
Compares `last_pan` with `first_tev` in this slot.

The second boolean argument `simple` results in only four directions if true.

@return (direction, distance) pan direction and distance
--]]
function GestureDetector:getPath(slot, simple, diagonal, first_tev)
    first_tev = first_tev or self.first_tevs

    local x_diff = self.last_tevs[slot].x - first_tev[slot].x
    local y_diff = self.last_tevs[slot].y - first_tev[slot].y
    local direction = nil
    local distance = math.sqrt(x_diff*x_diff + y_diff*y_diff)
    if x_diff ~= 0 or y_diff ~= 0 then
        local v_direction = y_diff < 0 and "north" or "south"
        local h_direction = x_diff < 0 and "west" or "east"
        if (not simple
            and math.abs(y_diff) > 0.577*math.abs(x_diff)
            and math.abs(y_diff) < 1.732*math.abs(x_diff))
           or (simple and diagonal)
        then
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
    local tv_diff = self.last_tevs[slot].timev - self.first_tevs[slot].timev
    if (tv_diff.sec == 0) and (tv_diff.usec < ges_swipe_interval) then
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
    --- @todo Do we need to check whether state is valid?    (houqp)
    return self[state_new](self, tev, param)
end

function GestureDetector:clearState(slot)
    self.states[slot] = self.initialState
    self.hold_timer_id[slot] = nil
    self.detectings[slot] = false
    self.first_tevs[slot] = nil
    self.last_tevs[slot] = nil
    self.multiswipe_directions = {}
    self.multiswipe_type = nil
end

function GestureDetector:setNewInterval(type, interval)
    if type == "ges_double_tap_interval" then
        ges_double_tap_interval = interval
    elseif type == "ges_two_finger_tap_duration" then
        ges_two_finger_tap_duration = interval
    elseif type == "ges_hold_interval" then
        ges_hold_interval = interval
    elseif type == "ges_pan_delayed_interval" then
        ges_pan_delayed_interval = interval
    elseif type == "ges_swipe_interval" then
        ges_swipe_interval = interval
    end
end

function GestureDetector:getInterval(type)
    if type == "ges_double_tap_interval" then
        return ges_double_tap_interval
    elseif type == "ges_two_finger_tap_duration" then
        return ges_two_finger_tap_duration
    elseif type == "ges_hold_interval" then
        return ges_hold_interval
    elseif type == "ges_pan_delayed_interval" then
        return ges_pan_delayed_interval
    elseif type == "ges_swipe_interval" then
        return ges_swipe_interval
    end
end

function GestureDetector:clearStates()
    self:clearState(0)
    self:clearState(1)
end

function GestureDetector:initialState(tev)
    local slot = tev.slot
    if tev.id then
        -- an event ends
        if tev.id == -1 then
            self.detectings[slot] = false
        else
            self.track_ids[slot] = tev.id
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
    end
end

--[[--
Handles both single and double tap.
--]]
function GestureDetector:tapState(tev)
    logger.dbg("in tap state...")
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
                logger.dbg("two-finger tap detected with span", tap_span)
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

    if not self.input.disable_double_tap and self.last_taps[slot] ~= nil and
                self:isDoubleTap(self.last_taps[slot], cur_tap) then
        -- it is a double tap
        self:clearState(slot)
        ges_ev.ges = "double_tap"
        self.last_taps[slot] = nil
        logger.dbg("double tap detected in slot", slot)
        return ges_ev
    end

    -- set current tap to last tap
    self.last_taps[slot] = cur_tap

    logger.dbg("set up tap timer")
    -- deadline should be calculated by adding current tap time and the interval
    local deadline = cur_tap.timev + TimeVal:new{
        sec = 0,
        usec = not self.input.disable_double_tap and ges_double_tap_interval or 0,
    }
    self.input:setTimeout(function()
        logger.dbg("in tap timer", self.last_taps[slot] ~= nil)
        -- double tap will set last_tap to nil so if it is not, then
        -- user must only tapped once
        if self.last_taps[slot] ~= nil then
            self.last_taps[slot] = nil
            -- we are using closure here
            logger.dbg("single tap detected in slot", slot, ges_ev.pos)
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
        logger.dbg("set up hold timer")
        local deadline = tev.timev + TimeVal:new{
            sec = 0, usec = ges_hold_interval
        }
        -- Be sure the following setTimeout only react to this tapState
        local hold_timer_id = tev.timev
        self.hold_timer_id[slot] = hold_timer_id
        self.input:setTimeout(function()
            if self.states[slot] == self.tapState and self.hold_timer_id[slot] == hold_timer_id then
                -- timer set in tapState, so we switch to hold
                logger.dbg("hold gesture detected in slot", slot)
                return self:switchState("holdState", tev, true)
            end
        end, deadline)
        return {
            ges = "touch",
            pos = Geom:new{
                x = tev.x,
                y = tev.y,
                w = 0, h = 0,
            },
            time = tev.timev,
        }
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
    logger.dbg("in pan state...")
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
                    logger.dbg(ges_ev.ges, ges_ev.direction, ges_ev.distance, "detected")
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
    local ges = "swipe"
    local multiswipe_directions

    if #self.multiswipe_directions > 1 then
        ges = "multiswipe"
        multiswipe_directions = ""
        for k, v in pairs(self.multiswipe_directions) do
            local sep = ""
            if k > 1 then
                sep = " "
            end
            multiswipe_directions = multiswipe_directions .. sep .. v[1]
        end
        logger.dbg("multiswipe", multiswipe_directions)
    end

    --- @todo dirty hack for some weird devices, replace it with better solution
    if swipe_direction == "west" and DCHANGE_WEST_SWIPE_TO_EAST then
        swipe_direction = "east"
    elseif swipe_direction == "east" and DCHANGE_EAST_SWIPE_TO_WEST then
        swipe_direction = "west"
    end
    logger.dbg("swipe", swipe_direction, swipe_distance, "detected in slot", slot)
    self:clearState(slot)
    return {
        ges = ges,
        -- use first pan tev coordination as swipe start point
        pos = start_pos,
        direction = swipe_direction,
        multiswipe_directions = multiswipe_directions,
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
        local tv_diff = self.last_tevs[slot].timev - self.first_tevs[slot].timev

        local pan_ev = {
            ges = "pan",
            relative = {
                -- default to pan 0
                x = 0,
                y = 0,
            },
            relative_delayed = {
                -- default to pan 0
                x = 0,
                y = 0,
            },
            pos = nil,
            direction = pan_direction,
            distance = pan_distance,
            distance_delayed = 0,
            time = tev.timev,
        }

        -- regular pan
        pan_ev.relative.x = tev.x - self.first_tevs[slot].x
        pan_ev.relative.y = tev.y - self.first_tevs[slot].y

        -- delayed pan, used where necessary to reduce potential activation of panning
        -- when swiping is intended (e.g., for the menu or for multiswipe)
        if not ((tv_diff.sec == 0) and (tv_diff.usec < ges_pan_delayed_interval)) then
            pan_ev.relative_delayed.x = tev.x - self.first_tevs[slot].x
            pan_ev.relative_delayed.y = tev.y - self.first_tevs[slot].y
            pan_ev.distance_delayed = pan_distance
        end

        pan_ev.pos = Geom:new{
            x = self.last_tevs[slot].x,
            y = self.last_tevs[slot].y,
            w = 0, h = 0,
        }

        local msd_cnt = #self.multiswipe_directions
        local msd_direction_prev = (msd_cnt > 0) and self.multiswipe_directions[msd_cnt][1] or ""
        local prev_ms_ev, fake_first_tev

        if msd_cnt == 0 then
            -- determine whether to initiate a straight or diagonal multiswipe
            self.multiswipe_type = "straight"
            if pan_direction ~= "north" and pan_direction ~= "south"
               and pan_direction ~= "east" and pan_direction ~= "west" then
                self.multiswipe_type = "diagonal"
            end
        -- recompute a more accurate direction and distance in a multiswipe context
        elseif msd_cnt > 0 then
            prev_ms_ev = self.multiswipe_directions[msd_cnt][2]
            fake_first_tev = {
                [slot] = {
                    ["x"] = prev_ms_ev.pos.x,
                    ["y"] = prev_ms_ev.pos.y,
                    ["slot"] = slot,
                },
            }
        end

        -- the first time fake_first_tev is nil, so self.first_tevs is automatically used instead
        local msd_direction, msd_distance
        if self.multiswipe_type == "straight" then
            msd_direction, msd_distance = self:getPath(slot, true, false, fake_first_tev)
        else
            msd_direction, msd_distance = self:getPath(slot, true, true, fake_first_tev)
        end

        if msd_distance > self.MULTISWIPE_THRESHOLD then
            local pan_ev_multiswipe = pan_ev
            -- store a copy of pan_ev without rotation adjustment
            -- for multiswipe calculations when rotated
            if self.screen:getTouchRotation() > self.screen.ORIENTATION_PORTRAIT then
                pan_ev_multiswipe = util.tableDeepCopy(pan_ev)
            end
            if msd_direction ~= msd_direction_prev then
                self.multiswipe_directions[msd_cnt+1] = {
                    [1] = msd_direction,
                    [2] = pan_ev_multiswipe,
                }
            -- update ongoing swipe direction to the new maximum
            else
                self.multiswipe_directions[msd_cnt] = {
                    [1] = msd_direction,
                    [2] = pan_ev_multiswipe,
                }
            end
        end

        return pan_ev
    end
end

function GestureDetector:handleTwoFingerPan(tev)
    -- triggering slot
    local tslot = tev.slot
    -- reference slot
    local rslot = tslot == 1 and 0 or 1
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
        logger.dbg(ges_ev.ges, ges_ev.direction, ges_ev.distance, "detected")
        return ges_ev
    elseif self.states[rslot] == self.holdState then
        local angle = self:getRotate(rstart_pos, tstart_pos, tend_pos)
        logger.dbg("rotate", angle, "detected")
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
        logger.dbg("two finger pan release detected")
        pan_ev.ges = "two_finger_pan_release"
        self:clearStates()
    else
        logger.dbg("pan release detected in slot", slot)
        self:clearState(slot)
    end
    return pan_ev
end

function GestureDetector:holdState(tev, hold)
    logger.dbg("in hold state...")
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
    elseif tev.id == -1 and self.last_tevs[slot] ~= nil then
        -- end of hold, signal hold release
        logger.dbg("hold_release detected in slot", slot)
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
    elseif (tev.x and math.abs(tev.x - self.first_tevs[slot].x) >= self.PAN_THRESHOLD) or
        (tev.y and math.abs(tev.y - self.first_tevs[slot].y) >= self.PAN_THRESHOLD) then
        local ges_ev = self:handlePan(tev)
        if ges_ev ~= nil then ges_ev.ges = "hold_pan" end
        return ges_ev
    end
end

local ges_coordinate_translation_270 = {
    north = "west",
    south = "east",
    east = "north",
    west = "south",
    northeast = "northwest",
    northwest = "southwest",
    southeast = "northeast",
    southwest = "southeast",
}
local ges_coordinate_translation_180 = {
    north = "south",
    south = "north",
    east = "west",
    west = "east",
    northeast = "southwest",
    northwest = "southeast",
    southeast = "northwest",
    southwest = "northeast",
}
local ges_coordinate_translation_90 = {
    north = "east",
    south = "west",
    east = "south",
    west = "north",
    northeast = "southeast",
    northwest = "northeast",
    southeast = "southwest",
    southwest = "northwest",
}
local function translateGesDirCoordinate(direction, translation_table)
    return translation_table[direction]
end
local function translateMultiswipeGesDirCoordinate(multiswipe_directions, translation_table)
    return multiswipe_directions:gsub("%S+", translation_table)
end

--[[--
  Changes gesture's `x` and `y` coordinates according to screen view mode.

  @param ges gesture that you want to adjust
  @return adjusted gesture.
--]]
function GestureDetector:adjustGesCoordinate(ges)
    local mode = self.screen:getTouchRotation()
    if mode == self.screen.ORIENTATION_LANDSCAPE then
        -- in landscape mode rotated 90
        if ges.pos then
            ges.pos.x, ges.pos.y = (self.screen:getWidth() - ges.pos.y), (ges.pos.x)
        end
        if ges.ges == "swipe" or ges.ges == "pan"
            or ges.ges == "multiswipe"
            or ges.ges == "two_finger_swipe"
            or ges.ges == "two_finger_pan"
        then
            ges.direction = translateGesDirCoordinate(ges.direction, ges_coordinate_translation_90)
            if ges.ges == "multiswipe" then
                ges.multiswipe_directions = translateMultiswipeGesDirCoordinate(ges.multiswipe_directions, ges_coordinate_translation_90)
            end
            if ges.relative then
                ges.relative.x, ges.relative.y = -ges.relative.y, ges.relative.x
                ges.relative_delayed.x, ges.relative_delayed.y = -ges.relative_delayed.y, ges.relative_delayed.x
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
    elseif mode == self.screen.ORIENTATION_LANDSCAPE_ROTATED then
        -- in landscape mode rotated 270
        if ges.pos then
            ges.pos.x, ges.pos.y = (ges.pos.y), (self.screen:getHeight() - ges.pos.x)
        end
        if ges.ges == "swipe" or ges.ges == "pan"
            or ges.ges == "multiswipe"
            or ges.ges == "two_finger_swipe"
            or ges.ges == "two_finger_pan"
        then
            ges.direction = translateGesDirCoordinate(ges.direction, ges_coordinate_translation_270)
            if ges.ges == "multiswipe" then
                ges.multiswipe_directions = translateMultiswipeGesDirCoordinate(ges.multiswipe_directions, ges_coordinate_translation_270)
            end
            if ges.relative then
                ges.relative.x, ges.relative.y = ges.relative.y, -ges.relative.x
                ges.relative_delayed.x, ges.relative_delayed.y = ges.relative_delayed.y, -ges.relative_delayed.x
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
    elseif mode == self.screen.ORIENTATION_PORTRAIT_ROTATED then
        -- in portrait mode rotated 180
        if ges.pos then
            ges.pos.x, ges.pos.y = (self.screen:getWidth() - ges.pos.x), (self.screen:getHeight() - ges.pos.y)
        end
        if ges.ges == "swipe" or ges.ges == "pan"
            or ges.ges == "multiswipe"
            or ges.ges == "two_finger_swipe"
            or ges.ges == "two_finger_pan"
        then
            ges.direction = translateGesDirCoordinate(ges.direction, ges_coordinate_translation_180)
            if ges.ges == "multiswipe" then
                ges.multiswipe_directions = translateMultiswipeGesDirCoordinate(ges.multiswipe_directions, ges_coordinate_translation_180)
            end
            if ges.relative then
                ges.relative.x, ges.relative.y = -ges.relative.x, -ges.relative.y
                ges.relative_delayed.x, ges.relative_delayed.y = -ges.relative_delayed.x, -ges.relative_delayed.y
            end
        elseif ges.ges == "pinch" or ges.ges == "spread"
                or ges.ges == "inward_pan"
                or ges.ges == "outward_pan" then
            if ges.direction == "horizontal" then
                ges.direction = "horizontal"
            elseif ges.direction == "vertical" then
                ges.direction = "vertical"
            end
        end
    end
    logger.dbg("adjusted ges:", ges.ges, ges.multiswipe_directions or ges.direction)
    return ges
end

return GestureDetector
