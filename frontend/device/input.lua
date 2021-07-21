--[[--
An interface to get input events.
--]]

local DataStorage = require("datastorage")
local DEBUG = require("dbg")
local Event = require("ui/event")
local GestureDetector = require("device/gesturedetector")
local Key = require("device/key")
local TimeVal = require("ui/timeval")
local framebuffer = require("ffi/framebuffer")
local input = require("ffi/input")
local logger = require("logger")
local _ = require("gettext")

-- We're going to need a few <linux/input.h> constants...
local ffi = require("ffi")
local C = ffi.C
require("ffi/posix_h")
require("ffi/linux_input_h")

-- luacheck: push
-- luacheck: ignore
-- key press event values (KEY.value)
local EVENT_VALUE_KEY_PRESS   = 1
local EVENT_VALUE_KEY_REPEAT  = 2
local EVENT_VALUE_KEY_RELEASE = 0

-- For Kindle Oasis orientation events (ABS.code)
-- the ABS code of orientation event will be adjusted to -24 from 24 (C.ABS_PRESSURE)
-- as C.ABS_PRESSURE is also used to detect touch input in KOBO devices.
local ABS_OASIS_ORIENTATION                     = -24
local DEVICE_ORIENTATION_PORTRAIT_LEFT          = 15
local DEVICE_ORIENTATION_PORTRAIT_RIGHT         = 17
local DEVICE_ORIENTATION_PORTRAIT               = 19
local DEVICE_ORIENTATION_PORTRAIT_ROTATED_LEFT  = 16
local DEVICE_ORIENTATION_PORTRAIT_ROTATED_RIGHT = 18
local DEVICE_ORIENTATION_PORTRAIT_ROTATED       = 20
local DEVICE_ORIENTATION_LANDSCAPE              = 21
local DEVICE_ORIENTATION_LANDSCAPE_ROTATED      = 22

-- Kindle Oasis 2 & 3 variant
-- c.f., drivers/input/misc/accel/bma2x2.c
local UPWARD_PORTRAIT_UP_INTERRUPT_HAPPENED     = 15
local UPWARD_PORTRAIT_DOWN_INTERRUPT_HAPPENED   = 16
local UPWARD_LANDSCAPE_LEFT_INTERRUPT_HAPPENED  = 17
local UPWARD_LANDSCAPE_RIGHT_INTERRUPT_HAPPENED = 18

-- For the events of the Forma & Libra accelerometers (MSC.value)
-- c.f., drivers/hwmon/mma8x5x.c
local MSC_RAW_GSENSOR_PORTRAIT_DOWN             = 0x17
local MSC_RAW_GSENSOR_PORTRAIT_UP               = 0x18
local MSC_RAW_GSENSOR_LANDSCAPE_RIGHT           = 0x19
local MSC_RAW_GSENSOR_LANDSCAPE_LEFT            = 0x1a
-- Not that we care about those, but they are reported, and accurate ;).
local MSC_RAW_GSENSOR_BACK                      = 0x1b
local MSC_RAW_GSENSOR_FRONT                     = 0x1c

-- For debug logging of ev.type
local linux_evdev_type_map = {
    [C.EV_SYN] = "EV_SYN",
    [C.EV_KEY] = "EV_KEY",
    [C.EV_REL] = "EV_REL",
    [C.EV_ABS] = "EV_ABS",
    [C.EV_MSC] = "EV_MSC",
    [C.EV_SW] = "EV_SW",
    [C.EV_LED] = "EV_LED",
    [C.EV_SND] = "EV_SND",
    [C.EV_REP] = "EV_REP",
    [C.EV_FF] = "EV_FF",
    [C.EV_PWR] = "EV_PWR",
    [C.EV_FF_STATUS] = "EV_FF_STATUS",
    [C.EV_MAX] = "EV_MAX",
    [C.EV_SDL] = "EV_SDL",
}

-- For debug logging of ev.code
local linux_evdev_syn_code_map = {
    [C.SYN_REPORT] = "SYN_REPORT",
    [C.SYN_CONFIG] = "SYN_CONFIG",
    [C.SYN_MT_REPORT] = "SYN_MT_REPORT",
    [C.SYN_DROPPED] = "SYN_DROPPED",
}

local linux_evdev_key_code_map = {
    [C.BTN_TOOL_PEN] = "BTN_TOOL_PEN",
    [C.BTN_TOOL_FINGER] = "BTN_TOOL_FINGER",
    [C.BTN_TOOL_RUBBER] = "BTN_TOOL_RUBBER",
    [C.BTN_TOUCH] = "BTN_TOUCH",
    [C.BTN_STYLUS] = "BTN_STYLUS",
    [C.BTN_STYLUS2] = "BTN_STYLUS2",
}

local linux_evdev_abs_code_map = {
    [C.ABS_X] = "ABS_X",
    [C.ABS_Y] = "ABS_Y",
    [C.ABS_PRESSURE] = "ABS_PRESSURE",
    [C.ABS_DISTANCE] = "ABS_DISTANCE",
    [C.ABS_MT_SLOT] = "ABS_MT_SLOT",
    [C.ABS_MT_TOUCH_MAJOR] = "ABS_MT_TOUCH_MAJOR",
    [C.ABS_MT_TOUCH_MINOR] = "ABS_MT_TOUCH_MINOR",
    [C.ABS_MT_WIDTH_MAJOR] = "ABS_MT_WIDTH_MAJOR",
    [C.ABS_MT_WIDTH_MINOR] = "ABS_MT_WIDTH_MINOR",
    [C.ABS_MT_ORIENTATION] = "ABS_MT_ORIENTATION",
    [C.ABS_MT_POSITION_X] = "ABS_MT_POSITION_X",
    [C.ABS_MT_POSITION_Y] = "ABS_MT_POSITION_Y",
    [C.ABS_MT_TOOL_TYPE] = "ABS_MT_TOOL_TYPE",
    [C.ABS_MT_BLOB_ID] = "ABS_MT_BLOB_ID",
    [C.ABS_MT_TRACKING_ID] = "ABS_MT_TRACKING_ID",
    [C.ABS_MT_PRESSURE] = "ABS_MT_PRESSURE",
    [C.ABS_TILT_X] = "ABS_TILT_X",
    [C.ABS_TILT_Y] = "ABS_TILT_Y",
    [C.ABS_MT_DISTANCE] = "ABS_MT_DISTANCE",
    [C.ABS_MT_TOOL_X] = "ABS_MT_TOOL_X",
    [C.ABS_MT_TOOL_Y] = "ABS_MT_TOOL_Y",
}

