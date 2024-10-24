--[[--
This module detects gestures.

Current detectable gestures:

* `touch` (emitted once on first contact down)
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

-- This is used as a singleton by Input (itself used as a singleton).
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
    DIRECTION_TABLE = { -- const
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
    -- Used for double tap and bounce detection (this is outside a Contact object because it requires minimal persistence).
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
    -- distance parameters
    self.TWO_FINGER_TAP_REGION = self.screen:scaleByDPI(20)
    self.DOUBLE_TAP_DISTANCE = self.screen:scaleByDPI(50)
    self.SINGLE_TAP_BOUNCE_DISTANCE = self.DOUBLE_TAP_DISTANCE
    self.PAN_THRESHOLD = self.screen:scaleByDPI(35)
    self.MULTISWIPE_THRESHOLD = self.DOUBLE_TAP_DISTANCE
end

local function deepCopyEv(tev)
    return {
        x = tev.x,
        y = tev.y,
        id = tev.id,
        slot = tev.slot,
        timev = tev.timev, -- A ref is enough for this table, it's re-assigned to a new object on every SYN_REPORT
    }
end

-- Contact object, it'll keep track of everything we need for a single contact across its lifetime
-- i.e., from this contact's down to up (or its *effective* up for double-taps, e.g., when the tap or double_tap is emitted).
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
        initial_tev = nil, -- Copy of the input event table at first contact (i.e., at contact down [iff the platform is sane, might be a copy of current_tev otherwise])
        current_tev = nil, -- Pointer to the current input event table, ref is *stable*, c.f., NOTE in feedEvent below
        down = false, -- Contact is down (as opposed to up, i.e., lifted). Only really happens for double-tap handling, in every other case the Contact object is destroyed on lift.
        pending_double_tap_timer = false, -- Contact is pending a double_tap timer
        pending_hold_timer = false, -- Contact is pending a hold timer
        mt_gesture = nil, -- Contact is part of a MT gesture (string, gesture name)
        mt_immobile = true, -- Contact is part of a MT gesture, and hasn't moved (i.e., would be in holdState if it weren't in voidState)
        multiswipe_directions = {}, -- Accumulated multiswipe chain for this contact
        multiswipe_type = nil, -- Current multiswipe type for this contact
        buddy_contact = buddy_contact, -- Ref to the paired contact in a MT gesture (if any)
        ges_dec = self, -- Ref to the current GestureDetector instance
    }
    self.contact_count = self.contact_count + 1
    --logger.dbg("New contact for slot", slot, "#contacts =", self.contact_count)

    -- If we have a buddy contact, point its own buddy ref to us
    if buddy_contact then
        buddy_contact.buddy_contact = self.active_contacts[slot]

        -- And make sure it has an initial_tev recorded, for misbehaving platforms...
        if not buddy_contact.initial_tev then
            buddy_contact.initial_tev = deepCopyEv(buddy_contact.current_tev)
            logger.warn("GestureDetector:newContact recorded an initial_tev out of order for buddy slot", buddy_contact.slot)
        end
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
    --logger.dbg("Dropped contact for slot", slot, "#contacts =", self.contact_count)
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
    if time_diff < interval then
        local x_diff = math.abs(tap1.x - tap2.x)
        local y_diff = math.abs(tap1.y - tap2.y)

        return (
            x_diff < self.SINGLE_TAP_BOUNCE_DISTANCE and
            y_diff < self.SINGLE_TAP_BOUNCE_DISTANCE
        )
    end
end

function GestureDetector:isDoubleTap(tap1, tap2)
    local time_diff = tap2.timev - tap1.timev
    if time_diff < 0 then
        time_diff = time.huge
    end
    if time_diff < self.ges_double_tap_interval then
        local x_diff = math.abs(tap1.x - tap2.x)
        local y_diff = math.abs(tap1.y - tap2.y)

        return (
            x_diff < self.DOUBLE_TAP_DISTANCE and
            y_diff < self.DOUBLE_TAP_DISTANCE
        )
    end
end

function Contact:isTwoFingerTap(buddy_contact)
    local gesture_detector = self.ges_dec

    local time_diff0 = self.current_tev.timev - self.initial_tev.timev
    if time_diff0 < 0 then
        time_diff0 = time.huge
    end
    local time_diff1 = buddy_contact.current_tev.timev - buddy_contact.initial_tev.timev
    if time_diff1 < 0 then
        time_diff1 = time.huge
    end
    if time_diff0 < gesture_detector.ges_two_finger_tap_duration and
       time_diff1 < gesture_detector.ges_two_finger_tap_duration then
        local x_diff0 = math.abs(self.current_tev.x - self.initial_tev.x)
        local x_diff1 = math.abs(buddy_contact.current_tev.x - buddy_contact.initial_tev.x)
        local y_diff0 = math.abs(self.current_tev.y - self.initial_tev.y)
        local y_diff1 = math.abs(buddy_contact.current_tev.y - buddy_contact.initial_tev.y)

        return (
            x_diff0 < gesture_detector.TWO_FINGER_TAP_REGION and
            x_diff1 < gesture_detector.TWO_FINGER_TAP_REGION and
            y_diff0 < gesture_detector.TWO_FINGER_TAP_REGION and
            y_diff1 < gesture_detector.TWO_FINGER_TAP_REGION
        )
    end
end

--[[--
Compares `current_tev` with `initial_tev`.

The first boolean argument `simple` results in only four directions if true.

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

function Contact:switchState(state_func, func_arg)
    self.state = state_func
    return state_func(self, func_arg)
end

-- Unlike switchState, we don't *call* the new state, and we ensure that initial_tev is set,
-- in case initialState never ran on a contact down because the platform screwed up (e.g., PB with broken MT).
-- The rest of the code, in particular the buddy system, assumes initial_tev is always set (and supposedly sane).
function Contact:setState(state_func)
    -- NOTE: Safety net for broken platforms that might screw up slot order...
    if not self.initial_tev then
        self.initial_tev = deepCopyEv(self.current_tev)
        logger.warn("Contact:setState recorded an initial_tev out of order for slot", self.slot)
    end
    self.state = state_func
end

function Contact:initialState()
    local tev = self.current_tev

    if tev.id then
        -- Contact lift
        if tev.id == -1 then
            -- If this slot was a buddy slot that happened to be dropped by a MT gesture in the *same* input frame,
            -- a lift might be the first thing we process here... We can safely drop it again.
            -- Hover pen events are also good candidates for this.
            logger.dbg("Contact:initialState Cancelled a gesture in slot", self.slot)
            self.ges_dec:dropContact(self)
        else
            self.id = tev.id
            if tev.x and tev.y then
                -- Contact down, user started a new touch motion
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
    if boottime ~= 0 and timev >= boottime - threshold and timev <= boottime + threshold then
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
    local gesture_detector = self.ges_dec

    -- Attempt to detect the clock source for these events (we reset it on suspend to discriminate MONOTONIC from BOOTTIME).
    if not gesture_detector.clock_id then
        gesture_detector:probeClockSource(tev.timev)
    end

    logger.dbg("slot", slot, "in tap state...")
    -- Contact lift
    if tev.id == -1 then
        if buddy_contact and self.down then
            -- Both main contacts are actives and we are down
            if self:isTwoFingerTap(buddy_contact) then
                -- Mark that slot
                self.mt_gesture = "tap"
                -- Neuter its buddy
                buddy_contact:setState(Contact.voidState)
                buddy_contact.mt_gesture = "tap"

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
                local tap_pos = pos0:midpoint(pos1)
                logger.dbg("two_finger_tap detected @", tap_pos.x, tap_pos.y, "with span", tap_span)
                -- Don't drop buddy, voidState will handle it
                gesture_detector:dropContact(self)
                return {
                    ges = "two_finger_tap",
                    pos = tap_pos,
                    span = tap_span,
                    time = tev.timev,
                }
            else
                logger.dbg("Contact:tapState: Two-contact tap failed to pass the two_finger_tap constraints -> single tap @", tev.x, tev.y)
                -- We blew the gesture position/time constraints,
                -- neuter buddy and send a single tap on this slot.
                buddy_contact:setState(Contact.voidState)
                gesture_detector:dropContact(self)

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
        elseif self.down or self.pending_double_tap_timer then
            -- Hand over to the double tap handler, it's responsible for downgrading to single tap
            return self:handleDoubleTap()
        else
            -- Huh, caught a *second* contact lift for this contact? (should never happen).
            logger.warn("Contact:tapState Cancelled a gesture")
            gesture_detector:dropContact(self)
        end
    else
        -- If we're pending a double_tap timer, flag the contact as down again.
        if self.pending_double_tap_timer and self.down == false then
            self.down = true
            logger.dbg("Contact:tapState: Contact down")
        end
        -- See if we need to do something with the move/hold
        return self:handleNonTap(new_tap)
    end
end

--[[--
Emits both tap & double_tap gestures. Contact is up (but down is still true) or pending a double_tap timer.
--]]
function Contact:handleDoubleTap()
    local slot = self.slot
    --logger.dbg("Contact:handleDoubleTap for slot", slot)
    local tev = self.current_tev
    local gesture_detector = self.ges_dec

    -- If we don't actually detect two distinct taps (i.e., down -> up -> down -> up), then it's a hover, ignore it.
    -- (Without a double tap timer involved, these get dropped in initialState).
    if self.pending_double_tap_timer and self.down == false then
        logger.dbg("Contact:handleDoubleTap Ignored a hover event")
        return
    end

    -- cur_tap is used for double tap and bounce detection
    local cur_tap = {
        x = tev.x,
        y = tev.y,
        timev = tev.timev,
    }

    -- Tap interval / bounce detection may be tweaked by a widget (i.e., VirtualKeyboard)
    local tap_interval = gesture_detector.input.tap_interval_override or gesture_detector.ges_tap_interval
    -- We do tap bounce detection even when double tap is enabled
    -- (so, double tap is triggered when: ges_tap_interval <= delay < ges_double_tap_interval).
    if tap_interval ~= 0 and gesture_detector.previous_tap[slot] ~= nil and
       gesture_detector:isTapBounce(gesture_detector.previous_tap[slot], cur_tap, tap_interval) then
        logger.dbg("Contact:handleDoubleTap Stopped a tap bounce")
        -- Simply ignore it, and drop this slot as this is a contact lift.
        gesture_detector:dropContact(self)
        return
    end

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

    if not gesture_detector.input.disable_double_tap and self.pending_double_tap_timer and
       gesture_detector:isDoubleTap(gesture_detector.previous_tap[slot], cur_tap) then
        -- It is a double tap
        ges_ev.ges = "double_tap"
        logger.dbg("Contact:handleDoubleTap: double_tap detected @", ges_ev.pos.x, ges_ev.pos.y)
        gesture_detector:dropContact(self)
        return ges_ev
    end

    -- Remember this tap, now that we're out of the bounce & double_tap windows
    gesture_detector.previous_tap[slot] = cur_tap

    if gesture_detector.input.disable_double_tap then
        -- We can send the event immediately (no need for the timer stuff needed for double tap support)
        logger.dbg("Contact:handleDoubleTap: single tap detected @", ges_ev.pos.x, ges_ev.pos.y)
        gesture_detector:dropContact(self)
        return ges_ev
    end

    -- Double tap enabled: we can't send this single tap immediately as it may be the start of a double tap.
    -- We'll send it as a single tap after a timer if no second tap happened in the double tap delay.
    if not self.pending_double_tap_timer then
        logger.dbg("set up double_tap timer")
        self.pending_double_tap_timer = true
        -- setTimeout will handle computing the deadline in the least lossy way possible given the platform.
        gesture_detector.input:setTimeout(slot, "double_tap", function()
            if self == gesture_detector:getContact(slot) and self.pending_double_tap_timer then
                self.pending_double_tap_timer = false
                if self.state == Contact.tapState then
                    -- A single or double tap will yield a different contact object, by virtue of dropContact and closure magic ;).
                    -- Speaking of closures, this is the original ges_ev from the timer setup.
                    logger.dbg("double_tap timer detected a single tap in slot", slot, "@", ges_ev.pos.x, ges_ev.pos.y)
                    gesture_detector:dropContact(self)
                    return ges_ev
                end
            end
        end, tev.timev, gesture_detector.ges_double_tap_interval)
    end
    -- Regardless of the timer shenanigans, it's at the very least a contact lift,
    -- but we can't quite call dropContact yet, as it would cancel the timer.
    self.down = false
    logger.dbg("Contact:handleDoubleTap: Contact lift")
end

--[[--
Handles move (switch to panState) & hold (switch to holdState). Contact is down.
`new_tap` is true for the initial contact down event.
--]]
function Contact:handleNonTap(new_tap)
    local slot = self.slot
    --logger.dbg("Contact:handleNonTap for slot", slot)
    local tev = self.current_tev
    local gesture_detector = self.ges_dec

    -- If we haven't yet fired the hold timer, do so first and foremost, as hold_pan handling *requires* a hold.
    -- We only do this on the first contact down.
    if new_tap and not self.pending_hold_timer then
        logger.dbg("set up hold timer")
        self.pending_hold_timer = true
        gesture_detector.input:setTimeout(slot, "hold", function()
            -- If this contact is still active & alive and its timer hasn't been cancelled,
            -- (e.g., it hasn't gone through dropContact because of a contact lift yet),
            -- then check that we're still in a stationary contact down state (i.e., tapState).
            -- NOTE: We need to check that the current contact in this slot is *still* the same object first, because closure ;).
            if self == gesture_detector:getContact(slot) and self.pending_hold_timer then
                self.pending_hold_timer = nil
                if self.state == Contact.tapState and self.down then
                    -- NOTE: If we happened to have moved enough, holdState will generate a hold_pan on the *next* event,
                    --       but for now, the initial hold is mandatory.
                    --       On the other hand, if we're *already* in pan state, we stay there and *never* switch to hold.
                    logger.dbg("hold timer tripped a switch to hold state in slot", slot)
                    return self:switchState(Contact.holdState, true)
                end
            end
        end, tev.timev, gesture_detector.ges_hold_interval)

        -- NOTE: We only generate touch *once*, on first contact down (at which point there's not enough history to trip a pan).
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
function Contact:panState(keep_contact)
    local slot = self.slot
    local tev = self.current_tev
    local buddy_contact = self.buddy_contact
    local gesture_detector = self.ges_dec

    logger.dbg("slot", slot, "in pan state...")
    if tev.id == -1 then
        -- End of pan, emit swipe and swipe-like gestures if necessary
        if self:isSwipe() then
            if buddy_contact and self.down then
                -- Both main contacts are actives and we are down, mark that slot
                self.mt_gesture = "swipe"
                -- Neuter its buddy
                -- NOTE: Similar trickery as in handlePan to deal with rotate,
                --       without the panState check for self, because we're obviously in panState...
                if buddy_contact.state ~= Contact.panState and buddy_contact.mt_immobile then
                    buddy_contact.mt_gesture = "rotate"
                else
                    buddy_contact.mt_gesture = "swipe"
                end
                buddy_contact:setState(Contact.voidState)

                local ges_ev = self:handleTwoFingerPan(buddy_contact)
                if ges_ev then
                    if buddy_contact.mt_gesture == "swipe" then
                        -- Only accept gestures that require both contacts to have been lifted
                        if ges_ev.ges == "two_finger_pan" then
                            ges_ev.ges = "two_finger_swipe"
                            -- Swap from pan semantics to swipe semantics
                            ges_ev.pos = ges_ev._start_pos
                            ges_ev._start_pos = nil
                            ges_ev.start_pos = nil
                            ges_ev.end_pos = ges_ev._end_pos
                            ges_ev._end_pos = nil
                            ges_ev.relative = nil
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
                    end
                end

                -- Don't drop buddy, voidState will handle it.
                -- NOTE: This is a hack for out of order rotate lifts when we have to fake a lift from voidState:
                --       when `keep_contact` is true, this isn't an actual contact lift,
                --       so we can't destroy the contact just yet...
                if not keep_contact then
                    gesture_detector:dropContact(self)
                end
                return ges_ev
            elseif self.down then
                return self:handleSwipe()
            end
        elseif self.down then
            -- If the contact lift is not a swipe, then it's a pan.
            return self:handlePanRelease(keep_contact)
        else
            -- Huh, caught a *second* contact lift for this contact? (should never happen).
            logger.warn("Contact:panState Cancelled a gesture")
            gesture_detector:dropContact(self)
        end
    else
        return self:handlePan()
    end
end

--[[--
Used to ignore a buddy slot part of a MT gesture, so that we don't send duplicate events.
--]]
function Contact:voidState()
    local slot = self.slot
    local tev = self.current_tev
    local buddy_contact = self.buddy_contact
    local buddy_slot = buddy_contact and self.buddy_contact.slot
    local gesture_detector = self.ges_dec

    logger.dbg("slot", slot, "in void state...")
    -- We basically don't do anything but drop the slot on contact lift,
    -- if need be deferring to the right state when we're part of a MT gesture.
    if tev.id == -1 then
        if self.down and buddy_contact and buddy_contact.down and self.mt_gesture then
            -- If we were lifted before our buddy, and we're part of a MT gesture,
            -- defer to the proper state (without switching state ourselves).
            if self.mt_gesture == "tap" then
                return self:tapState()
            elseif self.mt_gesture == "swipe" or self.mt_gesture == "pan" or self.mt_gesture == "pan_release" then
                return self:panState()
            elseif self.mt_gesture == "rotate" then
                -- NOTE: As usual, rotate requires some trickery,
                --       because it's the only gesture that requires both slots to be in *different* states...
                --       (The trigger contact *has* to be the panning one; while we're the held one in this scenario).
                logger.dbg("Contact:voidState Deferring to panState via buddy slot", buddy_slot, "to handle MT contact lift for a rotate")
                local ges_ev
                local buddy_tid = buddy_contact.current_tev.id
                if buddy_tid == -1 then
                    -- It's an actual lift for buddy, so we can just send it along, panState will drop the contact.
                    ges_ev = buddy_contact:panState()
                else
                    -- But *this* means the lifts are staggered, and we, the hold pivot, were lifted *first*.
                    -- To avoid further issues, we'll forcibly lift buddy for this single call,
                    -- to make sure panState tries for the rotate gesture *now*,
                    -- while asking it *not* to drop itself just now (as it's not an actual contact lift just yet) so that...
                    buddy_contact.current_tev.id = -1
                    ges_ev = buddy_contact:panState(true)
                    -- ...we can then send it to the void.
                    -- Whether the gesture fails or not, it'll be in voidState and only dropped on actual contact lift,
                    -- regardless of whether the driver repeats ABS_MT_TRACKING_ID values or not.
                    -- Otherwise, if it only lifts on the next input frame,
                    -- it won't go through MT codepaths at all, and you'll end up with a single swipe,
                    -- and if it lifts even later, we'd have to deal with spurious moves first, probably leading into a tap...
                    -- If the gesture *succeeds*, the buddy contact will be dropped whenever it's actually lifted,
                    -- thanks to the temporary tracking id switcheroo & voidState...
                    buddy_contact.current_tev.id = buddy_tid
                    buddy_contact:setState(Contact.voidState)
                end
                -- Regardless of whether we detected a gesture, this is a contact lift, so it's curtains for us!
                gesture_detector:dropContact(self)
                return ges_ev
            elseif self.mt_gesture == "hold" or self.mt_gesture == "hold_pan" or
                   self.mt_gesture == "hold_release" or self.mt_gesture == "hold_pan_release" then
                return self:holdState()
            else
                -- Should absolutely never happen (and, at the time of writing, is technically guaranteed to be unreachable).
                logger.warn("Contact:voidState Unknown MT gesture", self.mt_gesture, "cannot handle contact lift properly")
                -- We're still gone, though.
                gesture_detector:dropContact(self)
            end
        elseif self.down then
            -- We were lifted *after* our buddy, the gesture already went through, we can silently slink away into the night.
            logger.dbg("Contact:voidState Contact lift detected")
            gesture_detector:dropContact(self)
        else
            -- Huh, caught a *second* contact lift for this contact? (should never happen).
            logger.warn("Contact:voidState Cancelled a gesture")
            gesture_detector:dropContact(self)
        end
    else
        -- We need to be able to discriminate between a moving and unmoving contact for rotate/pan discrimination.
        if self.mt_immobile then
            if (math.abs(tev.x - self.initial_tev.x) >= gesture_detector.PAN_THRESHOLD) or
               (math.abs(tev.y - self.initial_tev.y) >= gesture_detector.PAN_THRESHOLD) then
                self.mt_immobile = false
                -- NOTE: We've just moved: if we were flagged for a hold gesture (meaning our buddy is still in holdState),
                --       that won't do anymore, switch to a setup for a rotate gesture.
                --       (This happens when attempting a rotate, and the hold timer for slot 0 expires
                --       before slot 1 has the chance to switch to panState).
                --       A.K.A., "rotate dirty hack #42" ;).
                if buddy_contact and buddy_contact.mt_gesture == "hold" and self.mt_gesture == "hold" then
                    self.mt_gesture = "pan"
                    buddy_contact.mt_gesture = "rotate"
                    logger.dbg("Contact:voidState We moved while pending a hold gesture, swap to a rotate setup")
                end
            else
                self.mt_immobile = true
            end
        end
    end
end

--[[--
Emits the swipe & multiswipe gestures. Contact is up. ST only (i.e., there isn't any buddy contact active).
--]]
function Contact:handleSwipe()
    --logger.dbg("Contact:handleSwipe for slot", self.slot)
    local tev = self.current_tev
    local gesture_detector = self.ges_dec

    local swipe_direction, swipe_distance = self:getPath()
    local start_pos = Geom:new{
        x = self.initial_tev.x,
        y = self.initial_tev.y,
        w = 0,
        h = 0,
    }
    local end_pos = Geom:new{
        x = tev.x,
        y = tev.y,
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

    logger.dbg("Contact:handleSwipe: swipe", swipe_direction, swipe_distance, "detected")
    gesture_detector:dropContact(self)
    return {
        ges = ges,
        -- NOTE: Unlike every other gesture, we use the *contact* point as the gesture's position,
        --       instead of the *lift* point, mainly because that's what makes the most sense
        --       from a hit-detection standpoint (c.f., `GestureRange:match` & `InputContainer:onGesture`),
        --       and that's 99% of the use-cases where the position actually matters for a swipe.
        pos = start_pos,
        -- And for those rare cases that need it, we provide the lift point separately.
        end_pos = end_pos,
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
    --logger.dbg("Contact:handlePan for slot", self.slot)
    local tev = self.current_tev
    local buddy_contact = self.buddy_contact
    local gesture_detector = self.ges_dec

    if buddy_contact and self.down then
        -- Both main contacts are actives and we are down, mark that slot
        self.mt_gesture = "pan"
        -- Neuter its buddy
        -- NOTE: Small trickery for rotate, which requires both contacts to be in very specific states.
        --       We merge tapState with holdState because it's likely that the hold hasn't taken yet,
        --       and it never will after that because we switch to voidState ;).
        if buddy_contact.state ~= Contact.panState and buddy_contact.mt_immobile and
           self.state == Contact.panState then
            buddy_contact.mt_gesture = "rotate"
        else
            buddy_contact.mt_gesture = "pan"
        end
        buddy_contact:setState(Contact.voidState)

        return self:handleTwoFingerPan(buddy_contact)
    elseif self.down then
        local pan_direction, pan_distance = self:getPath()
        local pan_ev = {
            ges = "pan",
            relative = {
                x = tev.x - self.initial_tev.x,
                y = tev.y - self.initial_tev.y,
            },
            start_pos = Geom:new{
                x = self.initial_tev.x,
                y = self.initial_tev.y,
                w = 0,
                h = 0,
            },
            pos = Geom:new{
                x = tev.x,
                y = tev.y,
                w = 0,
                h = 0,
            },
            direction = pan_direction,
            distance = pan_distance,
            time = tev.timev,
        }

        local msd_cnt = #self.multiswipe_directions
        local msd_direction_prev = (msd_cnt > 0) and self.multiswipe_directions[msd_cnt][1] or ""
        local prev_ms_ev, fake_initial_tev

        if msd_cnt == 0 then
            -- determine whether to initiate a straight or diagonal multiswipe
            self.multiswipe_type = "straight"
            if pan_direction ~= "north" and pan_direction ~= "south" and
               pan_direction ~= "east" and pan_direction ~= "west" then
                self.multiswipe_type = "diagonal"
            end
        elseif msd_cnt > 0 then
            -- recompute a more accurate direction and distance in a multiswipe context
            prev_ms_ev = self.multiswipe_directions[msd_cnt][2]
            fake_initial_tev = {
                x = prev_ms_ev.pos.x,
                y = prev_ms_ev.pos.y,
            }
        end

        -- the first time, fake_initial_tev is nil, so the contact's initial_tev is automatically used instead
        local msd_direction, msd_distance
        if self.multiswipe_type == "straight" then
            msd_direction, msd_distance = self:getPath(true, false, fake_initial_tev)
        else
            msd_direction, msd_distance = self:getPath(true, true, fake_initial_tev)
        end

        if msd_distance > gesture_detector.MULTISWIPE_THRESHOLD then
            local pan_ev_multiswipe = pan_ev
            -- store a copy of pan_ev without rotation adjustment for multiswipe calculations when rotated
            if gesture_detector.screen:getTouchRotation() > gesture_detector.screen.DEVICE_ROTATED_UPRIGHT then
                pan_ev_multiswipe = util.tableDeepCopy(pan_ev)
            end
            if msd_direction ~= msd_direction_prev then
                self.multiswipe_directions[msd_cnt+1] = {
                    [1] = msd_direction,
                    [2] = pan_ev_multiswipe,
                }
            else
                -- update ongoing swipe direction to the new maximum
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
    --logger.dbg("Contact:handleTwoFingerPan for slot", self.slot)
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
    if self.current_tev.id == -1 and buddy_contact.mt_gesture == "rotate" then
        -- NOTE: We only handle the rotate gesture when triggered by the just lifted pan finger
        --       (actually, it needs to pass the swipe interval check, but it is in panState),
        --       because this gesture would be too difficult to discriminate from a pinch/spread the other way around ;).
        --       TL;DR: Both fingers need to move for a pinch/spread, while a finger needs to stay still for a rotate.
        -- NOTE: FWIW, on an Elipsa, if we misdetect a pinch (i.e., both fingers moved) for a rotate
        --       because the buddy slot failed to pass the pan threshold, we get a very shallow angle (often < 1°, at most ~2°).
        --       If, on the other hand, we misdetect a rotate that *looked* like a pinch,
        --       (i.e., a pinch with only one finger moving), we get slightly larger angles (~5°).
        --       Things get wildly more difficult on an Android phone, where you can easily add ~10° of noise to those results.
        --       TL;DR: We just chuck those as misdetections instead of adding brittle heuristics to correct course ;).
        local angle = gesture_detector:getRotate(rstart_pos, tstart_pos, tend_pos)
        logger.dbg("Contact:handleTwoFingerPan: rotate", angle, "detected")
        return {
            ges = "rotate",
            pos = rstart_pos,
            angle = angle,
            direction = angle >= 0 and "cw" or "ccw",
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
        -- Use midpoint of tstart and rstart as swipe start point
        local start_point = tstart_pos:midpoint(rstart_pos)
        local end_point = tend_pos:midpoint(rend_pos)
        -- Compute the distance based on the start & end midpoints
        local avg_distance = start_point:distance(end_point)
        -- We'll also want to remember the span between both contacts on start & end for some gestures
        local start_distance = tstart_pos:distance(rstart_pos)
        local end_distance = tend_pos:distance(rend_pos)
        -- NOTE: "pan" and "hold_pan" use the current/end point as pos,
        --       but swipe reports pos as the *starting* point (c.f., `Contact:handleSwipe`).
        --       Since this table will be used for both pans and two_finger_swipe (via panState),
        --       we stuff a bunch of extra info in there to swap it around as-needed...
        local ges_ev = {
            ges = "two_finger_pan",
            relative = {
                x = end_point.x - start_point.x,
                y = end_point.y - start_point.y,
            },
            -- Default to the pan semantics, c.f., note above
            pos = end_point,
            start_pos = start_point,
            _start_pos = start_point,
            _end_pos = end_point,
            distance = avg_distance,
            direction = tpan_dir,
            time = self.current_tev.timev,
        }
        if tpan_dir ~= rpan_dir then
            if start_distance > end_distance then
                ges_ev.ges = "inward_pan"
                -- Use the end pos (this is the default already)
                ges_ev._start_pos = nil
                ges_ev._end_pos = nil
            else
                ges_ev.ges = "outward_pan"
                -- Use the start pos, it'll make more sense than the midpoint of the current contacts,
                -- given the potentially wide span between the two...
                ges_ev.pos = ges_ev._start_pos
                ges_ev._start_pos = nil
                ges_ev.start_pos = nil
                ges_ev.end_pos = ges_ev._end_pos
                ges_ev._end_pos = nil
            end
            ges_ev.direction = gesture_detector.DIRECTION_TABLE[tpan_dir]
            -- Use the sum of both contacts' travel for the distance
            ges_ev.distance = tpan_dis + rpan_dis
            -- Some handlers might also want to know the distance between the two contacts on lift & down.
            ges_ev.span = end_distance
            ges_ev.start_span = start_distance
            -- Drop unnecessary field
            ges_ev.relative = nil
        elseif self.state == Contact.holdState then
            ges_ev.ges = "two_finger_hold_pan"
            -- Flag 'em for holdState to discriminate with two_finger_hold_release
            self.mt_gesture = "hold_pan"
            buddy_contact.mt_gesture = "hold_pan"
        end

        logger.dbg("Contact:handleTwoFingerPan:", ges_ev.ges, ges_ev.direction, ges_ev.distance, "detected")
        return ges_ev
    end
end

--[[--
Emits the pan_release & two_finger_pan_release gestures. Contact is up (but down is still true) and in panState.
--]]
function Contact:handlePanRelease(keep_contact)
    --logger.dbg("Contact:handlePanRelease for slot", self.slot)
    local tev = self.current_tev
    local buddy_contact = self.buddy_contact
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
    if buddy_contact and self.down then
        -- Both main contacts are actives and we are down, mark that slot
        self.mt_gesture = "pan_release"
        -- Neuter its buddy
        buddy_contact:setState(Contact.voidState)
        buddy_contact.mt_gesture = "pan_release"

        logger.dbg("Contact:handlePanRelease: two_finger_pan_release detected")
        pan_ev.ges = "two_finger_pan_release"
        -- The pan itself used the midpoint between the two contacts, keep doing that.
        local buddy_pos = Geom:new{
            x = buddy_contact.current_tev.x,
            y = buddy_contact.current_tev.y,
            w = 0,
            h = 0,
        }
        pan_ev.pos = release_pos:midpoint(buddy_pos)
        -- Don't drop buddy, voidState will handle it
        -- NOTE: This is yet another rotate hack, emanating from voidState into panState.
        if not keep_contact then
            gesture_detector:dropContact(self)
        end
        return pan_ev
    elseif self.down then
        logger.dbg("Contact:handlePanRelease: pan release detected")
        gesture_detector:dropContact(self)
        return pan_ev
    else
        -- Huh, caught a *second* contact lift for this contact? (should never happen).
        logger.warn("Contact:handlePanRelease Cancelled a gesture")
        gesture_detector:dropContact(self)
    end
end

--[[--
Emits the hold, hold_release & hold_pan gestures and their two_finger variants.
--]]
function Contact:holdState(new_hold)
    local slot = self.slot
    local tev = self.current_tev
    local buddy_contact = self.buddy_contact
    local gesture_detector = self.ges_dec

    logger.dbg("slot", slot, "in hold state...")
    -- When we switch to hold state, we pass an additional boolean param "new_hold".
    if new_hold and tev.id ~= -1 then
        if buddy_contact and self.down then
            -- Both main contacts are actives and we are down, mark that slot
            self.mt_gesture = "hold"
            -- Neuter its buddy
            buddy_contact:setState(Contact.voidState)
            buddy_contact.mt_gesture = "hold"

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
            local tap_pos = pos0:midpoint(pos1)
            logger.dbg("two_finger_hold detected @", tap_pos.x, tap_pos.y, "with span", tap_span)
            return {
                ges = "two_finger_hold",
                pos = tap_pos,
                span = tap_span,
                time = tev.timev,
            }
        elseif self.down then
            logger.dbg("hold detected @", tev.x, tev.y)
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
    elseif tev.id == -1 then
        if buddy_contact and self.down then
            -- Both main contacts are actives and we are down, mark that slot
            if self.mt_gesture == "rotate" and buddy_contact.mt_gesture == "pan" then
                -- NOTE: We're setup as the hold in a rotate gesture, and we were lifted *before* our pan buddy,
                --       do a bit of gymnastics, because the trigger contact for a rotate *needs* to be the pan...
                --       This is a snow protocol special :/.
                -- NOTE: This is simpler than the elaborate trickery this case involves when dealt with via voidState,
                --       because it is specifically aimed at the snow protocol, so we *know* both contacts are lifted
                --       in the same input frame.
                logger.dbg("Contact:holdState: Early lift as a rotate pivot, trying for a rotate...")
                local ges_ev = buddy_contact:handleTwoFingerPan(self)
                if ges_ev then
                    if ges_ev.ges ~= "rotate" then
                        ges_ev = nil
                    else
                        logger.dbg(ges_ev.ges, ges_ev.direction, math.abs(ges_ev.angle), "detected")
                    end
                end
                -- Regardless of whether this panned out (pun intended), this is a lift, so we'll defer to voidState next.
                buddy_contact:setState(Contact.voidState)
                gesture_detector:dropContact(self)
                return ges_ev
            elseif self.mt_gesture == "hold_pan" or self.mt_gesture == "pan" then
                self.mt_gesture = "hold_pan_release"
                buddy_contact.mt_gesture = "hold_pan_release"
            else
                self.mt_gesture = "hold_release"
                buddy_contact.mt_gesture = "hold_release"
            end
            -- Neuter its buddy
            buddy_contact:setState(Contact.voidState)

            -- Don't drop buddy, voidState will handle it
            gesture_detector:dropContact(self)

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
            local ges_type = self.mt_gesture == "hold_pan_release" and "two_finger_hold_pan_release" or "two_finger_hold_release"
            local tap_span = pos0:distance(pos1)
            local tap_pos = pos0:midpoint(pos1)
            logger.dbg(ges_type, "detected @", tap_pos.x, tap_pos.y, "with span", tap_span)
            return {
                ges = ges_type,
                pos = tap_pos,
                span = tap_span,
                time = tev.timev,
            }
        elseif self.down then
            -- Contact lift, emit a hold_release
            logger.dbg("hold_release detected @", tev.x, tev.y)
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
        else
            -- Huh, caught a *second* contact lift for this contact? (should never happen).
            logger.warn("Contact:holdState Cancelled a gesture")
            gesture_detector:dropContact(self)
        end
    elseif tev.id ~= -1 and ((math.abs(tev.x - self.initial_tev.x) >= gesture_detector.PAN_THRESHOLD) or
                             (math.abs(tev.y - self.initial_tev.y) >= gesture_detector.PAN_THRESHOLD)) then
        -- We've moved enough to count as a pan, defer to the pan handler, but stay in holdState
        local ges_ev = self:handlePan()
        if ges_ev ~= nil then
            if ges_ev.ges ~= "two_finger_hold_pan" then
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
    if mode == self.screen.DEVICE_ROTATED_CLOCKWISE then
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
                logger.dbg("GestureDetector: Landscape translation for multiswipe:", ges.multiswipe_directions)
            else
                logger.dbg("GestureDetector: Landscape translation for ges:", ges.ges, ges.direction)
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
            logger.dbg("GestureDetector: Landscape translation for ges:", ges.ges, ges.direction)
        end
    elseif mode == self.screen.DEVICE_ROTATED_COUNTER_CLOCKWISE then
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
                logger.dbg("GestureDetector: Inverted landscape translation for multiswipe:", ges.multiswipe_directions)
            else
                logger.dbg("GestureDetector: Inverted landscape translation for ges:", ges.ges, ges.direction)
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
            logger.dbg("GestureDetector: Inverted landscape translation for ges:", ges.ges, ges.direction)
        end
    elseif mode == self.screen.DEVICE_ROTATED_UPSIDE_DOWN then
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
                logger.dbg("GestureDetector: Inverted portrait translation for multiswipe:", ges.multiswipe_directions)
            else
                logger.dbg("GestureDetector: Inverted portrait translation for ges:", ges.ges, ges.direction)
            end
            if ges.relative then
                ges.relative.x, ges.relative.y = -ges.relative.x, -ges.relative.y
            end
        end
        -- pinch/spread are unaffected
    end
    return ges
end

return GestureDetector
