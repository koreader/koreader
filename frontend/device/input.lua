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

-- luacheck: push
-- luacheck: ignore
-- constants from <linux/input.h>
local EV_SYN = 0
local EV_KEY = 1
local EV_ABS = 3
local EV_MSC = 4
-- for frontend SDL event handling
local EV_SDL = 53 -- ASCII code for S

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

-- For Kindle Oasis orientation events (ABS.code)
-- the ABS code of orientation event will be adjusted to -24 from 24(ABS_PRESSURE)
-- as ABS_PRESSURE is also used to detect touch input in KOBO devices.
local ABS_OASIS_ORIENTATION = -24
local DEVICE_ORIENTATION_PORTRAIT_LEFT = 15
local DEVICE_ORIENTATION_PORTRAIT_RIGHT = 17
local DEVICE_ORIENTATION_PORTRAIT = 19
local DEVICE_ORIENTATION_PORTRAIT_ROTATED_LEFT = 16
local DEVICE_ORIENTATION_PORTRAIT_ROTATED_RIGHT = 18
local DEVICE_ORIENTATION_PORTRAIT_ROTATED = 20
local DEVICE_ORIENTATION_LANDSCAPE = 21
local DEVICE_ORIENTATION_LANDSCAPE_ROTATED = 22

-- For the events of the Forma accelerometer (MSC.code)
local MSC_RAW = 0x03

-- For the events of the Forma accelerometer (MSC.value)
local MSC_RAW_GSENSOR_PORTRAIT_DOWN = 0x17
local MSC_RAW_GSENSOR_PORTRAIT_UP = 0x18
local MSC_RAW_GSENSOR_LANDSCAPE_RIGHT = 0x19
local MSC_RAW_GSENSOR_LANDSCAPE_LEFT = 0x1a
-- Not that we care about those, but they are reported, and accurate ;).
local MSC_RAW_GSENSOR_BACK = 0x1b
local MSC_RAW_GSENSOR_FRONT = 0x1c

-- luacheck: pop

local _internal_clipboard_text = nil -- holds the last copied text