local linux_evdev_msc_code_map = {
    [C.MSC_RAW] = "MSC_RAW",
}
-- luacheck: pop

local _internal_clipboard_text = nil -- holds the last copied text

local Input = {
    -- must point to the device implementation when instantiating
    device = nil,
    -- this depends on keyboard layout and should be overridden:
    event_map = {},
    -- adapters are post processing functions that transform a given event to another event
    event_map_adapter = {},
    -- EV_ABS event to honor for pressure event (if any)
    pressure_event = nil,

    group = {
        Cursor = { "Up", "Down", "Left", "Right" },
        PgFwd = { "RPgFwd", "LPgFwd" },
        PgBack = { "RPgBack", "LPgBack" },
        Alphabet = {
            "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M",
            "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z"
        },
        AlphaNumeric = {
            "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
            "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M",
            "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z"
        },
        Numeric = {
            "0", "1", "2", "3", "4", "5", "6", "7", "8", "9"
        },
        Text = {
            " ", ".", "/",
            "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
            "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M",
            "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z"
        },
        Any = {
            " ", ".", "/",
            "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
            "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M",
            "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
            "Up", "Down", "Left", "Right", "Press", "Backspace", "End",
            "Back", "Sym", "AA", "Menu", "Home", "Del",
            "LPgBack", "RPgBack", "LPgFwd", "RPgFwd"
        },
    },

    -- NOTE: When looking at the device in Portrait mode, that's assuming PgBack is on TOP, and PgFwd on the BOTTOM
    rotation_map = {
        [framebuffer.ORIENTATION_PORTRAIT] = {},
        [framebuffer.ORIENTATION_LANDSCAPE] = { Up = "Right", Right = "Down", Down = "Left", Left = "Up", LPgBack = "LPgFwd", LPgFwd = "LPgBack", RPgBack = "RPgFwd", RPgFwd = "RPgBack" },
        [framebuffer.ORIENTATION_PORTRAIT_ROTATED] = { Up = "Down", Right = "Left", Down = "Up", Left = "Right", LPgFwd = "LPgBack", LPgBack = "LPgFwd", RPgFwd = "RPgBack", RPgBack = "RPgFwd" },
        [framebuffer.ORIENTATION_LANDSCAPE_ROTATED] = { Up = "Left", Right = "Up", Down = "Right", Left = "Down" }
    },

    timer_callbacks = {},
    disable_double_tap = true,
    tap_interval_override = nil,

    -- keyboard state:
    modifiers = {
        Alt = false,
        Ctrl = false,
        Shift = false,
        Sym = false,
    },

    -- repeat state:
    repeat_count = 0,

    -- touch state:
    main_finger_slot = 0,
    cur_slot = 0,
    MTSlots = {},
    ev_slots = {},
    gesture_detector = nil,

    -- simple internal clipboard implementation, can be overidden to use system clipboard
    hasClipboardText = function()
        return _internal_clipboard_text ~= nil and _internal_clipboard_text ~= ""
    end,
    getClipboardText = function()
        return _internal_clipboard_text
    end,
    setClipboardText = function(text)
        _internal_clipboard_text = text
    end,
}

function Input:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    if o.init then o:init() end
    return o
end

function Input:init()
    -- Handle default finger slot
    self.cur_slot = self.main_finger_slot
    self.ev_slots = {
        [self.main_finger_slot] = {
            slot = self.main_finger_slot,
        },
    }

    self.gesture_detector = GestureDetector:new{
        screen = self.device.screen,
        input = self,
    }

    -- set up fake event map
    self.event_map[10000] = "IntoSS" -- go into screen saver
    self.event_map[10001] = "OutOfSS" -- go out of screen saver
    self.event_map[10010] = "UsbPlugIn"
    self.event_map[10011] = "UsbPlugOut"
    self.event_map[10020] = "Charging"
    self.event_map[10021] = "NotCharging"

    -- user custom event map
    local custom_event_map_location = string.format(
        "%s/%s", DataStorage:getSettingsDir(), "event_map.lua")
    local ok, custom_event_map = pcall(dofile, custom_event_map_location)
    if ok then
        for key, value in pairs(custom_event_map) do
            self.event_map[key] = value
        end
        logger.info("loaded custom event map", custom_event_map)
    end
end

--[[--
Wrapper for FFI input open.

Note that we adhere to the "." syntax here for compatibility.

@todo Clean up separation FFI/this.
--]]
function Input.open(device, is_emu_events)
    input.open(device, is_emu_events and 1 or 0)
end

--[[--
Different device models can implement their own hooks
and register them.
--]]
function Input:registerEventAdjustHook(hook, hook_params)
    local old = self.eventAdjustHook
    self.eventAdjustHook = function(this, ev)
        old(this, ev)
        hook(this, ev, hook_params)
    end
end

function Input:registerGestureAdjustHook(hook, hook_params)
    local old = self.gestureAdjustHook
    self.gestureAdjustHook = function(this, ges)
        old(this, ges)
        hook(this, ges, hook_params)
    end
end

function Input:eventAdjustHook(ev)
    -- do nothing by default
end

function Input:gestureAdjustHook(ges)
    -- do nothing by default
end

--- Catalog of predefined hooks.
function Input:adjustTouchSwitchXY(ev)
    if ev.type == C.EV_ABS then
        if ev.code == C.ABS_X then
            ev.code = C.ABS_Y
        elseif ev.code == C.ABS_Y then
            ev.code = C.ABS_X
        elseif ev.code == C.ABS_MT_POSITION_X then
            ev.code = C.ABS_MT_POSITION_Y
        elseif ev.code == C.ABS_MT_POSITION_Y then
            ev.code = C.ABS_MT_POSITION_X
        end
    end
