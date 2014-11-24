local Event = require("ui/event")
local TimeVal = require("ui/timeval")
local input = require("ffi/input")
local util = require("ffi/util")
local Math = require("optmath")
local DEBUG = require("dbg")
local ffi = require("ffi")
local _ = require("gettext")
local Key = require("device/key")
local GestureDetector = require("device/gesturedetector")

-- constants from <linux/input.h>
local EV_SYN = 0
local EV_KEY = 1
local EV_ABS = 3
local EV_MSC = 4

-- key press event values (KEY.value)
local EVENT_VALUE_KEY_PRESS = 1
local EVENT_VALUE_KEY_REPEAT = 2
local EVENT_VALUE_KEY_RELEASE = 0

-- Synchronization events (SYN.code).
local SYN_REPORT = 0
local SYN_CONFIG = 1
local SYN_MT_REPORT = 2

-- For single-touch events (ABS.code).
local ABS_X = 00
local ABS_Y = 01
local ABS_PRESSURE = 24

-- For multi-touch events (ABS.code).
local ABS_MT_SLOT = 47
local ABS_MT_TOUCH_MAJOR = 48
local ABS_MT_WIDTH_MAJOR = 50

local ABS_MT_POSITION_X = 53
local ABS_MT_POSITION_Y = 54
local ABS_MT_TRACKING_ID = 57
local ABS_MT_PRESSURE = 58

--[[
an interface to get input events
]]
local Input = {
    -- this depends on keyboard layout and should be overridden:
    event_map = {},

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
            "Up", "Down", "Left", "Right", "Press",
            "Back", "Enter", "Sym", "AA", "Menu", "Home", "Del",
            "LPgBack", "RPgBack", "LPgFwd", "RPgFwd"
        },
    },

    rotation_map = {
        [0] = {},
        [1] = { Up = "Right", Right = "Down", Down = "Left", Left = "Up" },
        [2] = { Up = "Down", Right = "Left", Down = "Up", Left = "Right" },
        [3] = { Up = "Left", Right = "Up", Down = "Right", Left = "Down" }
    },

    timer_callbacks = {},
    disable_double_tap = DGESDETECT_DISABLE_DOUBLE_TAP,

    -- keyboard state:
    modifiers = {
        Alt = false,
        Shift = false,
    },

    -- touch state:
    cur_slot = 0,
    MTSlots = {},
    ev_slots = {
        [0] = {
            slot = 0,
        }
    },
    gesture_detector = nil,
}

function Input:new(o)
    local o = o or {}
    setmetatable(o, self)
    self.__index = self
    if o.init then o:init() end
    return o
end

function Input:init()
    self.gesture_detector = GestureDetector:new{
        screen = self.device.screen,
        input = self,
    }

    -- set up fake event map
    self.event_map[10000] = "IntoSS" -- go into screen saver
    self.event_map[10001] = "OutOfSS" -- go out of screen saver
    self.event_map[10020] = "Charging"
    self.event_map[10021] = "NotCharging"

    -- user custom event map
    local ok, custom_event_map = pcall(dofile, "custom.event.map.lua")
    if ok then
        DEBUG("custom event map", custom_event_map)
        for key, value in pairs(custom_event_map) do
            self.event_map[key] = value
        end
    end
end

--[[
wrapper for FFI input open

Note that we adhere to the "." syntax here for compatibility.
TODO: clean up separation FFI/this
--]]
function Input.open(device)
    input.open(device)
end

--[[
Different device models can implement their own hooks
and register them.
--]]
function Input:registerEventAdjustHook(hook, hook_params)
    local old = self.eventAdjustHook
    self.eventAdjustHook = function(self, ev)
        old(self, ev)
        hook(self, ev, hook_params)
    end
end
function Input:eventAdjustHook(ev)
    -- do nothing by default
