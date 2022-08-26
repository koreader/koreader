--[[--
This module detects gestures.

Current detectable gestures:

* `touch` (emitted once on first contact down, unless it's a pan)
* `tap` (touch action detected as single tap)
* `pan`
* `hold`
* `swipe`
* `pinch`
* `spread`
* `rotate`
* `hold_pan` (will emit `hold_release` on contact lift, unlike its two-finger variant)
* `double_tap`
* `inward_pan`
* `outward_pan`
* `pan_release`
* `hold_release`
* `two_finger_hold`
* `two_finger_hold_release`
* `two_finger_tap`
* `two_finger_pan`
* `two_finger_hold_pan`
* `two_finger_swipe`
* `two_finger_pan_release`
* `two_finger_hold_pan_release`

You change the state machine by feeding it touch events, i.e. calling
@{GestureDetector:feedEvent|GestureDetector:feedEvent(tev)}.


a touch event should have following format:

    tev = {
        slot = 1,
        id = 46,
        x = 0,
        y = 1,
        timev = time.s(123.23),
    }

Don't confuse `tev` with raw evs from kernel, `tev` is built according to ev.

@{GestureDetector:feedEvent|GestureDetector:feedEvent(tev)} will return a
detection result when you feed a touch release event to it.
--]]

local Geom = require("ui/geometry")
local logger = require("logger")
local time = require("ui/time")
local util = require("util")

-- We're going to need some clockid_t constants
local ffi = require("ffi")
local C = ffi.C
require("ffi/posix_h")

-- default values (time parameters are in milliseconds (ms))
local TAP_INTERVAL_MS = 0
local DOUBLE_TAP_INTERVAL_MS = 300
local TWO_FINGER_TAP_DURATION_MS = 300
local HOLD_INTERVAL_MS = 500
local SWIPE_INTERVAL_MS = 900

local GestureDetector = {
    -- must be initialized with the Input singleton class
    input = nil,
    -- default values (accessed for display by plugins/gestures.koplugin)
    TAP_INTERVAL_MS = TAP_INTERVAL_MS,
    DOUBLE_TAP_INTERVAL_MS = DOUBLE_TAP_INTERVAL_MS,
    TWO_FINGER_TAP_DURATION_MS = TWO_FINGER_TAP_DURATION_MS,
    HOLD_INTERVAL_MS = HOLD_INTERVAL_MS,
    SWIPE_INTERVAL_MS = SWIPE_INTERVAL_MS,
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
    -- Hash of our currently active contacts
    active_contacts = {},
    contact_count = 0,
    -- Used for double tap and bounce detection (this is outside a Contact object because it requires minimal persistance).
    previous_tap = {},
    -- for timestamp clocksource detection
    clock_id = nil,
    -- current values
    ges_tap_interval = time.ms(G_reader_settings:readSetting("ges_tap_interval_ms") or TAP_INTERVAL_MS),
    ges_double_tap_interval = time.ms(G_reader_settings:readSetting("ges_double_tap_interval_ms")
        or DOUBLE_TAP_INTERVAL_MS),
    ges_two_finger_tap_duration = time.ms(G_reader_settings:readSetting("ges_two_finger_tap_duration_ms")
        or TWO_FINGER_TAP_DURATION_MS),
    ges_hold_interval = time.ms(G_reader_settings:readSetting("ges_hold_interval_ms") or HOLD_INTERVAL_MS),
    ges_swipe_interval = time.ms(G_reader_settings:readSetting("ges_swipe_interval_ms") or SWIPE_INTERVAL_MS),
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
    self.SINGLE_TAP_BOUNCE_DISTANCE = self.DOUBLE_TAP_DISTANCE
    self.PAN_THRESHOLD = self.DOUBLE_TAP_DISTANCE
    self.MULTISWIPE_THRESHOLD = self.DOUBLE_TAP_DISTANCE
end

-- Contact object, it'll keep track of everything we need for a single contact across its lifetime
-- (which should be a single gesture, i.e., from this contact's down to up (and up of its paired contacts for MT gestures)).
-- We'll identify contacts by their slot numbers, and store 'em in GestureDetector's active_contacts table (hash).
local Contact = {} -- Class object is empty, as we do *NOT* want inheritance outside of methods.
function Contact:new(o)
    setmetatable(o, self)
    self.__index = self
    return o
end

function GestureDetector:newContact(slot)
    -- Check if this new contact might be part of a two finger gesture,
    -- by checking if the current slot is one of the two main slots, and the other is active.
    local buddy_slot = slot == self.input.main_finger_slot and self.input.main_finger_slot + 1 or
                       slot == self.input.main_finger_slot + 1 and self.input.main_finger_slot
    local buddy_contact = buddy_slot and self:getContact(buddy_slot)

    self.active_contacts[slot] = Contact:new{
        state = Contact.initialState, -- Current state function
        slot = slot, -- Current ABS_MT_SLOT value (also its key in the active_contacts hash)
        id = -1, -- Current ABS_MT_TRACKING_ID value
        initial_tev = nil, -- Copy of the input event table at first contact (i.e., at contact down)
        current_tev = nil, -- Pointer to the current input event table, *stable*, c.f., NOTE in feedEvent below
        down = false, -- Contact is down (as opposed to up, i.e., lifted)
        pending_double_tap_timer = false, -- Contact is pending a double_tap timer
        pending_hold_timer = false, -- Contact is pending a hold timer
        pending_mt_gesture = nil, -- Contact is pending a MT gesture (string, gesture name)
        multiswipe_directions = {}, -- Accumulated multiswipe chain for this contact
        multiswipe_type = nil, -- Current multiswipe type for this contact
        buddy_contact = buddy_contact, -- Ref to the paired contact in a MT gesture (if any)
        ges_dec = self, -- Ref to the current GestureDetector instance
    }
    self.contact_count = self.contact_count + 1
    logger.dbg("New contact for slot", slot, "#contacts =", self.contact_count)

    -- If we have a buddy contact, point its own buddy ref to us
    if buddy_contact then
        buddy_contact.buddy_contact = self.active_contacts[slot]
        logger.dbg("It's an MT buddy with slot", buddy_slot)
    end

    return self.active_contacts[slot]
end

function GestureDetector:getContact(slot)
    return self.active_contacts[slot]
end

function GestureDetector:dropContact(contact)
    local slot = contact.slot

    -- Guard against double drops
    if not self.active_contacts[slot] then
        logger.warn("Contact for slot", slot, "has already been dropped! #contacts =", self.contact_count)
        return
    end

    -- Also clear any pending callbacks on that slot.
    if contact.pending_double_tap_timer then
        self.input:clearTimeout(slot, "double_tap")
        contact.pending_double_tap_timer = nil
    end
    if contact.pending_hold_timer then
        self.input:clearTimeout(slot, "hold")
        contact.pending_hold_timer = nil
    end

    -- If we have a buddy contact, drop its buddy ref to us
    if contact.buddy_contact then
        contact.buddy_contact.buddy_contact = nil
    end

    self.active_contacts[slot] = nil
    self.contact_count = self.contact_count - 1
    logger.dbg("Dropped contact for slot", slot, "#contacts =", self.contact_count)
end

function GestureDetector:dropContacts()
    for _, contact in pairs(self.active_contacts) do
        self:dropContact(contact)
    end
end

--[[--
Feeds touch events to state machine.

Note that, in a single input frame, if the same slot gets multiple events, only the last one is kept.
Every slot in the input frame is consumed, and that in FIFO order (slot order based on appearance in the frame).
--]]
function GestureDetector:feedEvent(tevs)
    local gestures = {}
    for _, tev in ipairs(tevs) do
        local slot = tev.slot
        local contact = self:getContact(slot)
        if not contact then
            contact = self:newContact(slot)
            -- NOTE: tev is actually a simple reference to Input's self.ev_slots[slot],
            --       which means a Contact's current_tev doesn't actually point to the *previous*
            --       input frame for a given slot, but always points to the *current* input frame for that slot!
            --       Meaning the tev we feed the state function *always* matches that Contact's current_tev.
            --       Compare to initial_tev below, which does create a copy...
            -- This is what allows us to only do this once on contact creation ;).
            contact.current_tev = tev
        end
        local ges = contact.state(contact)
        if ges then
            table.insert(gestures, ges)
        end
    end
    return gestures
end

local function deepCopyEv(tev)
    return {
        x = tev.x,
        y = tev.y,
        id = tev.id,
        slot = tev.slot,
        timev = tev.timev, -- No need to make a copy of this one, tev.timev is re-assigned to a new object on every SYN_REPORT
    }
end

--[[
tap2 is the later tap
--]]
function GestureDetector:isTapBounce(tap1, tap2, interval)
    -- NOTE: If time went backwards, make the delta infinite to avoid misdetections,
    --       as we can no longer compute a sensible value...
    local time_diff = tap2.timev - tap1.timev
    if time_diff < 0 then
        time_diff = time.huge
    end
    return (
        math.abs(tap1.x - tap2.x) < self.SINGLE_TAP_BOUNCE_DISTANCE and
        math.abs(tap1.y - tap2.y) < self.SINGLE_TAP_BOUNCE_DISTANCE and
        time_diff < interval
    )
end

function GestureDetector:isDoubleTap(tap1, tap2)
    local time_diff = tap2.timev - tap1.timev
    if time_diff < 0 then
        time_diff = time.huge
    end
    logger.dbg("GestureDetector:isDoubleTap", tap1, tap2)
    return (
        math.abs(tap1.x - tap2.x) < self.DOUBLE_TAP_DISTANCE and
        math.abs(tap1.y - tap2.y) < self.DOUBLE_TAP_DISTANCE and
        time_diff < self.ges_double_tap_interval
    )
end

-- Takes times as input, not a tev
function GestureDetector:isHold(time1, time2)
    local time_diff = time2 - time1
    if time_diff < 0 then
        time_diff = 0
    end
    -- NOTE: We cheat by not checking a distance because we're only checking that in tapState,
    --       which already ensures a stationary finger, by elimination ;).
    return time_diff >= self.ges_hold_interval
end

function Contact:isTwoFingerTap(buddy_contact)
    local gesture_detector = self.ges_dec

    local x_diff0 = math.abs(self.current_tev.x - self.initial_tev.x)
    local x_diff1 = math.abs(buddy_contact.current_tev.x - buddy_contact.initial_tev.x)
    local y_diff0 = math.abs(self.current_tev.y - self.initial_tev.y)
    local y_diff1 = math.abs(buddy_contact.current_tev.y - buddy_contact.initial_tev.y)
    local time_diff0 = self.current_tev.timev - self.initial_tev.timev
    if time_diff0 < 0 then
        time_diff0 = time.huge
    end
    local time_diff1 = buddy_contact.current_tev.timev - buddy_contact.initial_tev.timev
    if time_diff1 < 0 then
        time_diff1 = time.huge
    end
    logger.dbg("Contact:isTwoFingerTap: x_diff0:", x_diff0, "x_diff1:", x_diff1, "y_diff0:", y_diff0, "y_diff1:", y_diff1, "TWO_FINGER_TAP_REGION:", gesture_detector.TWO_FINGER_TAP_REGION, "time_diff0:", time_diff0, "time_diff1:", time_diff1, "ges_two_finger_tap_duration:", gesture_detector.ges_two_finger_tap_duration)
    return (
        x_diff0 < gesture_detector.TWO_FINGER_TAP_REGION and
        x_diff1 < gesture_detector.TWO_FINGER_TAP_REGION and
        y_diff0 < gesture_detector.TWO_FINGER_TAP_REGION and
        y_diff1 < gesture_detector.TWO_FINGER_TAP_REGION and
        time_diff0 < gesture_detector.ges_two_finger_tap_duration and
        time_diff1 < gesture_detector.ges_two_finger_tap_duration
    )
end

--[[--
Compares `current_tev` with `initial_tev` in this slot.

The second boolean argument `simple` results in only four directions if true.

@return (direction, distance) pan direction and distance
--]]
function Contact:getPath(simple, diagonal, initial_tev)
    initial_tev = initial_tev or self.initial_tev

    local x_diff = self.current_tev.x - initial_tev.x
    local y_diff = self.current_tev.y - initial_tev.y
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
            direction = v_direction .. h_direction
        elseif (math.abs(x_diff) > math.abs(y_diff)) then
            direction = h_direction
        else
            direction = v_direction
        end
    end
    return direction, distance
end

function Contact:isSwipe()
    local gesture_detector = self.ges_dec

    local time_diff = self.current_tev.timev - self.initial_tev.timev
    if time_diff < 0 then
        time_diff = time.huge
    end
    if time_diff < gesture_detector.ges_swipe_interval then
        local x_diff = self.current_tev.x - self.initial_tev.x
        local y_diff = self.current_tev.y - self.initial_tev.y
        if x_diff ~= 0 or y_diff ~= 0 then
            return true
        end
    end
end

function GestureDetector:getRotate(orig_point, start_point, end_point)
    --[[
    local a = orig_point:distance(start_point)
    local b = orig_point:distance(end_point)
    local c = start_point:distance(end_point)
    return math.acos((a*a + b*b - c*c)/(2*a*b))*180/math.pi
    --]]

    -- NOTE: I am severely maths impaired, and I just wanted something that preserved rotation direction (CCW if < 0),
    --       so this is shamelessly stolen from https://stackoverflow.com/a/31334882
    --       & https://stackoverflow.com/a/21484228
    local rad = math.atan2(end_point.y - orig_point.y, end_point.x - orig_point.x) -
                math.atan2(start_point.y - orig_point.y, start_point.x - orig_point.x)
    -- Normalize to [-180, 180]
    if rad < -math.pi then
        rad = rad + 2 * math.pi
    elseif rad > math.pi then
        rad = rad - 2 * math.pi
    end
    return rad * 180/math.pi
end

function Contact:switchState(state_func, ...)
    self.state = state_func
    return state_func(self, ...)
end

function Contact:initialState()
    local tev = self.current_tev

    if tev.id then
        -- Contact lift
        if tev.id == -1 then
            -- If this slot was a buddy slot that happened to be dropped by a MT gesture in the *same* input frame,
            -- a lift might be the first thing we process here... We can safely drop it again.
            logger.dbg("Contact:initialState Cancelled a gesture in slot", self.slot)
            self.ges_dec:dropContact(self)
        else
            self.id = tev.id
            if tev.x and tev.y then
                -- Contact down, user starts a new touch motion
                if not self.down then
                    self.down = true
                    -- NOTE: We can't use a simple reference, because tev is actually Input's self.ev_slots[slot],
                    --       and *that* is a fixed reference for a given slot!
                    --       Here, we really want to remember the *first* tev, so, make a copy of it.
                    self.initial_tev = deepCopyEv(tev)
                    -- Default to tap state, indicating that this is a new contact
                    return self:switchState(Contact.tapState, true)
                end
            end
        end
    end
end

--[[--
Attempts to figure out which clock source tap events are using...
]]
function GestureDetector:probeClockSource(timev)
    -- We'll check if that timestamp is +/- 2.5s away from the three potential clock sources supported by evdev.
    -- We have bigger issues than this if we're parsing events more than 3s late ;).
    local threshold = time.s(2) + time.ms(500)

    -- Start w/ REALTIME, because it's the easiest to detect ;).
    local realtime = time.realtime_coarse()
    -- clock-threshold <= timev <= clock+threshold
    if timev >= realtime - threshold and timev <= realtime + threshold then
        self.clock_id = C.CLOCK_REALTIME
        logger.dbg("GestureDetector:probeClockSource: Touch event timestamps appear to use CLOCK_REALTIME")
        return
    end

    -- Then MONOTONIC, as it's (hopefully) more common than BOOTTIME (and also guaranteed to be an usable clock source)
    local monotonic = time.monotonic_coarse()
    if timev >= monotonic - threshold and timev <= monotonic + threshold then
        self.clock_id = C.CLOCK_MONOTONIC
        logger.dbg("GestureDetector:probeClockSource: Touch event timestamps appear to use CLOCK_MONOTONIC")
        return
    end

    -- Finally, BOOTTIME
    local boottime = time.boottime()
    -- NOTE: It was implemented in Linux 2.6.39, so, reject 0, which would mean it's unsupported...
    if not boottime == 0 and timev >= boottime - threshold and timev <= boottime + threshold then
        self.clock_id = C.CLOCK_BOOTTIME
        logger.dbg("GestureDetector:probeClockSource: Touch event timestamps appear to use CLOCK_BOOTTIME")
        return
    end

    -- If we're here, the detection was inconclusive :/
    self.clock_id = -1
    logger.dbg("GestureDetector:probeClockSource: Touch event clock source detection was inconclusive")
    -- Print all all the gory details in debug mode when this happens...
    logger.dbg("Input frame    :", time.format_time(timev))
    logger.dbg("CLOCK_REALTIME :", time.format_time(realtime))
    logger.dbg("CLOCK_MONOTONIC:", time.format_time(monotonic))
    logger.dbg("CLOCK_BOOTTIME :", time.format_time(boottime))
end

function GestureDetector:getClockSource()
    return self.clock_id
end

function GestureDetector:resetClockSource()
    self.clock_id = nil
end

--[[--
Handles both single and double tap. `new_tap` is true for the initial contact down event.
--]]
function Contact:tapState(new_tap)
    local slot = self.slot
    local tev = self.current_tev
    local buddy_contact = self.buddy_contact
    local buddy_slot = buddy_contact and self.buddy_contact.slot
    local gesture_detector = self.ges_dec

    -- Attempt to detect the clock source for these events (we reset it on suspend to discriminate MONOTONIC from BOOTTIME).
    if not gesture_detector.clock_id then
        gesture_detector:probeClockSource(tev.timev)
    end

    logger.dbg("slot", slot, "in tap state...")
    -- Contact lift
    if tev.id == -1 then
        if buddy_contact and self.down and (buddy_contact.down or buddy_contact.pending_mt_gesture == "tap") then
            -- Both main contacts are actives, and we're currently down, while our buddy is still down or pending a MT gesture
            if self:isTwoFingerTap(buddy_contact) then
                -- Mark that slot as pending and lifted, but leave its state alone
                self.pending_mt_gesture = "tap"
                self.down = false
                logger.dbg("Flagged slot", slot, "as pending a two_finger_tap")

                -- Once both contacts have been lifted, we're good to go!
                if self.pending_mt_gesture == "tap" and buddy_contact.pending_mt_gesture == "tap" then
                    local pos0 = Geom:new{
                        x = tev.x,
                        y = tev.y,
                        w = 0,
                        h = 0,
                    }
                    local pos1 = Geom:new{
                        x = buddy_contact.current_tev.x,
                        y = buddy_contact.current_tev.y,
                        w = 0,
                        h = 0,
                    }
                    local tap_span = pos0:distance(pos1)
                    logger.dbg("two_finger_tap detected with span", tap_span)
                    gesture_detector:dropContact(self)
                    gesture_detector:dropContact(buddy_contact)
                    return {
                        ges = "two_finger_tap",
                        pos = pos0:midpoint(pos1),
                        span = tap_span,
                        time = tev.timev,
                    }
                end
            else
                logger.dbg("Two finger tap failed to pass the two_finger_tap constraints")
                -- One of the slot is down or pending a double tap, but we blew the gesture position/time constraints,
                -- drop both slots and send a single tap on this slot.
                gesture_detector:dropContact(self)
                gesture_detector:dropContact(buddy_contact)

                return {
                    ges = "tap",
                    pos = Geom:new{
                        x = tev.x,
                        y = tev.y,
                        w = 0,
                        h = 0,
                    },
                    time = tev.timev,
                }
            end
        elseif self.pending_mt_gesture == "rotate" then
            -- If we were flagged as pending a rotate, but have yet to hit either hold or pan state,
            -- do it now to avoid leaving our buddy slot hanging...
            return self:switchState(Contact.panState)
        else
            -- What's left to go through is ST, if we still have a stale buddy, it's time to get rid of it.
            if buddy_contact and buddy_contact.down == false then
                logger.dbg("Contact:tapState Dropped stale buddy on slot", buddy_contact.slot)
                gesture_detector:dropContact(buddy_contact)
                buddy_contact = nil
            end
            if self.down or self.pending_double_tap_timer then
                -- Hand over to the double tap handler, it's responsible for downgrading to single tap
                return self:handleDoubleTap()
            end
        end
        -- If both contacts are up and we haven't detected any gesture, forget about 'em (should never happen).
        if buddy_contact and self.down == false and buddy_contact.down == false then
            logger.warn("Contact:tapState Cancelled gestures in slots", slot, buddy_slot)
            gesture_detector:dropContact(self)
            gesture_detector:dropContact(buddy_contact)
        elseif not buddy_contact and self.down == false then
            -- Huh, caught a *second* contact lift for this contact? (should never happen).
            logger.warn("Contact:tapState Cancelled a gesture in slot", slot)
            gesture_detector:dropContact(self)
        end
    else
        -- See if we need to do something with the move/hold
        local ges = self:handleNonTap(new_tap)
        -- NOTE: If buddy is up (because of a tapState pending_mt_gesture, i.e., "tap") and this made us switch to another state,
        --       drop buddy now, because we won't ever be a match with it again.
        if buddy_contact and buddy_contact.down == false and buddy_contact.pending_mt_gesture == "tap" and
           self.state ~= Contact.tapState then
            logger.warn("Contact:tapState Cancelled a two-finger tap gesture in slot", buddy_slot, "because slot", slot, "switched to an incompatible state")
            gesture_detector:dropContact(buddy_contact)
        end
        return ges
    end
end

--[[--
Emits both tap & double_tap gestures. Contact is either down or pending a double_tap timer.
--]]
function Contact:handleDoubleTap()
    local slot = self.slot
    logger.dbg("Contact:handleDoubleTap for slot", slot)
    local tev = self.current_tev
    local gesture_detector = self.ges_dec

    local ges_ev = {
        -- Default to single tap
        ges = "tap",
        pos = Geom:new{
            x = tev.x,
            y = tev.y,
            w = 0,
            h = 0,
        },
        time = tev.timev,
    }
    -- cur_tap is used for double tap and bounce detection
    local cur_tap = {
        x = tev.x,
        y = tev.y,
        timev = tev.timev,
    }

    -- Tap interval / bounce detection may be tweaked by a widget (i.e. VirtualKeyboard)
    local tap_interval = gesture_detector.input.tap_interval_override or gesture_detector.ges_tap_interval
    -- We do tap bounce detection even when double tap is enabled
    -- (so, double tap is triggered when: ges_tap_interval <= delay < ges_double_tap_interval).
    if tap_interval ~= 0 and gesture_detector.previous_tap[slot] ~= nil and gesture_detector:isTapBounce(gesture_detector.previous_tap[slot], cur_tap, tap_interval) then
        logger.dbg("tap bounce detected in slot", slot, ": ignored")
        -- Simply ignore it, and drop this slot as this is the end of a touch event.
        gesture_detector:dropContact(self)
        return
    end

    if not gesture_detector.input.disable_double_tap and self.pending_double_tap_timer and gesture_detector:isDoubleTap(gesture_detector.previous_tap[slot], cur_tap) then
        -- It is a double tap
        gesture_detector:dropContact(self)
        ges_ev.ges = "double_tap"
        logger.dbg("double tap detected in slot", slot)
        return ges_ev
    end

    -- Remember this tap
    gesture_detector.previous_tap[slot] = cur_tap
    logger.dbg("Set previous_tap for slot", slot, cur_tap)

    if gesture_detector.input.disable_double_tap then
        -- We can send the event immediately (no need for the timer stuff needed for double tap support)
        logger.dbg("single tap detected in slot", slot, ges_ev.pos)
        gesture_detector:dropContact(self)
        return ges_ev
    end

    -- Double tap enabled: we can't send this single tap immediately as it may be the start of a double tap.
    -- We'll send it as a single tap after a timer if no second tap happened in the double tap delay.
    if not self.pending_double_tap_timer then
        logger.dbg("set up double_tap timer for slot", slot)
        self.pending_double_tap_timer = true
        -- setTimeout will handle computing the deadline in the least lossy way possible given the platform.
        gesture_detector.input:setTimeout(slot, "double_tap", function()
            if self == gesture_detector:getContact(slot) and self.pending_double_tap_timer then
                self.pending_double_tap_timer = false
                if self.state == Contact.tapState then
                    -- A single or double tap will yield a different contact object, by virtue of dropContact and closure magic ;).
                    -- Speaking of closures, this is the original ges_ev from the timer setup.
                    logger.dbg("double_tap timer detected a single tap in slot", slot, ges_ev.pos)
                    gesture_detector:dropContact(self)
                    return ges_ev
                end
            end
        end, tev.timev, gesture_detector.ges_double_tap_interval)
    end
    -- Regardless of the timer shenanigans, it's at the very least a contact lift,
    -- (and calling dropContact here would break the timer).
    self.down = false
    logger.dbg("Contact:handleDoubleTap Contact lift for slot", slot)