end

function Input:adjustTouchScale(ev, by)
    if ev.type == C.EV_ABS then
        if ev.code == C.ABS_X or ev.code == C.ABS_MT_POSITION_X then
            ev.value = by.x * ev.value
        end
        if ev.code == C.ABS_Y or ev.code == C.ABS_MT_POSITION_Y then
            ev.value = by.y * ev.value
        end
    end
end

function Input:adjustTouchMirrorX(ev, width)
    if ev.type == C.EV_ABS
    and (ev.code == C.ABS_X or ev.code == C.ABS_MT_POSITION_X) then
        ev.value = width - ev.value
    end
end

function Input:adjustTouchMirrorY(ev, height)
    if ev.type == C.EV_ABS
    and (ev.code == C.ABS_Y or ev.code == C.ABS_MT_POSITION_Y) then
        ev.value = height - ev.value
    end
end

function Input:adjustTouchTranslate(ev, by)
    if ev.type == C.EV_ABS then
        if ev.code == C.ABS_X or ev.code == C.ABS_MT_POSITION_X then
            ev.value = by.x + ev.value
        end
        if ev.code == C.ABS_Y or ev.code == C.ABS_MT_POSITION_Y then
            ev.value = by.y + ev.value
        end
    end
end

function Input:adjustKindleOasisOrientation(ev)
    if ev.type == C.EV_ABS and ev.code == C.ABS_PRESSURE then
        ev.code = ABS_OASIS_ORIENTATION
    end
end

function Input:setTimeout(slot, ges, cb, origin, delay)
    local item = {
        slot     = slot,
        gesture  = ges,
        callback = cb,
    }

    -- We're going to need the clock source id for these events from GestureDetector
    local clock_id = self.gesture_detector:getClockSource()
    local deadline

    -- If we're on a platform with the timerfd backend, handle that
    local timerfd
    if input.setTimer then
        -- If GestureDetector's clock source probing was inconclusive, do this on the UI timescale instead.
        if clock_id == -1 then
            deadline = TimeVal:now() + delay
            clock_id = C.CLOCK_MONOTONIC
        else
            deadline = origin + delay
        end
        -- What this does is essentially to ask the kernel to wake us up when the timer expires,
        -- instead of ensuring that ourselves via a polling timeout.
        -- This ensures perfect accuracy, and allows it to be computed in the event's own timescale.
        timerfd = input.setTimer(clock_id, deadline.sec, deadline.usec)
    end
    if timerfd then
            -- It worked, tweak the table a bit to make it clear the deadline will be handled by the kernel
            item.timerfd = timerfd
            -- We basically only need this for the sorting ;).
            item.deadline = deadline
    else
        -- No timerfd, we'll compute a poll timeout ourselves.
        if clock_id == C.CLOCK_MONOTONIC then
            -- If the event's clocksource is monotonic, we can use it directly.
            deadline = origin + delay
        else
            -- Otherwise, fudge it by using a current timestamp in the UI's timescale (MONOTONIC).
            -- This isn't the end of the world in practice (c.f., #7415).
            deadline = TimeVal:now() + delay
        end
        item.deadline = deadline
    end
    table.insert(self.timer_callbacks, item)

    -- NOTE: While the timescale is monotonic, we may interleave timers based on different delays, so we still need to sort...
    table.sort(self.timer_callbacks, function(v1, v2)
        return v1.deadline < v2.deadline
    end)
end

-- Clear all timeouts for a specific slot (and a specific gesture, if ges is set)
function Input:clearTimeout(slot, ges)
    for i = #self.timer_callbacks, 1, -1 do
        local item = self.timer_callbacks[i]
        if item.slot == slot and (not ges or item.gesture == ges) then
            -- If the timerfd backend is in use, close the fd and free the list's node, too.
            if item.timerfd then
                input.clearTimer(item.timerfd)
            end
            table.remove(self.timer_callbacks, i)
        end
    end
end

function Input:clearTimeouts()
    -- If the timerfd backend is in use, close the fds, too
    if input.setTimer then
        for _, item in ipairs(self.timer_callbacks) do
            if item.timerfd then
                input.clearTimer(item.timerfd)
            end
        end
    end

    self.timer_callbacks = {}
end

-- Reset the gesture parsing state to a blank slate
function Input:resetState()
    if self.gesture_detector then
        self.gesture_detector:clearStates()
        -- Resets the clock source probe
        self.gesture_detector:resetClockSource()
    end
    self:clearTimeouts()
end