end
-- catalogue of predefined hooks:
function Input:adjustTouchSwitchXY(ev)
    if ev.type == EV_ABS then
        if ev.code == ABS_X then
            ev.code = ABS_Y
        elseif ev.code == ABS_Y then
            ev.code = ABS_X
        elseif ev.code == ABS_MT_POSITION_X then
            ev.code = ABS_MT_POSITION_Y
        elseif ev.code == ABS_MT_POSITION_Y then
            ev.code = ABS_MT_POSITION_X
        end
    end
end
function Input:adjustTouchScale(ev, by)
    if ev.type == EV_ABS then
        if ev.code == ABS_X or ev.code == ABS_MT_POSITION_X then
            ev.value = by.x * ev.value
        end
        if ev.code == ABS_Y or ev.code == ABS_MT_POSITION_Y then
            ev.value = by.y * ev.value
        end
    end
end
function Input:adjustTouchMirrorX(ev, width)
    if ev.type == EV_ABS
    and (ev.code == ABS_X or ev.code == ABS_MT_POSITION_X) then
        ev.value = width - ev.value
    end
end
function Input:adjustTouchMirrorY(ev, height)
    if ev.type == EV_ABS
    and (ev.code == ABS_Y or ev.code == ABS_MT_POSITION_Y) then
        ev.value = height - ev.value
    end
end
function Input:adjustTouchTranslate(ev, by)
    if ev.type == EV_ABS then
        if ev.code == ABS_X or ev.code == ABS_MT_POSITION_X then
            ev.value = by.x + ev.value
        end
        if ev.code == ABS_Y or ev.code == ABS_MT_POSITION_Y then
            ev.value = by.y + ev.value
        end
    end
end

function Input:setTimeout(cb, tv_out)
    local item = {
        callback = cb,
        deadline = tv_out,
    }
    table.insert(self.timer_callbacks, item)
    table.sort(self.timer_callbacks, function(v1,v2)
        return v1.deadline < v2.deadline
    end)
end

function Input:handleKeyBoardEv(ev)
    local keycode = self.event_map[ev.code]
    if not keycode then
        -- do not handle keypress for keys we don't know
        return
    end

    -- take device rotation into account
    if self.rotation_map[self.device.screen:getRotationMode()][keycode] then
        keycode = self.rotation_map[self.device.screen:getRotationMode()][keycode]
    end

    if keycode == "IntoSS" or keycode == "OutOfSS"
    or keycode == "Charging" or keycode == "NotCharging" then
        return keycode
    end

    -- Kobo sleep
    if keycode == "Power_SleepCover" then
        if ev.value == EVENT_VALUE_KEY_PRESS then
            return "Suspend"
        else
            return "Resume"
        end
    end

    if ev.value == EVENT_VALUE_KEY_RELEASE
    and (keycode == "Light" or keycode == "Power") then
        return keycode
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
    elseif ev.value == EVENT_VALUE_KEY_RELEASE then
        return Event:new("KeyRelease", key)
    end
end

function Input:handleMiscEv(ev)
    -- should be handled by a misc event protocol plugin
end