end

--[[--
Handles move (switch to panState) & hold (switch to holdState). Contact is down.
`new_tap` is true for the initial contact down event.
--]]
function Contact:handleNonTap(new_tap)
    local slot = self.slot
    logger.dbg("Contact:handleNonTap for slot", slot)
    local tev = self.current_tev
    local gesture_detector = self.ges_dec

    -- If we haven't yet fired the hold timer, do so first and foremost, as hold_pan handling *requires* a hold.
    -- We only do this on the first contact down.
    if new_tap and not self.pending_hold_timer then
        logger.dbg("set up hold timer for slot", slot)
        self.pending_hold_timer = true
        gesture_detector.input:setTimeout(slot, "hold", function()
            -- If the pending_hold_timer we set on our first switch to tapState on this slot (e.g., first finger down event),
            -- back when the timer was setup, is still relevant (e.g., the slot wasn't run through dropContact by a finger up gesture),
            -- then check that we're still in a stationary finger down state (e.g., tapState).
            -- NOTE: We need to check that the current contact in this slot is *still* the same object first, because closure ;).
            if self == gesture_detector:getContact(slot) and self.pending_hold_timer then
                self.pending_hold_timer = nil
                if self.state == Contact.tapState and self.down then
                    -- NOTE: If we happened to have moved enough, holdState will generate a hold_pan on the *next* event,
                    --       but for now, the initial hold is mandatory.
                    --       On the other hand, if we're *already* in pan state, we stay there and don't switch to hold.
                    logger.dbg("hold timer detected a hold gesture in slot", slot)
                    return self:switchState(Contact.holdState, true)
                end
            end
        end, tev.timev, gesture_detector.ges_hold_interval)

        -- NOTE: We only generate touch *once*, on contact down (assuming it isn't a pan...)
        return {
            ges = "touch",
            pos = Geom:new{
                x = tev.x,
                y = tev.y,
                w = 0,
                h = 0,
            },
            time = tev.timev,
        }
    else
        -- Once the hold timer has been fired, we're free to see if we can switch to pan,
        -- if the contact moved far enough on the X or Y axes...
        if (math.abs(tev.x - self.initial_tev.x) >= gesture_detector.PAN_THRESHOLD) or
           (math.abs(tev.y - self.initial_tev.y) >= gesture_detector.PAN_THRESHOLD) then
            return self:switchState(Contact.panState)
        end
    end
end

--[[--
Handles the full panel of pans & swipes, including their two-finger variants.
--]]
function Contact:panState()
    local slot = self.slot
    local tev = self.current_tev
    local buddy_contact = self.buddy_contact
    local buddy_slot = buddy_contact and self.buddy_contact.slot
    local gesture_detector = self.ges_dec

    logger.dbg("slot", slot, "in pan state...")
    if tev.id == -1 then
        -- End of pan, signal swipe gesture if necessary
        if self:isSwipe() then
            if buddy_contact and self.down and
               (buddy_contact.down or buddy_contact.pending_mt_gesture == "swipe" or buddy_contact.pending_mt_gesture == "rotate") then
                -- Both main contacts are actives, and we're currently down, while our buddy is still down or pending a MT gesture
                -- Mark that slot as pending and lifted, but leave its state alone
                self.pending_mt_gesture = "swipe"
                self.down = false
                logger.dbg("Flagged slot", slot, "as pending a two_finger_swipe/pinch/spread")

                -- NOTE: There's a slight trickery involved here to handle the rotate gesture,
                --       which requires contact to have been lifted, but buddy_contact to still be in hold state...
                if self.pending_mt_gesture == "swipe" and
                   (buddy_contact.pending_mt_gesture == "swipe" or buddy_contact.pending_mt_gesture == "rotate" or
                   (buddy_contact.down and buddy_contact.state == Contact.holdState)) then
                    local ges_ev = self:handleTwoFingerPan(buddy_contact)
                    if ges_ev then
                        if buddy_contact.pending_mt_gesture == "swipe" then
                            -- Only accept gestures that require both contacts to have been lifted
                            if ges_ev.ges == "two_finger_pan" then
                                ges_ev.ges = "two_finger_swipe"
                            elseif ges_ev.ges == "inward_pan" then
                                ges_ev.ges = "pinch"
                            elseif ges_ev.ges == "outward_pan" then
                                ges_ev.ges = "spread"
                            else
                                ges_ev = nil
                            end
                        else
                            -- Only accept the rotate gesture
                            if ges_ev.ges ~= "rotate" then
                                ges_ev = nil
                            end
                        end

                        if ges_ev then
                            logger.dbg(ges_ev.ges, ges_ev.direction, ges_ev.distance or math.abs(ges_ev.angle), "detected")
                            if ges_ev.ges == "rotate" then
                                -- For rotate, only drop contact right now (as it's the only contact lift),
                                -- buddy should already have been neutered via a switch to voidState.
                                gesture_detector:dropContact(self)
                            else
                                gesture_detector:dropContact(self)
                                gesture_detector:dropContact(buddy_contact)
                            end
                            return ges_ev
                        end
                    end
                end
            else
                -- What's left to go through is ST, if we still have a stale buddy, it's time to get rid of it.
                if buddy_contact and buddy_contact.down == false then
                    logger.dbg("Contact:panState Dropped stale buddy on slot", buddy_contact.slot)
                    gesture_detector:dropContact(buddy_contact)
                    buddy_contact = nil
                end
                if self.down then
                    return self:handleSwipe()
                end
            end
        -- If the contact lift is not a swipe, then it's a pan.
        elseif self.down then
            return self:handlePanRelease()
        end
        -- If both contacts are up and we haven't detected any gesture, forget about 'em (should ideally not happen)
        if buddy_contact and self.down == false and buddy_contact.down == false then
            logger.warn("Contact:panState Cancelled gestures in slots", slot, buddy_slot)
            gesture_detector:dropContact(self)
            gesture_detector:dropContact(buddy_contact)
        elseif not buddy_contact and self.down == false then
            -- Huh, caught a *second* contact lift for this contact? (should never happen).
            logger.warn("Contact:panState Cancelled a gesture in slot", slot)
            gesture_detector:dropContact(self)
        end
    else
        return self:handlePan()
    end
end

--[[--
Used to ignore a buddy slot part of a MT gesture that requires staggered contact lifts (i.e., rotate)
--]]
function Contact:voidState()
    local slot = self.slot
    local tev = self.current_tev
    local buddy_contact = self.buddy_contact
    local buddy_slot = buddy_contact and self.buddy_contact.slot
    local gesture_detector = self.ges_dec

    logger.dbg("slot", slot, "in void state...")
    -- We basically don't do anything but drop the slot on contact lift
    if tev.id == -1 then
        -- What's left to go through is ST, if we still have a stale buddy, it's time to get rid of it.
        if buddy_contact and buddy_contact.down == false then
            logger.dbg("Contact:voidState Dropped stale buddy on slot", buddy_contact.slot)
            gesture_detector:dropContact(buddy_contact)
            buddy_contact = nil
        end
        if self.down then
            logger.dbg("Contact:voidState Contact lift detected in slot", slot)
            gesture_detector:dropContact(self)
        end
        -- If both contacts are up, forget about 'em (should ideally not happen)
        if buddy_contact and self.down == false and buddy_contact.down == false then
            logger.warn("Contact:voidState Cancelled gestures in slots", slot, buddy_slot)
            gesture_detector:dropContact(self)
            gesture_detector:dropContact(buddy_contact)
        elseif not buddy_contact and self.down == false then
            -- Huh, caught a *second* contact lift for this contact? (should never happen).
            logger.warn("Contact:voidState Cancelled a gesture in slot", slot)
            gesture_detector:dropContact(self)
        end
    end
end

--[[--
Emits the swipe & multiswipe gestures. Contact is up. ST only (i.e., there isn't any buddy contact active).
--]]
function Contact:handleSwipe()
    local slot = self.slot
    logger.dbg("Contact:handleSwipe for slot", slot)
    local tev = self.current_tev
    local gesture_detector = self.ges_dec

    local swipe_direction, swipe_distance = self:getPath()
    local start_pos = Geom:new{
        x = self.initial_tev.x,
        y = self.initial_tev.y,
        w = 0,
        h = 0,
    }
    local ges = "swipe"
    local multiswipe_directions

    if #self.multiswipe_directions > 1 then
        ges = "multiswipe"
        multiswipe_directions = ""
        for k, v in ipairs(self.multiswipe_directions) do
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
    gesture_detector:dropContact(self)
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

--[[--
Emits the pan gestures and handles their two finger variants. Contact is down (and either in holdState or panState).
--]]
function Contact:handlePan()
    local slot = self.slot
    logger.dbg("Contact:handlePan for slot", slot)
    local tev = self.current_tev
    local buddy_contact = self.buddy_contact
    local buddy_slot = buddy_contact and self.buddy_contact.slot
    local gesture_detector = self.ges_dec

    if buddy_contact and self.down and (buddy_contact.down or buddy_contact.pending_mt_gesture == "pan") then
        -- Both main contacts are actives, and we're currently down, while our buddy is still down or pending a MT gesture
        -- Mark that slot as pending, but leave its state alone.
        -- NOTE: Might *already* be flagged as pending a pan, the check is just to limit logging
        if self.pending_mt_gesture ~= "pan" then
            self.pending_mt_gesture = "pan"
            logger.dbg("Flagged slot", slot, "as pending a two_finger_pan/two_finger_hold_pan")
        end
        -- NOTE: If buddy isn't already in holdState, and isn't already flagged for a gesture,
        --       leave a flag so that we might skip the hold gesture for rotate when it switches to holdState...
        if buddy_contact.state == Contact.tapState and not buddy_contact.pending_mt_gesture then
            buddy_contact.pending_mt_gesture = "rotate"
            logger.dbg("Flagged slot", buddy_slot, "as pending a potential rotate")
        end

        -- Once both contacts have been flagged, we're good to go!
        -- (Keep in mind that holdState can call handlePan, so either contact can be in panState or holdState).
        if self.pending_mt_gesture == "pan" and buddy_contact.pending_mt_gesture == "pan" then
            -- This is *NOT* a contact lift, unlike most other two finger gestures ;).
            self.pending_mt_gesture = nil
            buddy_contact.pending_mt_gesture = nil
            logger.dbg("Cleared the pending two_finger_pan/two_finger_hold_pan flag for slots", slot, buddy_slot)
            return self:handleTwoFingerPan(buddy_contact)
        end
    else
        local pan_direction, pan_distance = self:getPath()
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

        -- Regular pan
        pan_ev.relative.x = tev.x - self.initial_tev.x
        pan_ev.relative.y = tev.y - self.initial_tev.y

        pan_ev.pos = Geom:new{
            x = tev.x,
            y = tev.y,
            w = 0,
            h = 0,
        }

        local msd_cnt = #self.multiswipe_directions
        local msd_direction_prev = (msd_cnt > 0) and self.multiswipe_directions[msd_cnt][1] or ""
        local prev_ms_ev, fake_initial_tev

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
            fake_initial_tev = {
                x = prev_ms_ev.pos.x,
                y = prev_ms_ev.pos.y,
            }
        end

        -- the first time fake_initial_tev is nil, so the contact's initial_tev is automatically used instead
        local msd_direction, msd_distance
        if self.multiswipe_type == "straight" then
            msd_direction, msd_distance = self:getPath(true, false, fake_initial_tev)
        else
            msd_direction, msd_distance = self:getPath(true, true, fake_initial_tev)
        end

        if msd_distance > gesture_detector.MULTISWIPE_THRESHOLD then
            local pan_ev_multiswipe = pan_ev
            -- store a copy of pan_ev without rotation adjustment
            -- for multiswipe calculations when rotated
            if gesture_detector.screen:getTouchRotation() > gesture_detector.screen.ORIENTATION_PORTRAIT then
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

--[[--
Emits the pan, two_finger_pan, two_finger_hold_pan, inward_pan, outward_pan & rotate gestures.
Contact is down in panState or holdState, or up in panState if it was lifted below the swipe interval.
--]]
function Contact:handleTwoFingerPan(buddy_contact)
    logger.dbg("Contact:handleTwoFingerPan for slot", self.slot)
    local gesture_detector = self.ges_dec

    -- triggering contact is self
    -- reference contact is buddy_contact
    local tpan_dir, tpan_dis = self:getPath()
    local tstart_pos = Geom:new{
        x = self.initial_tev.x,
        y = self.initial_tev.y,
        w = 0,
        h = 0,
    }
    local tend_pos = Geom:new{
        x = self.current_tev.x,
        y = self.current_tev.y,
        w = 0,
        h = 0,
    }
    local rstart_pos = Geom:new{
        x = buddy_contact.initial_tev.x,
        y = buddy_contact.initial_tev.y,
        w = 0,
        h = 0,
    }
    if self.current_tev.id == -1 and buddy_contact.state == Contact.holdState and self.state == Contact.panState then
        -- NOTE: We only handle the rotate gesture when triggered by the just lifted pan finger
        --       (actually, it needs to pass the swipe interval check, but it is in panState),
        --       because this gesture would be too difficult to discriminate from a pinch/spread the other way around ;).
        --       TL;DR: Both fingers need to move for a pinch/spread, while a finger needs to stay still for a rotate.
        local angle = gesture_detector:getRotate(rstart_pos, tstart_pos, tend_pos)
        logger.dbg("rotate", angle, "detected")
        local direction = angle > 0 and "cw" or "ccw"
        -- If buddy is still down, switch it to a neutered state so that it's ignored until lift.
        if buddy_contact.down then
            buddy_contact.state = Contact.voidState
        else
            -- If it's already up (e.g., because of the snow protocol), drop it now.
            gesture_detector:dropContact(buddy_contact)
        end
        return {
            ges = "rotate",
            pos = rstart_pos,
            angle = angle,
            direction = direction,
            time = self.current_tev.timev,
        }
    else
        local rpan_dir, rpan_dis = buddy_contact:getPath()
        local rend_pos = Geom:new{
            x = buddy_contact.current_tev.x,
            y = buddy_contact.current_tev.y,
            w = 0,
            h = 0,
        }
        local start_distance = tstart_pos:distance(rstart_pos)
        local end_distance = tend_pos:distance(rend_pos)
        local ges_ev = {
            ges = "two_finger_pan",
            -- Use midpoint of tstart and rstart as swipe start point
            pos = tstart_pos:midpoint(rstart_pos),
            distance = tpan_dis + rpan_dis,
            direction = tpan_dir,
            time = self.current_tev.timev,
        }
        if tpan_dir ~= rpan_dir then
            if start_distance > end_distance then
                ges_ev.ges = "inward_pan"
            else
                ges_ev.ges = "outward_pan"
            end
            ges_ev.direction = gesture_detector.DIRECTION_TABLE[tpan_dir]
        elseif buddy_contact.state == Contact.holdState and self.state == Contact.holdState then
            ges_ev.ges = "two_finger_hold_pan"
            -- Flag 'em for holdState to discriminate with two_finger_hold_release
            self.pending_mt_gesture = "hold_pan"
            logger.dbg("Flagged slot", self.slot, "as a two_finger_hold_pan")
            buddy_contact.pending_mt_gesture = "hold_pan"
            logger.dbg("Flagged slot", buddy_contact.slot, "as a two_finger_hold_pan")
        end

        if self.state == Contact.holdState and buddy_contact.state == Contact.panState then
            -- If self is in holdState but buddy is in panState and we've just detected a pan/pinch/spread,
            -- forcibly update it to pan so that stuff doesn't go wonky on release...
            logger.dbg("Detected a two_finger pan/pinch/spread from a hold, switching slot", self.slot, "to panState")
            self.state = Contact.panState
        end
        if self.state == Contact.panState and buddy_contact.state == Contact.holdState then
            -- Ditto the other way around
            logger.dbg("Detected a two_finger pan/pinch/spread with a hold buddy, switching slot", buddy_contact.slot, "to panState")
            buddy_contact.state = Contact.panState
        end
        if buddy_contact.state == Contact.tapState then
            -- If we detected an actual two-finger pan-like gesture but our buddy contact is late and still in tapState,
            -- (probably because it hasn't moved quite enough to pass PAN_THRESHOLD yet or hasn't been switched to hold yet,
            -- which is more likely to happen on platforms without timerfd support), forcibly switch it to pan now,
            -- so that *this* slot isn't left hanging waiting for a buffy that'll never go through panState ;).
            logger.dbg("Detected a two_finger pan/pinch/spread with a tardy buddy still in tapState, switching slot", buddy_contact.slot, "to panState")
            buddy_contact.state = Contact.panState
        end
        logger.dbg(ges_ev.ges, ges_ev.direction, ges_ev.distance, "detected")
        return ges_ev
    end