function Input:handleKeyBoardEv(ev)
    local keycode = self.event_map[ev.code]
    if not keycode then
        -- do not handle keypress for keys we don't know
        return
    end

    if self.event_map_adapter[keycode] then
        return self.event_map_adapter[keycode](ev)
    end

    -- take device rotation into account
    if self.rotation_map[self.device.screen:getRotationMode()][keycode] then
        keycode = self.rotation_map[self.device.screen:getRotationMode()][keycode]
    end

    -- fake events
    if keycode == "IntoSS" or keycode == "OutOfSS"
    or keycode == "UsbPlugIn" or keycode == "UsbPlugOut"
    or keycode == "Charging" or keycode == "NotCharging" then
        return keycode
    end

    -- The hardware camera button is used in Android to toggle the touchscreen
    if keycode == "Camera" and ev.value == EVENT_VALUE_KEY_RELEASE
        and G_reader_settings:isTrue("camera_key_toggles_touchscreen") then
        local isAndroid, android = pcall(require, "android")
        if isAndroid then
            -- toggle touchscreen behaviour
            android.toggleTouchscreenIgnored()

            -- show a toast with the new behaviour
            if android.isTouchscreenIgnored() then
                android.notification(_("Touchscreen disabled"))
            else
                android.notification(_("Touchscreen enabled"))
            end
        end
        return
    end

    if keycode == "Power" then
        -- Kobo generates Power keycode only, we need to decide whether it's
        -- power-on or power-off ourselves.
        if ev.value == EVENT_VALUE_KEY_PRESS then
            return "PowerPress"
        elseif ev.value == EVENT_VALUE_KEY_RELEASE then
            return "PowerRelease"
        end
    end

    -- quit on Alt + F4
    -- this is also emitted by the close event in SDL
    if self:isEvKeyPress(ev) and self.modifiers["Alt"] and keycode == "F4" then
        local Device = require("frontend/device")
        local UIManager = require("ui/uimanager")

        local save_quit = function()
            Device:saveSettings()
            UIManager:quit()
        end
        UIManager:broadcastEvent(Event:new("Exit", save_quit))
    end

    -- handle modifier keys
    if self.modifiers[keycode] ~= nil then
        if ev.value == EVENT_VALUE_KEY_PRESS then
            self.modifiers[keycode] = true
        elseif ev.value == EVENT_VALUE_KEY_RELEASE then
            self.modifiers[keycode] = false
        end
        return
    end

    local key = Key:new(keycode, self.modifiers)

    if ev.value == EVENT_VALUE_KEY_PRESS then
        return Event:new("KeyPress", key)
    elseif ev.value == EVENT_VALUE_KEY_REPEAT then
        -- NOTE: We only care about repeat events from the pageturn buttons...
        --       And we *definitely* don't want to flood the Event queue with useless SleepCover repeats!
        if keycode == "LPgBack"
        or keycode == "RPgBack"
        or keycode == "LPgFwd"
        or keycode == "RPgFwd" then
            --- @fixme Crappy event staggering!
            --
            -- The Forma & co repeats every 80ms after a 400ms delay, and 500ms roughly corresponds to a flashing update,
            -- so stuff is usually in sync when you release the key.
            -- Obvious downside is that this ends up slower than just mashing the key.
            --
            -- A better approach would be an onKeyRelease handler that flushes the Event queue...
            self.repeat_count = self.repeat_count + 1
            if self.repeat_count == 1 then
                return Event:new("KeyRepeat", key)
            elseif self.repeat_count >= 6 then
                self.repeat_count = 0
            end
        end
    elseif ev.value == EVENT_VALUE_KEY_RELEASE then
        self.repeat_count = 0
        return Event:new("KeyRelease", key)
    end
end

function Input:handleMiscEv(ev)
    -- should be handled by a misc event protocol plugin
end

function Input:handleSdlEv(ev)
    -- overwritten by device implementation
end

--[[--
Parse each touch ev from kernel and build up tev.
tev will be sent to GestureDetector:feedEvent

Events for a single tap motion from Linux kernel (MT protocol B):

    MT_TRACK_ID: 0
    MT_X: 222
    MT_Y: 207
    SYN REPORT
    MT_TRACK_ID: -1
    SYN REPORT

Notice that each line is a single event.

From kernel document:
For type B devices, the kernel driver should associate a slot with each
identified contact, and use that slot to propagate changes for the contact.
Creation, replacement and destruction of contacts is achieved by modifying
the C.ABS_MT_TRACKING_ID of the associated slot.  A non-negative tracking id
is interpreted as a contact, and the value -1 denotes an unused slot.  A
tracking id not previously present is considered new, and a tracking id no
longer present is considered removed.  Since only changes are propagated,
the full state of each initiated contact has to reside in the receiving
end.  Upon receiving an MT event, one simply updates the appropriate
attribute of the current slot.
--]]
function Input:handleTouchEv(ev)
    if ev.type == C.EV_ABS then
        if #self.MTSlots == 0 then
            table.insert(self.MTSlots, self:getMtSlot(self.cur_slot))
        end
        if ev.code == C.ABS_MT_SLOT then
            self:addSlotIfChanged(ev.value)
        elseif ev.code == C.ABS_MT_TRACKING_ID then
            if self.snow_protocol then
                self:addSlotIfChanged(ev.value)
            end
            self:setCurrentMtSlot("id", ev.value)
        elseif ev.code == C.ABS_MT_POSITION_X then
            self:setCurrentMtSlot("x", ev.value)
        elseif ev.code == C.ABS_MT_POSITION_Y then
            self:setCurrentMtSlot("y", ev.value)
        elseif self.pressure_event and ev.code == self.pressure_event and ev.value == 0 then
            -- Drop hovering pen events
            self:setCurrentMtSlot("id", -1)

        -- code to emulate mt protocol on kobos
        -- we "confirm" abs_x, abs_y only when pressure ~= 0
        elseif ev.code == C.ABS_X then
            self:setCurrentMtSlot("abs_x", ev.value)
        elseif ev.code == C.ABS_Y then
            self:setCurrentMtSlot("abs_y", ev.value)
        elseif ev.code == C.ABS_PRESSURE then
            if ev.value ~= 0 then
                self:setCurrentMtSlot("id", 1)
                self:confirmAbsxy()
            else
                self:cleanAbsxy()
                self:setCurrentMtSlot("id", -1)
            end
        end
    elseif ev.type == C.EV_SYN then
        if ev.code == C.SYN_REPORT then
            -- Promote our event's time table to a real TimeVal
            setmetatable(ev.time, TimeVal)
            for _, MTSlot in pairs(self.MTSlots) do
                self:setMtSlot(MTSlot.slot, "timev", ev.time)
                if self.snow_protocol then
                    -- if a slot appears in the current touch event, set "used"
                    self:setMtSlot(MTSlot.slot, "used", true)
                end
            end
            if self.snow_protocol then
                -- reset every slot that doesn't appear in the current touch event
                -- (because on the H2O2, this is the only way we detect finger-up)
                self.MTSlots = {}
                for _, slot in pairs(self.ev_slots) do
                    table.insert(self.MTSlots, slot)
                    if not slot.used then
                        slot.id = -1
                        slot.timev = ev.time
                    end
                end
            end
            -- feed ev in all slots to state machine
            local touch_ges = self.gesture_detector:feedEvent(self.MTSlots)
            self.MTSlots = {}
            if self.snow_protocol then
                -- go through all the ev_slots and clear used
                for _, slot in pairs(self.ev_slots) do
                    slot.used = nil
                end
            end
            if touch_ges then
                self:gestureAdjustHook(touch_ges)
                return Event:new("Gesture",
                    self.gesture_detector:adjustGesCoordinate(touch_ges)
                )
            end
        end
    end