--[[
parse each touch ev from kernel and build up tev.
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
the ABS_MT_TRACKING_ID of the associated slot.  A non-negative tracking id
is interpreted as a contact, and the value -1 denotes an unused slot.  A
tracking id not previously present is considered new, and a tracking id no
longer present is considered removed.  Since only changes are propagated,
the full state of each initiated contact has to reside in the receiving
end.  Upon receiving an MT event, one simply updates the appropriate
attribute of the current slot.
--]]
function Input:handleTouchEv(ev)
    if ev.type == EV_ABS then
        if #self.MTSlots == 0 then
            table.insert(self.MTSlots, self:getMtSlot(self.cur_slot))
        end
        if ev.code == ABS_MT_SLOT then
            if self.cur_slot ~= ev.value then
                table.insert(self.MTSlots, self:getMtSlot(ev.value))
            end
            self.cur_slot = ev.value
        elseif ev.code == ABS_MT_TRACKING_ID then
            self:setCurrentMtSlot("id", ev.value)
        elseif ev.code == ABS_MT_POSITION_X then
            self:setCurrentMtSlot("x", ev.value)
        elseif ev.code == ABS_MT_POSITION_Y then
            self:setCurrentMtSlot("y", ev.value)

        -- code to emulate mt protocol on kobos
        -- we "confirm" abs_x, abs_y only when pressure ~= 0
        elseif ev.code == ABS_X then
            self:setCurrentMtSlot("abs_x", ev.value)
        elseif ev.code == ABS_Y then
            self:setCurrentMtSlot("abs_y", ev.value)
        elseif ev.code == ABS_PRESSURE then
            if ev.value ~= 0 then
                self:setCurrentMtSlot("id", 1)
                self:confirmAbsxy()
            else
                self:cleanAbsxy()
                self:setCurrentMtSlot("id", -1)
            end
        end
    elseif ev.type == EV_SYN then
        if ev.code == SYN_REPORT then
            for _, MTSlot in pairs(self.MTSlots) do
                self:setMtSlot(MTSlot.slot, "timev", TimeVal:new(ev.time))
            end
            -- feed ev in all slots to state machine
            local touch_ges = self.gesture_detector:feedEvent(self.MTSlots)
            self.MTSlots = {}
            if touch_ges then
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
    --            input_report_abs(elan_touch_data.input, ABS_MT_TRACKING_ID, 0);
    --            input_report_abs(elan_touch_data.input, ABS_MT_TOUCH_MAJOR, 1);
    --            input_report_abs(elan_touch_data.input, ABS_MT_WIDTH_MAJOR, 1);
    --            input_report_abs(elan_touch_data.input, ABS_MT_POSITION_X, x1);
    --            input_report_abs(elan_touch_data.input, ABS_MT_POSITION_Y, y1);
    --            input_mt_sync (elan_touch_data.input);
    --        finger 1 down:
    --            input_report_abs(elan_touch_data.input, ABS_MT_TRACKING_ID, 1);
    --            input_report_abs(elan_touch_data.input, ABS_MT_TOUCH_MAJOR, 1);
    --            input_report_abs(elan_touch_data.input, ABS_MT_WIDTH_MAJOR, 1);
    --            input_report_abs(elan_touch_data.input, ABS_MT_POSITION_X, x2);
    --            input_report_abs(elan_touch_data.input, ABS_MT_POSITION_Y, y2);
    --            input_mt_sync (elan_touch_data.input);
    --        finger 0 up:
    --            input_report_abs(elan_touch_data.input, ABS_MT_TRACKING_ID, 0);
    --            input_report_abs(elan_touch_data.input, ABS_MT_TOUCH_MAJOR, 0);
    --            input_report_abs(elan_touch_data.input, ABS_MT_WIDTH_MAJOR, 0);
    --            input_report_abs(elan_touch_data.input, ABS_MT_POSITION_X, last_x);
    --            input_report_abs(elan_touch_data.input, ABS_MT_POSITION_Y, last_y);
    --            input_mt_sync (elan_touch_data.input);
    --        finger 1 up:
    --            input_report_abs(elan_touch_data.input, ABS_MT_TRACKING_ID, 1);
    --            input_report_abs(elan_touch_data.input, ABS_MT_TOUCH_MAJOR, 0);
    --            input_report_abs(elan_touch_data.input, ABS_MT_WIDTH_MAJOR, 0);
    --            input_report_abs(elan_touch_data.input, ABS_MT_POSITION_X, last_x2);
    --            input_report_abs(elan_touch_data.input, ABS_MT_POSITION_Y, last_y2);
    --            input_mt_sync (elan_touch_data.input);
    if ev.type == EV_ABS then
        if #self.MTSlots == 0 then
            table.insert(self.MTSlots, self:getMtSlot(self.cur_slot))
        end
        if ev.code == ABS_MT_TRACKING_ID then
            if self.cur_slot ~= ev.value then
                table.insert(self.MTSlots, self:getMtSlot(ev.value))
            end
            self.cur_slot = ev.value
            self:setCurrentMtSlot("id", ev.value)
        elseif ev.code == ABS_MT_TOUCH_MAJOR and ev.value == 0 then
            self:setCurrentMtSlot("id", -1)
        elseif ev.code == ABS_MT_POSITION_X then
            self:setCurrentMtSlot("x", ev.value)
        elseif ev.code == ABS_MT_POSITION_Y then
            self:setCurrentMtSlot("y", ev.value)
        end
    elseif ev.type == EV_SYN then
        if ev.code == SYN_REPORT then
            for _, MTSlot in pairs(self.MTSlots) do
                self:setMtSlot(MTSlot.slot, "timev", TimeVal:new(ev.time))
            end
            -- feed ev in all slots to state machine
            local touch_ges = self.gesture_detector:feedEvent(self.MTSlots)
            self.MTSlots = {}
            if touch_ges then
                return Event:new("Gesture",
                    self.gesture_detector:adjustGesCoordinate(touch_ges)
                )
            end
        end
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