end

--[[--
Emits the pan_release & two_finger_pan_release gestures. Contact is up (but down is still true) and in panState.
--]]
function Contact:handlePanRelease()
    local slot = self.slot
    logger.dbg("Contact:handlePanRelease for slot", slot)
    local tev = self.current_tev
    local buddy_contact = self.buddy_contact
    local buddy_slot = buddy_contact and self.buddy_contact.slot
    local gesture_detector = self.ges_dec

    local release_pos = Geom:new{
        x = tev.x,
        y = tev.y,
        w = 0,
        h = 0,
    }
    local pan_ev = {
        ges = "pan_release",
        pos = release_pos,
        time = tev.timev,
    }
    if buddy_contact and self.down and
       (buddy_contact.down or buddy_contact.pending_mt_gesture == "pan_release" or buddy_contact.pending_mt_gesture == "swipe") then
        -- Both main contacts are actives, and we're currently down, while our buddy is still down or pending a MT gesture
        -- Mark that slot as pending and lifted, but leave its state alone
        self.pending_mt_gesture = "pan_release"
        self.down = false
        logger.dbg("Flagged slot", slot, "as pending a two_finger_pan_release")

        -- Once both contacts have been lifted, we're good to go!
        -- NOTE: There's a bit of trickery here in that if the buddy contact passed the swipe interval test, but this one didn't,
        --       we assume that both contacts failed, and we do a two_finger_pan_release instead of a two_finger_swipe
        --       (because a single swipe + a single pan would be meaningless).
        if self.pending_mt_gesture == "pan_release" and
           (buddy_contact.pending_mt_gesture == "pan_release" or buddy_contact.pending_mt_gesture == "swipe") then
            logger.dbg("two_finger_pan_release detected")
            pan_ev.ges = "two_finger_pan_release"
            gesture_detector:dropContact(self)
            gesture_detector:dropContact(buddy_contact)
            return pan_ev
        end
    else
        -- What's left to go through is ST, if we still have a stale buddy, it's time to get rid of it.
        if buddy_contact and buddy_contact.down == false then
            logger.dbg("Contact:handlePanRelease Dropped stale buddy on slot", buddy_contact.slot)
            gesture_detector:dropContact(buddy_contact)
            buddy_contact = nil
        end
        if self.down then
            logger.dbg("pan release detected in slot", slot)
            gesture_detector:dropContact(self)
            return pan_ev
        end
    end
    -- If both contacts are up and we haven't detected any gesture, forget about 'em (should ideally not happen)
    if buddy_contact and self.down == false and buddy_contact.down == false then
        logger.warn("Contact:handlePanRelease Cancelled gestures in slots", slot, buddy_slot)
        gesture_detector:dropContact(self)
        gesture_detector:dropContact(buddy_contact)
    end