end
function Input:handleTouchEvPhoenix(ev)
    -- Hack on handleTouchEV for the Kobo Aura
    -- It seems to be using a custom protocol:
    --        finger 0 down:
    --            input_report_abs(elan_touch_data.input, C.ABS_MT_TRACKING_ID, 0);
    --            input_report_abs(elan_touch_data.input, C.ABS_MT_TOUCH_MAJOR, 1);
    --            input_report_abs(elan_touch_data.input, C.ABS_MT_WIDTH_MAJOR, 1);
    --            input_report_abs(elan_touch_data.input, C.ABS_MT_POSITION_X, x1);
    --            input_report_abs(elan_touch_data.input, C.ABS_MT_POSITION_Y, y1);
    --            input_mt_sync (elan_touch_data.input);
    --        finger 1 down:
    --            input_report_abs(elan_touch_data.input, C.ABS_MT_TRACKING_ID, 1);
    --            input_report_abs(elan_touch_data.input, C.ABS_MT_TOUCH_MAJOR, 1);
    --            input_report_abs(elan_touch_data.input, C.ABS_MT_WIDTH_MAJOR, 1);
    --            input_report_abs(elan_touch_data.input, C.ABS_MT_POSITION_X, x2);
    --            input_report_abs(elan_touch_data.input, C.ABS_MT_POSITION_Y, y2);
    --            input_mt_sync (elan_touch_data.input);
    --        finger 0 up:
    --            input_report_abs(elan_touch_data.input, C.ABS_MT_TRACKING_ID, 0);
    --            input_report_abs(elan_touch_data.input, C.ABS_MT_TOUCH_MAJOR, 0);
    --            input_report_abs(elan_touch_data.input, C.ABS_MT_WIDTH_MAJOR, 0);
    --            input_report_abs(elan_touch_data.input, C.ABS_MT_POSITION_X, last_x);
    --            input_report_abs(elan_touch_data.input, C.ABS_MT_POSITION_Y, last_y);
    --            input_mt_sync (elan_touch_data.input);
    --        finger 1 up:
    --            input_report_abs(elan_touch_data.input, C.ABS_MT_TRACKING_ID, 1);
    --            input_report_abs(elan_touch_data.input, C.ABS_MT_TOUCH_MAJOR, 0);
    --            input_report_abs(elan_touch_data.input, C.ABS_MT_WIDTH_MAJOR, 0);
    --            input_report_abs(elan_touch_data.input, C.ABS_MT_POSITION_X, last_x2);
    --            input_report_abs(elan_touch_data.input, C.ABS_MT_POSITION_Y, last_y2);
    --            input_mt_sync (elan_touch_data.input);
    if ev.type == C.EV_ABS then
        if #self.MTSlots == 0 then
            table.insert(self.MTSlots, self:getMtSlot(self.cur_slot))
        end
        if ev.code == C.ABS_MT_TRACKING_ID then
            self:addSlotIfChanged(ev.value)
            self:setCurrentMtSlot("id", ev.value)
        elseif ev.code == C.ABS_MT_TOUCH_MAJOR and ev.value == 0 then
            self:setCurrentMtSlot("id", -1)
        elseif ev.code == C.ABS_MT_POSITION_X then
            self:setCurrentMtSlot("x", ev.value)
        elseif ev.code == C.ABS_MT_POSITION_Y then
            self:setCurrentMtSlot("y", ev.value)
        end
    elseif ev.type == C.EV_SYN then
        if ev.code == C.SYN_REPORT then
            setmetatable(ev.time, TimeVal)
            for _, MTSlot in pairs(self.MTSlots) do
                self:setMtSlot(MTSlot.slot, "timev", ev.time)
            end
            -- feed ev in all slots to state machine
            local touch_ges = self.gesture_detector:feedEvent(self.MTSlots)
            self.MTSlots = {}
            if touch_ges then
                self:gestureAdjustHook(touch_ges)
                return Event:new("Gesture",
                    self.gesture_detector:adjustGesCoordinate(touch_ges)
                )
            end
        end
    end
end
function Input:handleTouchEvLegacy(ev)
    -- Single Touch Protocol. Some devices emit both singletouch and multitouch events.
    -- In those devices the 'handleTouchEv' function doesn't work as expected. Use this function instead.
    if ev.type == C.EV_ABS then
        if #self.MTSlots == 0 then
            table.insert(self.MTSlots, self:getMtSlot(self.cur_slot))
        end
        if ev.code == C.ABS_X then
            self:setCurrentMtSlot("x", ev.value)
        elseif ev.code == C.ABS_Y then
            self:setCurrentMtSlot("y", ev.value)
        elseif ev.code == C.ABS_PRESSURE then
            if ev.value ~= 0 then
                self:setCurrentMtSlot("id", 1)
            else
                self:setCurrentMtSlot("id", -1)
            end
        end
    elseif ev.type == C.EV_SYN then
        if ev.code == C.SYN_REPORT then
            setmetatable(ev.time, TimeVal)
            for _, MTSlot in pairs(self.MTSlots) do
                self:setMtSlot(MTSlot.slot, "timev", ev.time)
            end

            -- feed ev in all slots to state machine
            local touch_ges = self.gesture_detector:feedEvent(self.MTSlots)
            self.MTSlots = {}
            if touch_ges then
                self:gestureAdjustHook(touch_ges)
                return Event:new("Gesture",
                    self.gesture_detector:adjustGesCoordinate(touch_ges)
                )
            end
        end
    end
end