function Input:confirmAbsxy()
    self:setCurrentMtSlot("x", self.ev_slots[self.cur_slot]["abs_x"])
    self:setCurrentMtSlot("y", self.ev_slots[self.cur_slot]["abs_y"])
end

function Input:cleanAbsxy()
    self:setCurrentMtSlot("abs_x", nil)
    self:setCurrentMtSlot("abs_y", nil)
end


-- main event handling:

function Input:waitEvent(timeout_us, timeout_s)
    -- wrapper for input.waitForEvents that will retry for some cases
    local ok, ev
    local wait_deadline = TimeVal:now() + TimeVal:new{
            sec = timeout_s,
            usec = timeout_us
        }
    while true do
        if #self.timer_callbacks > 0 then
            -- we don't block if there is any timer, set wait to 10us
            while #self.timer_callbacks > 0 do
                ok, ev = pcall(input.waitForEvent, 100)
                if ok then break end
                local tv_now = TimeVal:now()
                if ((not timeout_us and not timeout_s) or tv_now < wait_deadline) then
                    -- check whether timer is up
                    if tv_now >= self.timer_callbacks[1].deadline then
                        local touch_ges = self.timer_callbacks[1].callback()
                        table.remove(self.timer_callbacks, 1)
                        if touch_ges then
                            -- Do we really need to clear all setTimeout after
                            -- decided a gesture? FIXME
                            self.timer_callbacks = {}
                            return Event:new("Gesture",
                                self.gesture_detector:adjustGesCoordinate(touch_ges)
                            )
                        end -- EOF if touch_ges
                    end -- EOF if deadline reached
                else
                    break
                end -- EOF if not exceed wait timeout
            end -- while #timer_callbacks > 0
        else
            ok, ev = pcall(input.waitForEvent, timeout_us)
        end -- EOF if #timer_callbacks > 0
        if ok then
            break
        end

        -- ev does contain an error message:
        if ev == "Waiting for input failed: timeout\n" then
            -- don't report an error on timeout
            ev = nil
            break
        elseif ev == "application forced to quit" then
            -- TODO: return an event that can be handled
            os.exit(0)
        end
        --DEBUG("got error waiting for events:", ev)
        if ev ~= "Waiting for input failed: 4\n" then
            -- we only abort if the error is not EINTR
            break
        end
    end

    if ok and ev then
        if DEBUG.is_on and ev then
            DEBUG:logEv(ev)
        end
        self:eventAdjustHook(ev)
        if ev.type == EV_KEY then
            DEBUG("key ev", ev)
            return self:handleKeyBoardEv(ev)
        elseif ev.type == EV_ABS or ev.type == EV_SYN then
            return self:handleTouchEv(ev)
        elseif ev.type == EV_MSC then
            return self:handleMiscEv(ev)
        else
            -- some other kind of event that we do not know yet
            return Event:new("GenericInput", ev)
        end
    elseif not ok and ev then
        return Event:new("InputError", ev)
    end
end

return Input