end

--[[--
Emits the hold, hold_release & hold_pan gestures and their two_finger variants.
--]]
function Contact:holdState(new_hold)
    local slot = self.slot
    local tev = self.current_tev
    local buddy_contact = self.buddy_contact
    local buddy_slot = buddy_contact and self.buddy_contact.slot
    local gesture_detector = self.ges_dec

    logger.dbg("slot", slot, "in hold state...")
    -- When we switch to hold state, we pass an additional boolean param "new_hold".
    if new_hold and tev.id ~= -1 then
        -- If this contact is part of a rotate gesture, don't actually emit the hold,
        -- as a finalized rotate will inhibit the hold_release anyway...
        if self.pending_mt_gesture ~= "rotate" then
            if buddy_contact and self.down and (buddy_contact.down or buddy_contact.pending_mt_gesture == "hold") then
                -- Both main contacts are actives, and we're currently down,
                -- while our buddy is still down or pending a MT gesture, so mark that slot as pending.
                self.pending_mt_gesture = "hold"
                logger.dbg("Flagged slot", slot, "as pending a two_finger_hold")
                -- NOTE: For simplicty's sake, and because the fingers can move during the hold,
                --       we don't validate the distance between the two fingers like for a double_tap.

                -- Once both contacts have been flagged, we're good to go!
                if self.pending_mt_gesture == "hold" and buddy_contact.pending_mt_gesture == "hold" then
                    -- This is *NOT* a contact lift, unlike most other two finger gestures ;).
                    self.pending_mt_gesture = nil
                    buddy_contact.pending_mt_gesture = nil
                    logger.dbg("Cleared the pending two_finger_hold flag for slots", slot, buddy_slot)

                    local pos0 = Geom:new{
                        x = tev.x,
                        y = tev.y,
                        w = 0,
                        h = 0,
                    }
                    local pos1 = Geom:new{
                        x = buddy_contact.current_tev.x,
                        y = buddy_contact.current_tev.y,
                        w = 0,
                        h = 0,
                    }
                    local tap_span = pos0:distance(pos1)
                    logger.dbg("two_finger_hold detected with span", tap_span)
                    return {
                        ges = "two_finger_hold",
                        pos = pos0:midpoint(pos1),
                        span = tap_span,
                        time = tev.timev,
                    }
                end
            else
                return {
                    ges = "hold",
                    pos = Geom:new{
                        x = tev.x,
                        y = tev.y,
                        w = 0,
                        h = 0,
                    },
                    time = tev.timev,
                }
            end
        else
            logger.dbg("Inhibited hold gesture in slot", slot, "because it's flagged for a rotate gesture")
        end
    elseif tev.id == -1 then
        if buddy_contact and self.down and buddy_contact.state == Contact.holdState and
           (buddy_contact.down or buddy_contact.pending_mt_gesture == "hold_pan" or
           buddy_contact.pending_mt_gesture == "hold_release" or buddy_contact.pending_mt_gesture == "hold_pan_release") then
            -- Both main contacts are actives, and we're currently down, while our buddy is still down or pending a MT gesture
            -- If it was doing a hold_pan, flag this slot as pending a hold_pan_release,
            -- and if it's not already pending a hold_pan_release, mark it as pending a hold_release.
            if self.pending_mt_gesture == "hold_pan" or self.pending_mt_gesture == "pan" then
                self.pending_mt_gesture = "hold_pan_release"
                logger.dbg("Flagged slot", slot, "as pending a two_finger_hold_pan_release")
            elseif self.pending_mt_gesture ~= "hold_pan_release" then
                self.pending_mt_gesture = "hold_release"
                logger.dbg("Flagged slot", slot, "as pending a two_finger_hold_release")
            end
            -- Mark it as lifted regardless.
            self.down = false

            -- Once both contacts have been lifted, we're good to go!
            if self.pending_mt_gesture == "hold_release" and buddy_contact.pending_mt_gesture == "hold_release" then
                logger.dbg("two_finger_hold_release detected")
                gesture_detector:dropContact(self)
                gesture_detector:dropContact(buddy_contact)
                return {
                    ges = "two_finger_hold_release",
                    pos = Geom:new{
                        x = tev.x,
                        y = tev.y,
                        w = 0,
                        h = 0,
                    },
                time = tev.timev,
                }
            elseif self.pending_mt_gesture == "hold_pan_release" and buddy_contact.pending_mt_gesture == "hold_pan_release" then
                logger.dbg("two_finger_hold_pan_release detected")
                gesture_detector:dropContact(self)
                gesture_detector:dropContact(buddy_contact)
                return {
                    ges = "two_finger_hold_pan_release",
                    pos = Geom:new{
                        x = tev.x,
                        y = tev.y,
                        w = 0,
                        h = 0,
                    },
                time = tev.timev,
                }
            end
        elseif buddy_contact and self.down and
               buddy_contact.state == Contact.panState and buddy_contact.down and
               self.pending_mt_gesture == "rotate" then
            -- If we're part of a rotate gesture, but we were lifted *before* our buddy (e.g., because of the snow protocol),
            -- leave the contact dropping to it.
            logger.dbg("Contact:holdState Contact lift for slot", slot)
            self.down = false
        else
            -- What's left to go through is ST, if we still have a stale buddy, it's time to get rid of it.
            if buddy_contact and buddy_contact.down == false then
                logger.dbg("Contact:holdState Dropped stale buddy on slot", buddy_contact.slot)
                gesture_detector:dropContact(buddy_contact)
                buddy_contact = nil
            end
            if self.down then
                -- End of hold, signal hold release
                logger.dbg("hold_release detected in slot", slot)
                gesture_detector:dropContact(self)
                return {
                    ges = "hold_release",
                    pos = Geom:new{
                        x = tev.x,
                        y = tev.y,
                        w = 0,
                        h = 0,
                    },
                    time = tev.timev,
                }
            end
        end
        -- If both contacts are up and we haven't detected any gesture, forget about 'em (should ideally not happen)
        if buddy_contact and self.down == false and buddy_contact.down == false then
            logger.warn("Contact:holdState Cancelled gestures in slots", slot, buddy_slot)
            gesture_detector:dropContact(self)
            gesture_detector:dropContact(buddy_contact)
        elseif not buddy_contact and self.down == false then
            -- Huh, caught a *second* contact lift for this contact? (should never happen).
            logger.warn("Contact:holdState Cancelled a gesture in slot", slot)
            gesture_detector:dropContact(self)
        end
    elseif tev.id ~= -1 and ((math.abs(tev.x - self.initial_tev.x) >= gesture_detector.PAN_THRESHOLD) or
                             (math.abs(tev.y - self.initial_tev.y) >= gesture_detector.PAN_THRESHOLD)) then
        local ges_ev = self:handlePan()
        if ges_ev ~= nil then
            if ges_ev.ges == "two_finger_hold_pan" then
                -- Only send it once per pair
                if not (buddy_contact and buddy_contact.pending_mt_gesture == "hold_pan" and self.pending_mt_gesture == "hold_pan") then
                    ges_ev = nil
                end
            else
                ges_ev.ges = "hold_pan"
            end
        end
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
            or ges.ges == "hold_pan"
            or ges.ges == "multiswipe"
            or ges.ges == "two_finger_swipe"
            or ges.ges == "two_finger_pan"
            or ges.ges == "two_finger_hold_pan"
        then
            ges.direction = translateGesDirCoordinate(ges.direction, ges_coordinate_translation_90)
            if ges.ges == "multiswipe" then
                ges.multiswipe_directions = translateMultiswipeGesDirCoordinate(ges.multiswipe_directions, ges_coordinate_translation_90)
            end
            if ges.relative then
                ges.relative.x, ges.relative.y = -ges.relative.y, ges.relative.x
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
            or ges.ges == "hold_pan"
            or ges.ges == "multiswipe"
            or ges.ges == "two_finger_swipe"
            or ges.ges == "two_finger_pan"
            or ges.ges == "two_finger_hold_pan"
        then
            ges.direction = translateGesDirCoordinate(ges.direction, ges_coordinate_translation_270)
            if ges.ges == "multiswipe" then
                ges.multiswipe_directions = translateMultiswipeGesDirCoordinate(ges.multiswipe_directions, ges_coordinate_translation_270)
            end
            if ges.relative then
                ges.relative.x, ges.relative.y = ges.relative.y, -ges.relative.x
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
            or ges.ges == "hold_pan"
            or ges.ges == "multiswipe"
            or ges.ges == "two_finger_swipe"
            or ges.ges == "two_finger_pan"
            or ges.ges == "two_finger_hold_pan"
        then
            ges.direction = translateGesDirCoordinate(ges.direction, ges_coordinate_translation_180)
            if ges.ges == "multiswipe" then
                ges.multiswipe_directions = translateMultiswipeGesDirCoordinate(ges.multiswipe_directions, ges_coordinate_translation_180)
            end
            if ges.relative then
                ges.relative.x, ges.relative.y = -ges.relative.x, -ges.relative.y
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