function Input:handleOasisOrientationEv(ev)
    local rotation_mode, screen_mode
    if self.device:isZelda() then
        if ev.value == UPWARD_PORTRAIT_UP_INTERRUPT_HAPPENED then
            -- i.e., UR
            rotation_mode = framebuffer.ORIENTATION_PORTRAIT
            screen_mode = 'portrait'
        elseif ev.value == UPWARD_LANDSCAPE_LEFT_INTERRUPT_HAPPENED then
            -- i.e., CW
            rotation_mode = framebuffer.ORIENTATION_LANDSCAPE
            screen_mode = 'landscape'
        elseif ev.value == UPWARD_PORTRAIT_DOWN_INTERRUPT_HAPPENED then
            -- i.e., UD
            rotation_mode = framebuffer.ORIENTATION_PORTRAIT_ROTATED
            screen_mode = 'portrait'
        elseif ev.value == UPWARD_LANDSCAPE_RIGHT_INTERRUPT_HAPPENED then
            -- i.e., CCW
            rotation_mode = framebuffer.ORIENTATION_LANDSCAPE_ROTATED
            screen_mode = 'landscape'
        end
    else
        if ev.value == DEVICE_ORIENTATION_PORTRAIT
            or ev.value == DEVICE_ORIENTATION_PORTRAIT_LEFT
            or ev.value == DEVICE_ORIENTATION_PORTRAIT_RIGHT then
            -- i.e., UR
            rotation_mode = framebuffer.ORIENTATION_PORTRAIT
            screen_mode = 'portrait'
        elseif ev.value == DEVICE_ORIENTATION_LANDSCAPE then
            -- i.e., CW
            rotation_mode = framebuffer.ORIENTATION_LANDSCAPE
            screen_mode = 'landscape'
        elseif ev.value == DEVICE_ORIENTATION_PORTRAIT_ROTATED
            or ev.value == DEVICE_ORIENTATION_PORTRAIT_ROTATED_LEFT
            or ev.value == DEVICE_ORIENTATION_PORTRAIT_ROTATED_RIGHT then
            -- i.e., UD
            rotation_mode = framebuffer.ORIENTATION_PORTRAIT_ROTATED
            screen_mode = 'portrait'
        elseif ev.value == DEVICE_ORIENTATION_LANDSCAPE_ROTATED then
            -- i.e., CCW
            rotation_mode = framebuffer.ORIENTATION_LANDSCAPE_ROTATED
            screen_mode = 'landscape'
        end
    end

    local old_rotation_mode = self.device.screen:getRotationMode()
    if self.device:isGSensorLocked() then
        local old_screen_mode = self.device.screen:getScreenMode()
        if rotation_mode ~= old_rotation_mode and screen_mode == old_screen_mode then
            -- Cheaper than a full SetRotationMode event, as we don't need to re-layout anything.
            self.device.screen:setRotationMode(rotation_mode)
            local UIManager = require("ui/uimanager")
            UIManager:onRotation()
        end
    else
        if rotation_mode ~= old_rotation_mode then
            return Event:new("SetRotationMode", rotation_mode)
        end
    end
end

--- Accelerometer on the Forma/Libra
function Input:handleMiscEvNTX(ev)
    local rotation_mode, screen_mode
    if ev.code == C.MSC_RAW then
        if ev.value == MSC_RAW_GSENSOR_PORTRAIT_UP then
            -- i.e., UR
            rotation_mode = framebuffer.ORIENTATION_PORTRAIT
            screen_mode = 'portrait'
        elseif ev.value == MSC_RAW_GSENSOR_LANDSCAPE_RIGHT then
            -- i.e., CW
            rotation_mode = framebuffer.ORIENTATION_LANDSCAPE
            screen_mode = 'landscape'
        elseif ev.value == MSC_RAW_GSENSOR_PORTRAIT_DOWN then
            -- i.e., UD
            rotation_mode = framebuffer.ORIENTATION_PORTRAIT_ROTATED
            screen_mode = 'portrait'
        elseif ev.value == MSC_RAW_GSENSOR_LANDSCAPE_LEFT then
            -- i.e., CCW
            rotation_mode = framebuffer.ORIENTATION_LANDSCAPE_ROTATED
            screen_mode = 'landscape'
        else
            -- Discard FRONT/BACK
            return
        end
    else
        -- Discard unhandled event codes, just to future-proof this ;).
        return
    end

    local old_rotation_mode = self.device.screen:getRotationMode()
    if self.device:isGSensorLocked() then
        local old_screen_mode = self.device.screen:getScreenMode()
        if rotation_mode and rotation_mode ~= old_rotation_mode and screen_mode == old_screen_mode then
            -- Cheaper than a full SetRotationMode event, as we don't need to re-layout anything.
            self.device.screen:setRotationMode(rotation_mode)
            local UIManager = require("ui/uimanager")
            UIManager:onRotation()
        end
    else
        if rotation_mode and rotation_mode ~= old_rotation_mode then
            return Event:new("SetRotationMode", rotation_mode)
        end
    end
end

--- Allow toggling the accelerometer at runtime.
function Input:toggleMiscEvNTX(toggle)
    if toggle == true then
        -- Honor Gyro events
        if not self.isNTXAccelHooked then
            self.handleMiscEv = self.handleMiscEvNTX
            self.isNTXAccelHooked = true
        end
    elseif toggle == false then
        -- Ignore Gyro events
        if self.isNTXAccelHooked then
            self.handleMiscEv = function() end
            self.isNTXAccelHooked = false
        end
    else
        -- Toggle it
        if self.isNTXAccelHooked then
            self.handleMiscEv = function() end
        else
            self.handleMiscEv = self.handleMiscEvNTX
        end

        self.isNTXAccelHooked = not self.isNTXAccelHooked
    end
end

-- helpers for touch event data management:

function Input:setMtSlot(slot, key, val)
    if not self.ev_slots[slot] then
        self.ev_slots[slot] = {
            slot = slot
        }
    end

    self.ev_slots[slot][key] = val
end

function Input:setCurrentMtSlot(key, val)
    self:setMtSlot(self.cur_slot, key, val)