local Input = {
    -- this depends on keyboard layout and should be overridden:
    event_map = {},
    -- adapters are post processing functions that transform a given event to another event
    event_map_adapter = {},

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

    -- keyboard state:
    modifiers = {
        Alt = false,
        Ctrl = false,
        Shift = false,
    },

    -- repeat state:
    repeat_count = 0,

    -- touch state:
    cur_slot = 0,
    MTSlots = {},
    ev_slots = {
        [0] = {
            slot = 0,
        }
    },
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

function Input:adjustKindleOasisOrientation(ev)
    if ev.type == EV_ABS and ev.code == ABS_PRESSURE then
        ev.code = ABS_OASIS_ORIENTATION
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
            -- The Forma repeats every 80ms after a 400ms delay, and 500ms roughly corresponds to a flashing update,
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
            self:addSlotIfChanged(ev.value)
        elseif ev.code == ABS_MT_TRACKING_ID then
            if self.snow_protocol then
                self:addSlotIfChanged(ev.value)
            end
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
                        slot.timev = TimeVal:new(ev.time)
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
            self:addSlotIfChanged(ev.value)
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
    if ev.type == EV_ABS then
        if #self.MTSlots == 0 then
            table.insert(self.MTSlots, self:getMtSlot(self.cur_slot))
        end
        if ev.code == ABS_X then
            self:setCurrentMtSlot("x", ev.value)
        elseif ev.code == ABS_Y then
            self:setCurrentMtSlot("y", ev.value)
        elseif ev.code == ABS_PRESSURE then
            if ev.value ~= 0 then
                self:setCurrentMtSlot("id", 1)
            else
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
    if ev.value == DEVICE_ORIENTATION_PORTRAIT
        or ev.value == DEVICE_ORIENTATION_PORTRAIT_LEFT
        or ev.value == DEVICE_ORIENTATION_PORTRAIT_RIGHT then
        rotation_mode = framebuffer.ORIENTATION_PORTRAIT
        screen_mode = 'portrait'
    elseif ev.value == DEVICE_ORIENTATION_LANDSCAPE then
        rotation_mode = framebuffer.ORIENTATION_LANDSCAPE
        screen_mode = 'landscape'
    elseif ev.value == DEVICE_ORIENTATION_PORTRAIT_ROTATED
        or ev.value == DEVICE_ORIENTATION_PORTRAIT_ROTATED_LEFT
        or ev.value == DEVICE_ORIENTATION_PORTRAIT_ROTATED_RIGHT then
        rotation_mode = framebuffer.ORIENTATION_PORTRAIT_ROTATED
        screen_mode = 'portrait'
    elseif ev.value == DEVICE_ORIENTATION_LANDSCAPE_ROTATED then
        rotation_mode = framebuffer.ORIENTATION_LANDSCAPE_ROTATED
        screen_mode = 'landscape'
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

--- Accelerometer on the Forma, c.f., drivers/hwmon/mma8x5x.c
function Input:handleMiscEvNTX(ev)
    local rotation_mode, screen_mode
    if ev.code == MSC_RAW then
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
function Input:waitEvent(timeout_us)
    local ok, ev
    -- wrapper for input.waitForEvents that will retry for some cases
    while true do
        if #self.timer_callbacks > 0 then
            local wait_deadline = TimeVal:now() + TimeVal:new{
                usec = timeout_us
            }
            -- we don't block if there is any timer, set wait to 10us
            while #self.timer_callbacks > 0 do
                ok, ev = pcall(input.waitForEvent, 100)
                if ok then break end
                local tv_now = TimeVal:now()
                if (not timeout_us or tv_now < wait_deadline) then
                    -- check whether timer is up
                    if tv_now >= self.timer_callbacks[1].deadline then
                        local touch_ges = self.timer_callbacks[1].callback()
                        table.remove(self.timer_callbacks, 1)
                        if touch_ges then
                            -- Do we really need to clear all setTimeout after
                            -- decided a gesture? FIXME
                            self.timer_callbacks = {}
                            self:gestureAdjustHook(touch_ges)
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
        local timeout_err_msg = "Waiting for input failed: timeout\n"
        -- ev may not be equal to timeout_err_msg, but it may ends with it
        -- ("./ffi/SDL2_0.lua:110: Waiting for input failed: timeout" on the emulator)
        if ev and ev.sub and ev:sub(-timeout_err_msg:len()) == timeout_err_msg then
            -- don't report an error on timeout
            ev = nil
            break
        elseif ev == "application forced to quit" then
            --- @todo return an event that can be handled
            os.exit(0)
        end
        logger.warn("got error waiting for events:", ev)
        if ev ~= "Waiting for input failed: 4\n" then
            -- we only abort if the error is not EINTR
            break
        end
    end

    if ok and ev then
        if DEBUG.is_on and ev then
            DEBUG:logEv(ev)
            logger.dbg(string.format(
                "%s event => type: %d, code: %d(%s), value: %s, time: %d.%d",
                ev.type == EV_KEY and "key" or "input",
                ev.type, ev.code, self.event_map[ev.code], tostring(ev.value),
                ev.time.sec, ev.time.usec))
        end
        self:eventAdjustHook(ev)
        if ev.type == EV_KEY then
            return self:handleKeyBoardEv(ev)
        elseif ev.type == EV_ABS and ev.code == ABS_OASIS_ORIENTATION then
            return self:handleOasisOrientationEv(ev)
        elseif ev.type == EV_ABS or ev.type == EV_SYN then
            return self:handleTouchEv(ev)
        elseif ev.type == EV_MSC then
            return self:handleMiscEv(ev)
        elseif ev.type == EV_SDL then
            return self:handleSdlEv(ev)
        else
            -- some other kind of event that we do not know yet
            return Event:new("GenericInput", ev)
        end
    elseif not ok and ev then
        return Event:new("InputError", ev)
    end
end

return Input