end

function Input:getMtSlot(slot)
    return self.ev_slots[slot]
end

function Input:getCurrentMtSlot()
    return self:getMtSlot(self.cur_slot)
end

function Input:addSlotIfChanged(value)
    if self.cur_slot ~= value then
        table.insert(self.MTSlots, self:getMtSlot(value))
    end
    self.cur_slot = value
end

function Input:confirmAbsxy()
    self:setCurrentMtSlot("x", self.ev_slots[self.cur_slot]["abs_x"])
    self:setCurrentMtSlot("y", self.ev_slots[self.cur_slot]["abs_y"])
end

function Input:cleanAbsxy()
    self:setCurrentMtSlot("abs_x", nil)
    self:setCurrentMtSlot("abs_y", nil)
end

function Input:isEvKeyPress(ev)
    return ev.value == EVENT_VALUE_KEY_PRESS
end

function Input:isEvKeyRepeat(ev)
    return ev.value == EVENT_VALUE_KEY_REPEAT
end

function Input:isEvKeyRelease(ev)
    return ev.value == EVENT_VALUE_KEY_RELEASE
end


--- Main event handling.
-- `now` corresponds to UIManager:getTime() (a TimeVal), and it's just been updated by UIManager.
-- `deadline` (a TimeVal) is the absolute deadline imposed by UIManager:handleInput() (a.k.a., our main event loop ^^):
-- it's either nil (meaning block forever waiting for input), or the earliest UIManager deadline (in most cases, that's the next scheduled task,
-- in much less common cases, that's the earliest of UIManager.INPUT_TIMEOUT (currently, only KOSync ever sets it) or UIManager.ZMQ_TIMEOUT if there are pending ZMQs).
function Input:waitEvent(now, deadline)
    -- On the first iteration of the loop, we don't need to update now, we're following closely (a couple ms at most) behind UIManager.
    local ok, ev
    -- Wrapper around the platform-specific input.waitForEvent (which itself is generally poll-like, and supposed to poll *once*).
    -- Speaking of input.waitForEvent, it can return:
    -- * true, ev: When a batch of input events was read.
    --             ev is an array of event tables, themselves mapped after the input_event <linux/input.h> struct.
    -- * false, errno, timerfd: When no input event was read, possibly for benign reasons.
    --                          One such common case is after a polling timeout, in which case errno is C.ETIME.
    --                          If the timerfd backend is in use, and the early return was caused by a timerfd expiring,
    --                          it returns false, C.ETIME, timerfd; where timerfd is a C pointer (i.e., light userdata)
    --                          to the timerfd node that expired (so as to be able to free it later, c.f., input/timerfd-callbacks.h).
    --                          Otherwise, errno is the actual error code from the backend (e.g., select's errno for the C backend).
    -- * nil: When something terrible happened (e.g., fatal poll/read failure). We abort in such cases.
    while true do
        if #self.timer_callbacks > 0 then
            -- If we have timers set, we need to honor them once we're done draining the input events.
            while #self.timer_callbacks > 0 do
                -- Choose the earliest deadline between the next timer deadline, and our full timeout deadline.
                local deadline_is_timer = false
                local with_timerfd = false
                local poll_deadline
                -- If the timer's deadline is handled via timerfd, that's easy
                if self.timer_callbacks[1].timerfd then
                    -- We use the ultimate deadline, as the kernel will just signal us when the timer expires during polling.
                    poll_deadline = deadline
                    with_timerfd = true
                else
                    if not deadline then
                        -- If we don't actually have a full timeout deadline, just honor the timer's.
                        poll_deadline = self.timer_callbacks[1].deadline
                        deadline_is_timer = true
                    else
                        if self.timer_callbacks[1].deadline < deadline then
                            poll_deadline = self.timer_callbacks[1].deadline
                            deadline_is_timer = true
                        else
                            poll_deadline = deadline
                        end
                    end
                end
                local poll_timeout
                -- With the timerfd backend, poll_deadline is set to deadline, which might be nil, in which case,
                -- we can happily block forever, like in the no timer_callbacks branch below ;).
                if poll_deadline then
                    -- If we haven't hit that deadline yet, poll until it expires, otherwise,
                    -- have select return immediately so that we trip a timeout.
                    now = now or TimeVal:now()
                    if poll_deadline > now then
                        -- Deadline hasn't been blown yet, honor it.
                        poll_timeout = poll_deadline - now
                    else
                        -- We've already blown the deadline: make select return immediately (most likely straight to timeout)
                        poll_timeout = TimeVal.zero
                    end
                end

                local timerfd
                ok, ev, timerfd = input.waitForEvent(poll_timeout and poll_timeout.sec, poll_timeout and poll_timeout.usec)
                -- We got an actual input event, go and process it
                if ok then break end

                -- If we've drained all pending input events, causing waitForEvent to time out, check our timers
                if ok == false and ev == C.ETIME then
                    -- Check whether the earliest timer to finalize a Gesture detection is up.
                    local consume_callback = false
                    if timerfd then
                        -- If we were woken up by a timerfd, that means the timerfd backend is in use, of course,
                        -- and it also means that we're guaranteed to have reached its deadline.
                        consume_callback = true
                    elseif not with_timerfd then
                        -- On systems where the timerfd backend is *NOT* in use, we have a few more cases to handle...
                        if deadline_is_timer then
                            -- We're only guaranteed to have blown the timer's deadline
                            -- when our actual select deadline *was* the timer's!
                            consume_callback = true
                        elseif TimeVal:now() >= self.timer_callbacks[1].deadline then
                            -- But if it was a task deadline instead, we to have to check the timer's against the current time,
                            -- to double-check whether we blew it or not.
                            consume_callback = true
                        end
                    end

                    if consume_callback then
                        local touch_ges = self.timer_callbacks[1].callback()
                        table.remove(self.timer_callbacks, 1)
                        -- If it was a timerfd, we also need to close the fd.
                        -- NOTE: The fact that deadlines are sorted *should* ensure that the timerfd that expired
                        --       is actually the first of the list without us having to double-check that...
                        if timerfd then
                            input.clearTimer(timerfd)
                        end
                        if touch_ges then
                            -- The timers we'll encounter are for finalizing a hold or (if enabled) double tap gesture,
                            -- as such, it makes no sense to try to detect *multiple* subsequent gestures.
                            -- This is why we clear the full list of timers on the first match ;).
                            self:clearTimeouts()
                            self:gestureAdjustHook(touch_ges)
                            return {
                                Event:new("Gesture", self.gesture_detector:adjustGesCoordinate(touch_ges))
                            }
                        end -- if touch_ges
                    end -- if poll_deadline reached
                else
                    -- Something went wrong, jump to error handling *now*
                    break
                end -- if poll returned ETIME

                -- Refresh now on the next iteration (e.g., when we have multiple timers to check, and we've just timed out)
                now = nil
            end -- while #timer_callbacks > 0
        else
            -- If there aren't any timers, just block for the requested amount of time.
            -- deadline may be nil, in which case waitForEvent blocks indefinitely (i.e., until the next input event ;)).
            local poll_timeout
            -- If UIManager put us on deadline, enforce it, otherwise, block forever.
            if deadline then
                -- Convert that absolute deadline to value relative to *now*, as we may loop multiple times between UI ticks.
                now = now or TimeVal:now()
                if deadline > now then
                    -- Deadline hasn't been blown yet, honor it.
                    poll_timeout = deadline - now
                else
                    -- Deadline has been blown: make select return immediately.
                    poll_timeout = TimeVal.zero
                end
            end

            ok, ev = input.waitForEvent(poll_timeout and poll_timeout.sec, poll_timeout and poll_timeout.usec)
        end -- if #timer_callbacks > 0

        -- Handle errors
        if ok then
            -- We're good, process the event and go back to UIManager.
            break
        elseif ok == false then
            if ev == C.ETIME then
                -- Don't report an error on ETIME, and go back to UIManager
                ev = nil
                break
            elseif ev == C.EINTR then  -- luacheck: ignore
                -- Retry on EINTR
            else
                -- Warn, report, and go back to UIManager
                logger.warn("Polling for input events returned an error:", ev, "->", ffi.string(C.strerror(ev)))
                break
            end
        elseif ok == nil then
            -- Something went horribly wrong, abort.
            logger.err("Polling for input events failed catastrophically")
            local UIManager = require("ui/uimanager")
            UIManager:abort()
            break
        end

        -- We'll need to refresh now on the next iteration, if there is one.
        now = nil
    end

    if ok and ev then
        local handled = {}
        -- We're guaranteed that ev is an array of event tables. Might be an array of *one* event, but an array nonetheless ;).
        for __, event in ipairs(ev) do
            if DEBUG.is_on then
                -- NOTE: This is rather spammy and computationally intensive,
                --       and we can't conditionally prevent evalutation of function arguments,
                --       so, just hide the whole thing behind a branch ;).
                DEBUG:logEv(event)
                if event.type == C.EV_KEY then
                    logger.dbg(string.format(
                        "key event => code: %d (%s), value: %s, time: %d.%06d",
                        event.code, self.event_map[event.code] or linux_evdev_key_code_map[event.code], event.value,
                        event.time.sec, event.time.usec))
                elseif event.type == C.EV_SYN then
                    logger.dbg(string.format(
                        "input event => type: %d (%s), code: %d (%s), value: %s, time: %d.%06d",
                        event.type, linux_evdev_type_map[event.type], event.code, linux_evdev_syn_code_map[event.code], event.value,
                        event.time.sec, event.time.usec))
                elseif event.type == C.EV_ABS then
                    logger.dbg(string.format(
                        "input event => type: %d (%s), code: %d (%s), value: %s, time: %d.%06d",
                        event.type, linux_evdev_type_map[event.type], event.code, linux_evdev_abs_code_map[event.code], event.value,
                        event.time.sec, event.time.usec))
                elseif event.type == C.EV_MSC then
                    logger.dbg(string.format(
                        "input event => type: %d (%s), code: %d (%s), value: %s, time: %d.%06d",
                        event.type, linux_evdev_type_map[event.type], event.code, linux_evdev_msc_code_map[event.code], event.value,
                        event.time.sec, event.time.usec))
                else
                    logger.dbg(string.format(
                        "input event => type: %d (%s), code: %d, value: %s, time: %d.%06d",
                        event.type, linux_evdev_type_map[event.type], event.code, event.value,
                        event.time.sec, event.time.usec))
                end
            end
            self:eventAdjustHook(event)
            if event.type == C.EV_KEY then
                local handled_ev = self:handleKeyBoardEv(event)
                if handled_ev then
                    table.insert(handled, handled_ev)
                end
            elseif event.type == C.EV_ABS and event.code == ABS_OASIS_ORIENTATION then
                local handled_ev = self:handleOasisOrientationEv(event)
                if handled_ev then
                    table.insert(handled, handled_ev)
                end
            elseif event.type == C.EV_ABS or event.type == C.EV_SYN then
                local handled_ev = self:handleTouchEv(event)
                -- We don't gnerate an Event for *every* input event, so, make sure we don't push nil values to the array
                if handled_ev then
                    table.insert(handled, handled_ev)
                end
            elseif event.type == C.EV_MSC then
                local handled_ev = self:handleMiscEv(event)
                if handled_ev then
                    table.insert(handled, handled_ev)
                end
            elseif event.type == C.EV_SDL then
                local handled_ev = self:handleSdlEv(event)
                if handled_ev then
                    table.insert(handled, handled_ev)
                end
            else
                -- Received some other kind of event that we do not know how to specifically handle yet
                table.insert(handled, Event:new("GenericInput", event))
            end
        end
        return handled
    elseif ok == false and ev then
        return {
            Event:new("InputError", ev)
        }
    elseif ok == nil then
        -- No ok and no ev? Hu oh...
        return {
            Event:new("InputError", "Catastrophic")
        }
    end
end

return Input
