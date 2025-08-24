--[[--
An interface to get input events.
--]]

local DataStorage = require("datastorage")
local DEBUG = require("dbg")
local Event = require("ui/event")
local GestureDetector = require("device/gesturedetector")
local Key = require("device/key")
local UIManager
local framebuffer = require("ffi/framebuffer")
local logger = require("logger")
local time = require("ui/time")
local _ = require("gettext")

-- We're going to need a few <linux/input.h> constants...
local ffi = require("ffi")
local C = ffi.C
require("ffi/posix_h")
require("ffi/linux_input_h")

-- EV_KEY values
local KEY_PRESS   = 1
local KEY_REPEAT  = 2
local KEY_RELEASE = 0

-- Based on ABS_MT_TOOL_TYPE values on Elan panels
local TOOL_TYPE_FINGER = 0
local TOOL_TYPE_PEN    = 1

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
    [C.KEY_BATTERY] = "KEY_BATTERY",
    [C.BTN_TOOL_PEN] = "BTN_TOOL_PEN",
    [C.BTN_TOOL_FINGER] = "BTN_TOOL_FINGER",
    [C.BTN_TOOL_RUBBER] = "BTN_TOOL_RUBBER",
    [C.BTN_TOUCH] = "BTN_TOUCH",
    [C.BTN_STYLUS] = "BTN_STYLUS",
    [C.BTN_STYLUS2] = "BTN_STYLUS2",
    [C.BTN_TOOL_DOUBLETAP] = "BTN_TOOL_DOUBLETAP",
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
    [C.MSC_GYRO] = "MSC_GYRO",
}

local linux_evdev_rep_code_map = {
    [C.REP_DELAY] = "REP_DELAY",
    [C.REP_PERIOD] = "REP_PERIOD",
}

local _internal_clipboard_text = "" -- holds the last copied text

local Input = {
    -- must point to the device implementation when instantiating
    device = nil,
    -- this depends on keyboard layout and should be overridden
    event_map = nil, -- hash
    -- adapters are post processing functions that transform a given event to another event
    event_map_adapter = nil, -- hash
    -- EV_ABS event to honor for pressure event (if any)
    pressure_event = nil,

    group = {
        Cursor = { "Up", "Down", "Left", "Right" },
        PgFwd = { "RPgFwd", "LPgFwd" },
        PgBack = { "RPgBack", "LPgBack" },
        Back = { "Back" },
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
            "Back", "Sym", "AA", "Menu", "Home", "Del", "ScreenKB",
            "LPgBack", "RPgBack", "LPgFwd", "RPgFwd"
        },
    },

    fake_event_set = {
        IntoSS = true, OutOfSS = true, ExitingSS = true,
        UsbPlugIn = true, UsbPlugOut = true,
        Charging = true, NotCharging = true,
        WakeupFromSuspend = true, ReadyToSuspend = true,
        UsbDevicePlugIn = true, UsbDevicePlugOut = true,
    },
    -- Crappy FIFO to forward parameters to UIManager for the subset of fake_event_set that require passing a parameter along
    fake_event_args = {
        UsbDevicePlugIn = {},
        UsbDevicePlugOut = {},
    },

    -- This might be modified at runtime, so we don't want any inheritance
    rotation_map = nil, -- hash

    timer_callbacks = nil, -- instance-specific table, because the object may get destroyed & recreated at runtime
    disable_double_tap = true,
    tap_interval_override = nil,

    -- keyboard state:
    modifiers = {
        Alt = false,
        Ctrl = false,
        Shift = false,
        Sym = false,
        Meta = false,
        ScreenKB = false,
    },

    -- repeat state:
    repeat_count = 0,

    -- touch state:
    main_finger_slot = 0,
    pen_slot = 4,
    cur_slot = 0,
    MTSlots = nil, -- table, object may be replaced at runtime
    active_slots = nil, -- ditto
    ev_slots = nil, -- table
    gesture_detector = nil,

    -- simple internal clipboard implementation, can be overridden to use system clipboard
    hasClipboardText = function()
        return _internal_clipboard_text ~= ""
    end,
    getClipboardText = function()
        return _internal_clipboard_text
    end,
    setClipboardText = function(text)
        _internal_clipboard_text = text or ""
    end,

    -- open'ed input devices hashmap (key: path, value: fd number)
    -- Must be a class member, both because Input is a singleton and that state is process-wide anyway.
    opened_devices = {},
}

function Input:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    if o.init then o:init() end
    return o
end

function Input:init()
    -- Setup underlying input implementation.
    if self.input then -- luacheck: ignore 542
        -- Already setup (e.g. stubbed by the testsuite).
    elseif self.device:isSDL() then
        self.input = require("ffi/input_SDL2_0")
        self.hasClipboardText = function()
            return self.input.hasClipboardText()
        end
        self.getClipboardText = function()
            return self.input.getClipboardText()
        end
        self.setClipboardText = function(text)
            return self.input.setClipboardText(text)
        end
        self.gameControllerRumble = function(left_intensity, right_intensity, duration)
            return self.input.gameControllerRumble(left_intensity, right_intensity, duration)
        end
    elseif self.device:isAndroid() then
        self.input = require("ffi/input_android")
    elseif self.device:isPocketBook() then
        self.input = require("ffi/input_pocketbook")
    else
        self.input = require("libs/libkoreader-input")
    end

    -- Initialize instance-specific tables
    -- NOTE: All of these arrays may be destroyed & recreated at runtime, so we don't want a parent/class object for those.
    self.timer_callbacks = {}
    self.MTSlots = {}
    self.active_slots = {}

    -- Handle default finger slot
    self.cur_slot = self.main_finger_slot
    self.ev_slots = {
        [self.main_finger_slot] = {
            slot = self.main_finger_slot,
        },
    }

    -- Always send pen data to a slot far enough away from our main finger slot that it can never be matched with a finger buddy in GestureDetector (i.e., +/- 1),
    -- with an extra bit of leeway, since we don't even actually support three finger gestures ;).
    self.pen_slot = self.main_finger_slot + 4

    self.gesture_detector = GestureDetector:new{
        screen = self.device.screen,
        input = self,
    }

    if not self.event_map then
        self.event_map = {}
    end
    if not self.event_map_adapter then
        self.event_map_adapter = {}
    end

    -- NOTE: When looking at the device in Portrait mode, that's assuming PgBack is on TOP, and PgFwd on the BOTTOM
    if not self.rotation_map then
        self.rotation_map = {
            [framebuffer.DEVICE_ROTATED_UPRIGHT]           = {},
            [framebuffer.DEVICE_ROTATED_CLOCKWISE]         = { Up = "Right", Right = "Down", Down = "Left",  Left = "Up",    LPgBack = "LPgFwd",  LPgFwd  = "LPgBack", RPgBack = "RPgFwd",  RPgFwd  = "RPgBack" },
            [framebuffer.DEVICE_ROTATED_UPSIDE_DOWN]       = { Up = "Down",  Right = "Left", Down = "Up",    Left = "Right", LPgFwd  = "LPgBack", LPgBack = "LPgFwd",  RPgFwd  = "RPgBack", RPgBack = "RPgFwd" },
            [framebuffer.DEVICE_ROTATED_COUNTER_CLOCKWISE] = { Up = "Left",  Right = "Up",   Down = "Right", Left = "Down" },
        }
    end

    -- set up fake event map
    self.event_map[10000] = "IntoSS" -- Requested to go into screen saver
    self.event_map[10001] = "OutOfSS" -- Requested to go out of screen saver
    self.event_map[10002] = "ExitingSS" -- Specific to Kindle, SS *actually* closed
    self.event_map[10010] = "UsbPlugIn"
    self.event_map[10011] = "UsbPlugOut"
    self.event_map[10020] = "Charging"
    self.event_map[10021] = "NotCharging"
    self.event_map[10030] = "WakeupFromSuspend"
    self.event_map[10031] = "ReadyToSuspend"
    self.event_map[10040] = "UsbDevicePlugIn"
    self.event_map[10041] = "UsbDevicePlugOut"

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

    if G_reader_settings:isTrue("backspace_as_back") then
        table.insert(self.group.Back, "Backspace")
    end

    -- setup inhibitInputUntil scheduling function
    self._inhibitInputUntil_func = function() self:inhibitInputUntil() end
end

function Input:UIManagerReady(uimgr)
    UIManager = uimgr
end

--[[--
Setup a rotation_map that does nothing (for platforms where the events we get are already translated).
--]]
function Input:disableRotationMap()
    self.rotation_map = {
        [framebuffer.DEVICE_ROTATED_UPRIGHT]           = {},
        [framebuffer.DEVICE_ROTATED_CLOCKWISE]         = {},
        [framebuffer.DEVICE_ROTATED_UPSIDE_DOWN]       = {},
        [framebuffer.DEVICE_ROTATED_COUNTER_CLOCKWISE] = {},
    }
end

--[[--
Wrapper for our Lua/C input module's open.

Note that we adhere to the "." syntax here for compatibility.

The `name` argument is optional, and used for logging purposes only.
--]]
function Input:open(path, name)
    if self.input.is_ffi then
        return self.input.open(path, name)
    end
    -- Make sure we don't open the same device twice.
    if not Input.opened_devices[path] then
        local fd = self.input.open(path)
        if fd then
            Input.opened_devices[path] = fd
            if name then
                logger.dbg("Opened fd", fd, "for input device", name, "@", path)
            else
                logger.dbg("Opened fd", fd, "for input device @", path)
            end
        end
        -- No need to log failures, input will have raised an error already,
        -- and we want to make those fatal, so we don't protect this call.
        return fd
    end
end

--[[--
Wrapper for our Lua/C input module's fdopen.

Note that we adhere to the "." syntax here for compatibility.

The `name` argument is optional, and used for logging purposes only.
`path` is mandatory, though!
--]]
function Input:fdopen(fd, path, name)
    -- Make sure we don't open the same device twice.
    if not Input.opened_devices[path] then
        self.input.fdopen(fd)
        -- As with input.open, it will throw on error (closing the fd first)
        Input.opened_devices[path] = fd
        if name then
            logger.dbg("Kept fd", fd, "open for input device", name, "@", path)
        else
            logger.dbg("Kept fd", fd, "open for input device @", path)
        end
        return fd
    end
end

--[[--
Wrapper for our Lua/C input module's close.

Note that we adhere to the "." syntax here for compatibility.
--]]
function Input:close(path)
    if self.input.is_ffi then
        return self.input.close(path)
    end
    -- Make sure we actually know about this device
    local fd = Input.opened_devices[path]
    if fd then
        local ok, err = self.input.close(fd)
        if ok or err == C.ENODEV then
            -- Either the call succeeded,
            -- or the backend had already caught an ENODEV in waitForInput and closed the fd internally.
            -- (Because the EvdevInputRemove Event comes from an UsbDevicePlugOut uevent forwarded as an... *input* EV_KEY event ;)).
            -- Regardless, that device is gone, so clear its spot in the hashmap.
            Input.opened_devices[path] = nil
        end
    else
        logger.warn("Tried to close an unknown input device @", path)
    end
end

--[[--
Wrapper for our Lua/C input module's closeAll.

Note that we adhere to the "." syntax here for compatibility.
--]]
function Input:teardown()
    self.input.closeAll()
    Input.opened_devices = {}
end

--[[--
Different device models can implement their own hooks and register them.
--]]
function Input:registerEventAdjustHook(hook, hook_params)
    if self.eventAdjustHook == Input.eventAdjustHook then
        -- First custom hook, skip the default NOP
        self.eventAdjustHook = function(this, ev)
            hook(this, ev, hook_params)
        end
    else
        -- We've already got a custom hook, chain 'em
        local old = self.eventAdjustHook
        self.eventAdjustHook = function(this, ev)
            old(this, ev)
            hook(this, ev, hook_params)
        end
    end
end

function Input:registerGestureAdjustHook(hook, hook_params)
    if self.gestureAdjustHook == Input.gestureAdjustHook then
        self.gestureAdjustHook = function(this, ges)
            hook(this, ges, hook_params)
        end
    else
        local old = self.gestureAdjustHook
        self.gestureAdjustHook = function(this, ges)
            old(this, ges)
            hook(this, ges, hook_params)
        end
    end
end

function Input:eventAdjustHook(ev)
    -- do nothing by default
end

function Input:gestureAdjustHook(ges)
    -- do nothing by default
end

--- Catalog of predefined hooks.
-- These are *not* usable directly as hooks, they're just building blocks (c.f., Kobo)
function Input:adjustABS_SwitchXY(ev)
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

function Input:adjustABS_Scale(ev, by)
    if ev.code == C.ABS_X or ev.code == C.ABS_MT_POSITION_X then
        ev.value = by.x * ev.value
    elseif ev.code == C.ABS_Y or ev.code == C.ABS_MT_POSITION_Y then
        ev.value = by.y * ev.value
    end
end

function Input:adjustABS_MirrorX(ev, max_x)
    if ev.code == C.ABS_X or ev.code == C.ABS_MT_POSITION_X then
        ev.value = max_x - ev.value
    end
end

function Input:adjustABS_MirrorY(ev, max_y)
    if ev.code == C.ABS_Y or ev.code == C.ABS_MT_POSITION_Y then
        ev.value = max_y - ev.value
    end
end

function Input:adjustABS_SwitchAxesAndMirrorX(ev, max_x)
    if ev.code == C.ABS_X then
        ev.code = C.ABS_Y
    elseif ev.code == C.ABS_Y then
        ev.code = C.ABS_X
        ev.value = max_x - ev.value
    elseif ev.code == C.ABS_MT_POSITION_X then
        ev.code = C.ABS_MT_POSITION_Y
    elseif ev.code == C.ABS_MT_POSITION_Y then
        ev.code = C.ABS_MT_POSITION_X
        ev.value = max_x - ev.value
    end
end

function Input:adjustABS_SwitchAxesAndMirrorY(ev, max_y)
    if ev.code == C.ABS_X then
        ev.code = C.ABS_Y
        ev.value = max_y - ev.value
    elseif ev.code == C.ABS_Y then
        ev.code = C.ABS_X
    elseif ev.code == C.ABS_MT_POSITION_X then
        ev.code = C.ABS_MT_POSITION_Y
        ev.value = max_y - ev.value
    elseif ev.code == C.ABS_MT_POSITION_Y then
        ev.code = C.ABS_MT_POSITION_X
    end
end

function Input:adjustABS_Translate(ev, by)
    if ev.code == C.ABS_X or ev.code == C.ABS_MT_POSITION_X then
        ev.value = by.x + ev.value
    elseif ev.code == C.ABS_Y or ev.code == C.ABS_MT_POSITION_Y then
        ev.value = by.y + ev.value
    end
end

-- These *are* usable directly as hooks
function Input:adjustTouchScale(ev, by)
    if ev.type == C.EV_ABS then
        self:adjustABS_Scale(ev, by)
    end
end

function Input:adjustTouchSwitchAxesAndMirrorX(ev, max_x)
    if ev.type == C.EV_ABS then
        self:adjustABS_SwitchAxesAndMirrorX(ev, max_x)
    end
end

function Input:adjustTouchTranslate(ev, by)
    if ev.type == C.EV_ABS then
        self:adjustABS_Translate(ev, by)
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
    if self.input.setTimer then
        -- If GestureDetector's clock source probing was inconclusive, do this on the UI timescale instead.
        if clock_id == -1 then
            deadline = time.now() + delay
            clock_id = C.CLOCK_MONOTONIC
        else
            deadline = origin + delay
        end
        -- What this does is essentially to ask the kernel to wake us up when the timer expires,
        -- instead of ensuring that ourselves via a polling timeout.
        -- This ensures perfect accuracy, and allows it to be computed in the event's own timescale.
        local sec, usec = time.split_s_us(deadline)
        timerfd = self.input.setTimer(clock_id, sec, usec)
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
            deadline = time.now() + delay
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
                self.input.clearTimer(item.timerfd)
            end
            table.remove(self.timer_callbacks, i)
        end
    end
end

function Input:clearTimeouts()
    -- If the timerfd backend is in use, close the fds, too
    if self.input.setTimer then
        for _, item in ipairs(self.timer_callbacks) do
            if item.timerfd then
                self.input.clearTimer(item.timerfd)
            end
        end
    end

    self.timer_callbacks = {}
end

-- Reset the gesture parsing state to a blank slate
function Input:resetState()
    if self.gesture_detector then
        self.gesture_detector:dropContacts()
        -- Resets the clock source probe
        self.gesture_detector:resetClockSource()
    end
    self:clearTimeouts()

    -- Drop the slots on our end, too
    self:newFrame()
    self.cur_slot = self.main_finger_slot
    self.ev_slots = {
        [self.main_finger_slot] = {
            slot = self.main_finger_slot,
        },
    }
end

function Input:handleKeyBoardEv(ev)
    -- Detect loss of contact for the "snow" protocol, as we *never* get EV_ABS:ABS_MT_TRACKING_ID:-1 on those...
    -- NOTE: The same logic *could* be used on *some* ST devices to detect contact states,
    --       but we instead prefer using EV_ABS:ABS_PRESSURE on those,
    --       as it appears to be more common than EV_KEY:BTN_TOUCH on the devices we care about...
    if self.snow_protocol then
        if ev.code == C.BTN_TOUCH then
            if ev.value == 0 then
                -- Kernel sends it after loss of contact for *all* slots,
                -- only once the final contact point has been lifted.
                if #self.MTSlots == 0 then
                    -- Likely, since this is usually in its own input frame,
                    -- meaning self.MTSlots has *just* been cleared by our last EV_SYN:SYN_REPORT handler...
                    -- So, poke at the actual data to find the slots that are currently active (i.e., in the down state),
                    -- and re-populate a minimal self.MTSlots array that simply switches them to the up state ;).
                    for _, slot in pairs(self.ev_slots) do
                        if slot.id ~= -1 then
                            table.insert(self.MTSlots, slot)
                            slot.id = -1
                        end
                    end
                else
                    -- Unlikely, given what we mentioned above...
                    -- Note that, funnily enough, its EV_KEY:BTN_TOUCH:1 counterpart
                    -- *can* be in the same initial input frame as the EV_ABS batch...
                    for _, MTSlot in ipairs(self.MTSlots) do
                        self:setMtSlot(MTSlot.slot, "id", -1)
                    end
                end
            end

            return
        end
    elseif self.wacom_protocol then
        if ev.code == C.BTN_TOOL_PEN then
            -- Switch to the dedicated pen slot, and make sure it's active, as this can come in a dedicated input frame
            self:setupSlotData(self.pen_slot)
            if ev.value == 1 then
                self:setCurrentMtSlot("tool", TOOL_TYPE_PEN)
            else
                self:setCurrentMtSlot("tool", TOOL_TYPE_FINGER)
                -- Switch back to our main finger slot
                self.cur_slot = self.main_finger_slot
            end

            return
        elseif ev.code == C.BTN_TOUCH then
            -- BTN_TOUCH is bracketed by BTN_TOOL_PEN, so we can limit this to pens, to avoid stomping on panel slots.
            if self:getCurrentMtSlotData("tool") == TOOL_TYPE_PEN then
                -- Make sure the pen slot is active, as this can come in a dedicated input frame
                -- (i.e., we need it to be referenced by self.MTSlots for the lift to be picked up in the EV_SYN:SYN_REPORT handler).
                -- (Conversely, getCurrentMtSlotData pokes at the *persistent* slot data in self.ev_slots,
                -- so it can keep track of data across input frames).
                self:setupSlotData(self.pen_slot)
                -- Much like on snow, use this to detect contact down & lift,
                -- as ABS_PRESSURE may be entirely omitted from hover events,
                -- and ABS_DISTANCE is not very clear cut...
                if ev.value == 1 then
                    self:setCurrentMtSlot("id", self.pen_slot)
                else
                    self:setCurrentMtSlot("id", -1)
                end
            end

            return
        end
    end
    -- On (some?) Kindles, cyttsp will report BTN_TOOL_DOUBLETAP on a two-slot contact... but with no data in the second slot :/.
    -- c.f., https://github.com/koreader/koreader/pull/13714
    if ev.code == C.BTN_TOOL_DOUBLETAP and ev.value == 1 and self.cur_slot ~= self.main_finger_slot and (self:getCurrentMtSlotData("x") == nil or self:getCurrentMtSlotData("y") == nil) then
        -- Drop the empty slot to avoid breaking GestureDetector
        self:setCurrentMtSlot("id", -1)

        return
    end

    local keycode = self.event_map[ev.code]
    if not keycode then
        -- do not handle keypress for keys we don't know
        return
    end

    if self.event_map_adapter[keycode] then
        return self.event_map_adapter[keycode](ev)
    end

    -- take device rotation into account
    local rota = self.device.screen:getRotationMode()
    if self.rotation_map[rota][keycode] then
        keycode = self.rotation_map[rota][keycode]
    end

    if self.fake_event_set[keycode] then
        -- For events that pass a parameter in the input event's value field,
        -- we kludge it up a bit, because we *want* a broadcastEvent *and* an argument, but...
        -- * If we return an Event here, UIManager.event_handlers.__default__ will just pass it to UIManager:sendEvent(),
        --   meaning it won't reach plugins (because these are not, and currently cannot be, registered as active_widgets).
        -- * If we return a string here, our named UIManager.event_handlers cannot directly receive an argument...
        -- So, we simply store it somewhere our handler can find and call it a day.
        -- And we use an array as a FIFO because we cannot guarantee that insertions and removals will interleave nicely.
        -- (This is all in the name of avoiding complexifying the common codepaths for events that should be few and far between).
        if self.fake_event_args[keycode] then
            table.insert(self.fake_event_args[keycode], ev.value)
        end
        return keycode
    end

    if keycode == "Power" then
        -- Kobo generates Power keycode only, we need to decide whether it's
        -- power-on or power-off ourselves.
        if ev.value == KEY_PRESS then
            return "PowerPress"
        elseif ev.value == KEY_RELEASE then
            return "PowerRelease"
        end
    end

    -- toggle fullscreen on F11
    if self:isEvKeyPress(ev) and keycode == "F11" and not self.device:isAlwaysFullscreen() then
        UIManager:broadcastEvent(Event:new("ToggleFullscreen"))
    end

    -- quit on Alt + F4
    -- this is also emitted by the close event in SDL
    if self:isEvKeyPress(ev) and self.modifiers["Alt"] and keycode == "F4" then
        UIManager:broadcastEvent(Event:new("Close")) -- Tell all widgets to close.
        UIManager:nextTick(function() UIManager:quit() end) -- Ensure the program closes in case of some lingering dialog.
    end

    -- handle modifier keys
    if self.modifiers[keycode] ~= nil then
        if ev.value == KEY_PRESS then
            self.modifiers[keycode] = true
        elseif ev.value == KEY_RELEASE then
            self.modifiers[keycode] = false
        end
        return
    end

    local key = Key:new(keycode, self.modifiers)

    if ev.value == KEY_PRESS then
        return Event:new("KeyPress", key)
    elseif ev.value == KEY_REPEAT then
        -- NOTE: We only care about repeat events from the page-turn buttons and cursor keys...
        --       And we *definitely* don't want to flood the Event queue with useless SleepCover repeats!
        if keycode == "Up" or keycode == "Down" or keycode == "Left" or keycode == "Right"
         or keycode == "RPgBack" or keycode == "RPgFwd" or keycode == "LPgBack" or keycode == "LPgFwd" then
            --- @fixme Crappy event staggering!
            --
            -- The Forma & co repeats every 80ms after a 400ms delay, and 500ms roughly corresponds to a flashing update,
            -- so stuff is usually in sync when you release the key.
            --
            -- A better approach would be an onKeyRelease handler that flushes the Event queue...
            local rep_period = self.device.key_repeat and self.device.key_repeat[C.REP_PERIOD] or 80
            local now = time.now()
            if not self.last_repeat_time then
                self.last_repeat_time = now
                return Event:new("KeyRepeat", key)
            else
                local time_diff = time.to_ms(now - self.last_repeat_time)
                if time_diff >= rep_period then
                    self.last_repeat_time = now
                    return Event:new("KeyRepeat", key)
                end
            end
        end
    elseif ev.value == KEY_RELEASE then
        self.last_repeat_time = nil
        return Event:new("KeyRelease", key)
    end
end

-- Mangled variant of handleKeyBoardEv that will only handle power management related keys.
-- (Used when blocking input during suspend via sleep cover).
function Input:handlePowerManagementOnlyEv(ev)
    local keycode = self.event_map[ev.code]
    if not keycode then
        -- Do not handle keypress for keys we don't know
        return
    end

    -- We'll need to parse the synthetic event map, because SleepCover* events are synthetic.
    if self.event_map_adapter[keycode] then
        keycode = self.event_map_adapter[keycode](ev)
    end

    -- Power management synthetic events
    if keycode == "SleepCoverClosed" or keycode == "SleepCoverOpened"
    or keycode == "Suspend" or keycode == "Resume" then
        return keycode
    end

    -- Treat page turn button like the latest kobo firmware when suspended
    if G_reader_settings:isTrue("pageturn_power") then
        if keycode == "RPgBack" or keycode == "LPgBack"
        or keycode == "RPgFwd" or keycode == "LPgFwd" then
            -- When suspended, pretend that the page turn button is *almost* a power button...
            if ev.value == KEY_PRESS or ev.value == KEY_REPEAT then
                -- Swallow key press/release events to avoid sending unbalanced events for the actual key being pressed
                return
            elseif ev.value == KEY_RELEASE then
                -- We only want to deal with key release events,
                -- to avoid tripping the Kobo-specific "poweroff on hold" PowerPress handler...
                -- (i.e., Power is a very very specific case where unbalanced press/release events *should* be fine).
                return "PowerRelease"
            end
        end
    end

    if self.fake_event_set[keycode] then
        if self.fake_event_args[keycode] then
            table.insert(self.fake_event_args[keycode], ev.value)
        end
        return keycode
    end

    if keycode == "Power" then
        -- Kobo generates Power keycode only, we need to decide whether it's
        -- power-on or power-off ourselves.
        if ev.value == KEY_PRESS then
            return "PowerPress"
        elseif ev.value == KEY_RELEASE then
            return "PowerRelease"
        end
    end

    -- Make sure we don't leave modifiers in an inconsistent state
    if self.modifiers[keycode] ~= nil then
        if ev.value == KEY_PRESS then
            self.modifiers[keycode] = true
        elseif ev.value == KEY_RELEASE then
            self.modifiers[keycode] = false
        end
        return
    end

    -- Nothing to see, move along!
    return
end

-- Empty event handler used to send input to the void
function Input:voidEv(ev)
    return
end

-- Generic event handler for unhandled input events
function Input:handleGenericEv(ev)
    return Event:new("GenericInput", ev)
end

function Input:handleMiscEv(ev)
    -- overwritten by device implementation
end

function Input:handleGyroEv(ev)
    -- setup by the Generic device implementation (for proper toggle handling)
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
        -- NOTE: Ideally, an input frame starts with either ABS_MT_SLOT or ABS_MT_TRACKING_ID,
        --       but they *both* may be omitted if the last contact point just moved without lift.
        --       The use of setCurrentMtSlotChecked instead of setCurrentMtSlot ensures
        --       we actually setup the slot data storage and/or reference for the current slot in this case,
        --       as the reference list is empty at the beginning of an input frame (c.f., Input:newFrame).
        --       The most common platforms where you'll see this happen are:
        --       * PocketBook, because of our InkView EVT_POINTERMOVE translation
        --         (c.f., translateEvent @ ffi/input_pocketbook.lua).
        --       * SDL, because of our SDL_MOUSEMOTION/SDL_FINGERMOTION translation
        --         (c.f., waitForEvent @ ffi/SDL2_0.lua).
        if ev.code == C.ABS_MT_SLOT then
            self:setupSlotData(ev.value)
        elseif ev.code == C.ABS_MT_TRACKING_ID then
            self:setCurrentMtSlotChecked("id", ev.value)
        elseif ev.code == C.ABS_MT_TOOL_TYPE then
            -- NOTE: On the Elipsa: Finger == 0; Pen == 1
            self:setCurrentMtSlot("tool", ev.value)
        elseif ev.code == C.ABS_MT_POSITION_X or ev.code == C.ABS_X then
            self:setCurrentMtSlotChecked("x", ev.value)
        elseif ev.code == C.ABS_MT_POSITION_Y or ev.code == C.ABS_Y then
            self:setCurrentMtSlotChecked("y", ev.value)
        elseif ev.code == self.pressure_event and ev.value == 0 then
            -- Drop hovering *pen* events
            if self:getCurrentMtSlotData("tool") == TOOL_TYPE_PEN then
                self:setCurrentMtSlot("id", -1)
            end
        end
    elseif ev.type == C.EV_SYN then
        if ev.code == C.SYN_REPORT then
            for _, MTSlot in ipairs(self.MTSlots) do
                self:setMtSlot(MTSlot.slot, "timev", time.timeval(ev.time))
            end
            -- feed ev in all slots to state machine
            local touch_gestures = self.gesture_detector:feedEvent(self.MTSlots)
            self:newFrame()
            local ges_evs = {}
            for _, touch_ges in ipairs(touch_gestures) do
                self:gestureAdjustHook(touch_ges)
                table.insert(ges_evs, Event:new("Gesture", self.gesture_detector:adjustGesCoordinate(touch_ges)))
            end
            return ges_evs
        end
    end
end

-- This is a slightly modified version of the above, tailored to play nice with devices with multiple absolute input devices,
-- (i.e., screen + pen), where one or both of these send conflicting events that we need to hook... (e.g., rM on mainline).
function Input:handleMixedTouchEv(ev)
    if ev.type == C.EV_ABS then
        if ev.code == C.ABS_MT_SLOT then
            self:setupSlotData(ev.value)
        elseif ev.code == C.ABS_MT_TRACKING_ID then
            self:setCurrentMtSlotChecked("id", ev.value)
        elseif ev.code == C.ABS_MT_POSITION_X then
            -- Panel
            self:setCurrentMtSlotChecked("x", ev.value)
        elseif ev.code == C.ABS_X then
            -- Panel + Stylus, but we only want to honor stylus!
            if self:getCurrentMtSlotData("tool") == TOOL_TYPE_PEN then
                self:setCurrentMtSlotChecked("x", ev.value)
            end
        elseif ev.code == C.ABS_MT_POSITION_Y then
            self:setCurrentMtSlotChecked("y", ev.value)
        elseif ev.code == C.ABS_Y then
            if self:getCurrentMtSlotData("tool") == TOOL_TYPE_PEN then
                self:setCurrentMtSlotChecked("y", ev.value)
            end
        end
    elseif ev.type == C.EV_SYN then
        if ev.code == C.SYN_REPORT then
            for _, MTSlot in ipairs(self.MTSlots) do
                self:setMtSlot(MTSlot.slot, "timev", time.timeval(ev.time))
            end
            -- feed ev in all slots to state machine
            local touch_gestures = self.gesture_detector:feedEvent(self.MTSlots)
            self:newFrame()
            local ges_evs = {}
            for _, touch_ges in ipairs(touch_gestures) do
                self:gestureAdjustHook(touch_ges)
                table.insert(ges_evs, Event:new("Gesture", self.gesture_detector:adjustGesCoordinate(touch_ges)))
            end
            return ges_evs
        end
    end
end

-- Slightly mangled variant of handleTouchEv to deal with the various quirks of the so-called "snow" protocol over the years...
function Input:handleTouchEvSnow(ev)
    if ev.type == C.EV_ABS then
        -- NOTE: Ideally, an input frame starts with either ABS_MT_SLOT or ABS_MT_TRACKING_ID,
        --       but they *both* may be omitted if the last contact point just moved without lift.
        --       The use of setCurrentMtSlotChecked instead of setCurrentMtSlot ensures
        --       we actually setup the slot data storage and/or reference for the current slot in this case,
        --       as the reference list is empty at the beginning of an input frame (c.f., Input:newFrame).
        --       The most common platforms where you'll see this happen are:
        --       * PocketBook, because of our InkView EVT_POINTERMOVE translation
        --         (c.f., translateEvent @ ffi/input_pocketbook.lua).
        --       * SDL, because of our SDL_MOUSEMOTION/SDL_FINGERMOTION translation
        --         (c.f., waitForEvent @ ffi/SDL2_0.lua).
        if ev.code == C.ABS_MT_SLOT then
            self:setupSlotData(ev.value)
        elseif ev.code == C.ABS_MT_TRACKING_ID then
            -- NOTE: We'll never get an ABS_MT_SLOT event, instead we have a slot-like ABS_MT_TRACKING_ID value...
            --       This also means that, unlike on sane devices, this will *never* be set to -1 on contact lift,
            --       which is why we instead have to rely on EV_KEY:BTN_TOUCH:0 for that (c.f., handleKeyBoardEv).
            if ev.value == -1 then
                -- NOTE: While *actual* snow_protocol devices will *never* emit an EV_ABS:ABS_MT_TRACKING_ID:-1 event,
                --       we've seen brand new revisions of snow_protocol devices shipping with sane panels instead,
                --       so we'll need to disable the quirks at runtime to handle these properly...
                --       (c.f., https://www.mobileread.com/forums/showpost.php?p=4383629&postcount=997).
                -- NOTE: Simply skipping the slot storage setup for -1 would not be enough, as it would only fix ST handling.
                --       MT would be broken, because buddy contact detection in GestureDetector looks at slot +/- 1,
                --       whereas we'd be having the main contact point at a stupidly large slot number
                --       (because it would match ABS_MT_TRACKING_ID, given the lack of ABS_MT_SLOT, at least for the first input frame),
                --       while the second contact would be at slot 1, because it would immediately have required emitting a proper ABS_MT_SLOT event...
                logger.warn("Input: Disabled snow_protocol quirks because your device's hardware revision doesn't appear to need them!")
                self.snow_protocol = false
                self.handleTouchEv = Input.handleTouchEv
            else
                self:setupSlotData(ev.value)
            end
            self:setCurrentMtSlotChecked("id", ev.value)
        elseif ev.code == C.ABS_MT_TOOL_TYPE then
            -- NOTE: On the Elipsa: Finger == 0; Pen == 1
            self:setCurrentMtSlot("tool", ev.value)
        -- NOTE: We ignore ABS_X & ABS_Y, as they may be reported for *multiple* contacts on the BTN_TOUCH:0 frame...
        --       ...without a corresponding ABS_MT_SLOT or ABS_MT_TRACKING_ID, of course... (#11910)
        elseif ev.code == C.ABS_MT_POSITION_X then
            self:setCurrentMtSlotChecked("x", ev.value)
        elseif ev.code == C.ABS_MT_POSITION_Y then
            self:setCurrentMtSlotChecked("y", ev.value)
        -- NOTE: Similarly, we can't honor ABS_PRESSURE for the same reason as ABS_X & ABS_Y...
        end
    elseif ev.type == C.EV_SYN then
        if ev.code == C.SYN_REPORT then
            for _, MTSlot in ipairs(self.MTSlots) do
                self:setMtSlot(MTSlot.slot, "timev", time.timeval(ev.time))
            end
            -- feed ev in all slots to state machine
            local touch_gestures = self.gesture_detector:feedEvent(self.MTSlots)
            self:newFrame()
            local ges_evs = {}
            for _, touch_ges in ipairs(touch_gestures) do
                self:gestureAdjustHook(touch_ges)
                table.insert(ges_evs, Event:new("Gesture", self.gesture_detector:adjustGesCoordinate(touch_ges)))
            end
            return ges_evs
        end
    end
end

function Input:handleTouchEvPhoenix(ev)
    -- Hack on handleTouchEv for the Kobo Aura
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
        if ev.code == C.ABS_MT_TRACKING_ID then
            self:setupSlotData(ev.value)
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
            for _, MTSlot in ipairs(self.MTSlots) do
                self:setMtSlot(MTSlot.slot, "timev", time.timeval(ev.time))
            end
            -- feed ev in all slots to state machine
            local touch_gestures = self.gesture_detector:feedEvent(self.MTSlots)
            self:newFrame()
            local ges_evs = {}
            for _, touch_ges in ipairs(touch_gestures) do
                self:gestureAdjustHook(touch_ges)
                table.insert(ges_evs, Event:new("Gesture", self.gesture_detector:adjustGesCoordinate(touch_ges)))
            end
            return ges_evs
        end
    end
end

function Input:handleTouchEvLegacy(ev)
    -- Single Touch Protocol.
    -- Some devices emit both singletouch and multitouch events.
    -- On those devices, `handleTouchEv` may not behave as expected. Use this one instead.
    if ev.type == C.EV_ABS then
        if ev.code == C.ABS_X then
            self:setCurrentMtSlotChecked("x", ev.value)
        elseif ev.code == C.ABS_Y then
            self:setCurrentMtSlotChecked("y", ev.value)
        elseif ev.code == C.ABS_PRESSURE then
            -- This is the least common denominator we can use to detect contact down & lift...
            if ev.value ~= 0 then
                self:setCurrentMtSlotChecked("id", 1)
            else
                self:setCurrentMtSlotChecked("id", -1)

                -- On Kobo Mk. 3 devices, the frame that reports a contact lift *actually* does the coordinates transform for us...
                -- Unfortunately, our own transforms are not stateful, so, just revert 'em here,
                -- since we can't simply avoid not doing 'em for that frame...
                -- c.f., https://github.com/koreader/koreader/issues/2128#issuecomment-1236289909 for logs on a Touch B
                -- NOTE: We can afford to do this here instead of on SYN_REPORT because the kernel *always*
                --       reports ABS_PRESSURE after ABS_X/ABS_Y.
                if self.touch_kobo_mk3_protocol then
                    local y = 599 - self:getCurrentMtSlotData("x") -- Mk. 3 devices are all 600x800, so just hard-code it here.
                    local x = self:getCurrentMtSlotData("y")
                    self:setCurrentMtSlot("x", x)
                    self:setCurrentMtSlot("y", y)
                end
            end
        end
    elseif ev.type == C.EV_SYN then
        if ev.code == C.SYN_REPORT then
            for _, MTSlot in ipairs(self.MTSlots) do
                self:setMtSlot(MTSlot.slot, "timev", time.timeval(ev.time))
            end

            -- feed ev in all slots to state machine
            local touch_gestures = self.gesture_detector:feedEvent(self.MTSlots)
            self:newFrame()
            local ges_evs = {}
            for _, touch_ges in ipairs(touch_gestures) do
                self:gestureAdjustHook(touch_ges)
                table.insert(ges_evs, Event:new("Gesture", self.gesture_detector:adjustGesCoordinate(touch_ges)))
            end
            return ges_evs
        end
    end
end

--- Accelerometer, in a platform-agnostic, custom format (EV_MSC:MSC_GYRO).
--- (Translation should be done via registerEventAdjustHook in Device implementations).
--- This needs to be called *via handleGyroEv* in a handleMiscEv implementation (c.f., Kobo, Kindle or PocketBook).
function Input:handleMiscGyroEv(ev)
    local rotation
    if ev.value == C.DEVICE_ROTATED_UPRIGHT then
        -- i.e., UR
        rotation = framebuffer.DEVICE_ROTATED_UPRIGHT
    elseif ev.value == C.DEVICE_ROTATED_CLOCKWISE then
        -- i.e., CW
        rotation = framebuffer.DEVICE_ROTATED_CLOCKWISE
    elseif ev.value == C.DEVICE_ROTATED_UPSIDE_DOWN then
        -- i.e., UD
        rotation = framebuffer.DEVICE_ROTATED_UPSIDE_DOWN
    elseif ev.value == C.DEVICE_ROTATED_COUNTER_CLOCKWISE then
        -- i.e., CCW
        rotation = framebuffer.DEVICE_ROTATED_COUNTER_CLOCKWISE
    else
        -- Discard FRONT/BACK
        return
    end

    local old_rotation = self.device.screen:getRotationMode()
    if self.device:isGSensorLocked() then
        local matching_orientation = bit.band(rotation, 1) == bit.band(old_rotation, 1)
        if rotation and rotation ~= old_rotation and matching_orientation then
            -- Cheaper than a full SetRotationMode event, as we don't need to re-layout anything.
            self.device.screen:setRotationMode(rotation)
            UIManager:onRotation()
        end
    else
        if rotation and rotation ~= old_rotation then
            -- NOTE: We do *NOT* send a broadcast manually, and instead rely on the main loop's sendEvent:
            --       this ensures that only widgets that actually know how to handle a rotation will do so ;).
            return Event:new("SetRotationMode", rotation)
        end
    end
end

--- Allow toggling the accelerometer at runtime.
function Input:toggleGyroEvents(toggle)
    if toggle == true then
        -- Honor Gyro events
        if self.handleGyroEv ~= self.handleMiscGyroEv then
            self.handleGyroEv = self.handleMiscGyroEv
        end
    elseif toggle == false then
        -- Ignore Gyro events
        if self.handleGyroEv == self.handleMiscGyroEv then
            self.handleGyroEv = self.voidEv
        end
    else
        -- Toggle it
        if self.handleGyroEv == self.handleMiscGyroEv then
            self.handleGyroEv = self.voidEv
        else
            self.handleGyroEv = self.handleMiscGyroEv
        end
    end
end

-- helpers for touch event data management:

function Input:initMtSlot(slot)
    if not self.ev_slots[slot] then
        self.ev_slots[slot] = {
            slot = slot
        }
    end
end

function Input:getMtSlot(slot)
    return self.ev_slots[slot]
end

function Input:getCurrentMtSlot()
    return self.ev_slots[self.cur_slot]
end

function Input:setMtSlot(slot, key, val)
    self.ev_slots[slot][key] = val
end

function Input:setCurrentMtSlot(key, val)
    self.ev_slots[self.cur_slot][key] = val
end

-- Same as above, but ensures the current slot actually has a live ref first
function Input:setCurrentMtSlotChecked(key, val)
    if not self.active_slots[self.cur_slot] then
        self:addSlot(self.cur_slot)
    end

    self.ev_slots[self.cur_slot][key] = val
end

function Input:getCurrentMtSlotData(key)
    local slot = self:getCurrentMtSlot()
    if slot then
        return slot[key]
    end

    return nil
end

function Input:newFrame()
    -- Array of references to the data for each slot seen in this input frame
    -- (Points to self.ev_slots, c.f., getMtSlot)
    self.MTSlots = {}
    -- Simple hash to keep track of which references we've inserted into self.MTSlots (keys are slot numbers)
    self.active_slots = {}
end

function Input:addSlot(value)
    self:initMtSlot(value)
    table.insert(self.MTSlots, self:getMtSlot(value))
    self.active_slots[value] = true
    self.cur_slot = value
end

function Input:setupSlotData(value)
    if not self.active_slots[value] then
        self:addSlot(value)
    else
        -- We've already seen that slot in this frame, don't insert a duplicate reference!
        -- NOTE: May already be set to the correct value if the driver repeats ABS_MT_SLOT (e.g., our android/PB translation layers; or ABS_MT_TRACKING_ID for snow_protocol).
        self.cur_slot = value
    end
end

function Input:isEvKeyPress(ev)
    return ev.value == KEY_PRESS
end

function Input:isEvKeyRepeat(ev)
    return ev.value == KEY_REPEAT
end

function Input:isEvKeyRelease(ev)
    return ev.value == KEY_RELEASE
end


--- Main event handling.
-- `now` corresponds to UIManager:getTime() (an fts time), and it's just been updated by UIManager.
-- `deadline` (an fts time) is the absolute deadline imposed by UIManager:handleInput() (a.k.a., our main event loop ^^):
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
        if self.timer_callbacks[1] then
            -- If we have timers set, we need to honor them once we're done draining the input events.
            while self.timer_callbacks[1] do
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
                    now = now or time.now()
                    if poll_deadline > now then
                        -- Deadline hasn't been blown yet, honor it.
                        poll_timeout = poll_deadline - now
                    else
                        -- We've already blown the deadline: make select return immediately (most likely straight to timeout).
                        -- NOTE: With the timerfd backend, this is sometimes a tad optimistic,
                        --       as we may in fact retry for a few iterations while waiting for the timerfd to actually expire.
                        poll_timeout = 0
                    end
                end

                local timerfd
                local sec, usec = time.split_s_us(poll_timeout)
                ok, ev, timerfd = self.input.waitForEvent(sec, usec)
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
                        elseif time.now() >= self.timer_callbacks[1].deadline then
                            -- But if it was a task deadline instead, we to have to check the timer's against the current time,
                            -- to double-check whether we blew it or not.
                            consume_callback = true
                        end
                    end

                    if consume_callback then
                        local touch_ges
                        local timer_idx = 1
                        if timerfd then
                            -- If there's a deadline collision, make sure we call the callback that matches the timerfd returned.
                            -- We'll handle the next one on the next iteration, as an expired timerfd will ensure
                            -- that select will return immediately.
                            for i, item in ipairs(self.timer_callbacks) do
                                if item.timerfd == timerfd then
                                    -- In the vast majority of cases, we should find our match on the first entry ;).
                                    timer_idx = i
                                    touch_ges = item.callback()
                                    break
                                end
                            end
                        else
                            -- If there's a deadline collision, we'll just handle the next one on the next iteration,
                            -- because the blown deadline means we'll have asked waitForEvent to return immediately.
                            touch_ges = self.timer_callbacks[1].callback()
                        end

                        -- Cleanup after the timer callback.
                        -- GestureDetector has guards in place to avoid double frees in case the callback itself
                        -- affected the timerfd or timer_callbacks list (e.g., by dropping a contact).
                        if timerfd then
                            self.input.clearTimer(timerfd)
                        end
                        table.remove(self.timer_callbacks, timer_idx)

                        if touch_ges then
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
                now = now or time.now()
                if deadline > now then
                    -- Deadline hasn't been blown yet, honor it.
                    poll_timeout = deadline - now
                else
                    -- Deadline has been blown: make select return immediately.
                    poll_timeout = 0
                end
            end

            local sec, usec = time.split_s_us(poll_timeout)
            ok, ev = self.input.waitForEvent(sec, usec)
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
                --       and we can't conditionally prevent evaluation of function arguments,
                --       so, just hide the whole thing behind a branch ;).
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
                elseif event.type == C.EV_REP then
                    logger.dbg(string.format(
                        "input event => type: %d (%s), code: %d (%s), value: %s, time: %d.%06d",
                        event.type, linux_evdev_type_map[event.type], event.code, linux_evdev_rep_code_map[event.code], event.value,
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
            elseif event.type == C.EV_ABS or event.type == C.EV_SYN then
                local handled_evs = self:handleTouchEv(event)
                -- handleTouchEv only returns an array of Events once it gets a SYN_REPORT,
                -- so more often than not, we just get a nil here ;).
                if handled_evs then
                    for _, handled_ev in ipairs(handled_evs) do
                        table.insert(handled, handled_ev)
                    end
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
                local handled_ev = self:handleGenericEv(event)
                if handled_ev then
                    table.insert(handled, handled_ev)
                end
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

-- Allow toggling the handling of most every kind of input, except for power management related events.
function Input:inhibitInput(toggle)
    if toggle then
        -- Only handle power management events
        if not self._key_ev_handler then
            logger.info("Inhibiting user input")
            self._key_ev_handler = self.handleKeyBoardEv
            self.handleKeyBoardEv = self.handlePowerManagementOnlyEv
        end
        -- And send everything else to the void
        if not self._abs_ev_handler then
            self._abs_ev_handler = self.handleTouchEv
            self.handleTouchEv = self.voidEv
        end
        -- NOTE: We leave handleMiscEv alone, as some platforms make extensive use of EV_MSC for critical low-level stuff:
        --       e.g., on PocketBook, it is used to handle InkView task management events (i.e., PM);
        --       and on Android, for the critical purpose of forwarding Android events to Lua-land.
        --       The only thing we might want to skip in there are gyro events anyway, which we'll handle separately.
        if not self._gyro_ev_handler then
            self._gyro_ev_handler = self.handleGyroEv
            self.handleGyroEv = self.voidEv
        end
        if not self._sdl_ev_handler then
            self._sdl_ev_handler = self.handleSdlEv
            -- This is mainly used for non-input events, so we mostly want to leave it alone (#10427).
            -- The only exception being mwheel handling, which we *do* want to inhibit.
            self.handleSdlEv = function(this, ev)
                local SDL_MOUSEWHEEL = 1027
                if ev.code == SDL_MOUSEWHEEL then
                    return
                else
                    return this:_sdl_ev_handler(ev)
                end
            end
        end
        if not self._generic_ev_handler then
            self._generic_ev_handler = self.handleGenericEv
            self.handleGenericEv = self.voidEv
        end

        -- Reset gesture detection state to a blank slate, to avoid bogus gesture detection on restore.
        self:resetState()
    else
        -- Restore event handlers, if any
        if self._key_ev_handler then
            logger.info("Restoring user input handling")
            self.handleKeyBoardEv = self._key_ev_handler
            self._key_ev_handler = nil
        end
        if self._abs_ev_handler then
            self.handleTouchEv = self._abs_ev_handler
            self._abs_ev_handler = nil
        end
        if self._gyro_ev_handler then
            self.handleGyroEv = self._gyro_ev_handler
            self._gyro_ev_handler = nil
        end
        if self._sdl_ev_handler then
            self.handleSdlEv = self._sdl_ev_handler
            self._sdl_ev_handler = nil
        end
        if self._generic_ev_handler then
            self.handleGenericEv = self._generic_ev_handler
            self._generic_ev_handler = nil
        end
    end
end

--[[--
Request all input events to be ignored for some duration.

@param set_or_seconds either `true`, in which case a platform-specific delay is chosen, or a duration in seconds (***int***).
]]
function Input:inhibitInputUntil(set_or_seconds)
    UIManager:unschedule(self._inhibitInputUntil_func)
    if not set_or_seconds then -- remove any previously set
        self:inhibitInput(false)
        return
    end
    local delay_s
    if set_or_seconds == true then
        -- Use an adequate delay to account for device refresh duration
        -- so any events happening in this delay (ie. before a widget
        -- is really painted on screen) are discarded.
        if self.device:hasEinkScreen() then
            -- A screen refresh can take a few 100ms,
            -- sometimes > 500ms on some devices/temperatures.
            -- So, block for 400ms (to have it displayed) + 400ms
            -- for user reaction to it
            delay_s = 0.8
        else
            -- On non-eInk screen, display is usually instantaneous
            delay_s = 0.4
        end
    else -- we expect a number
        delay_s = set_or_seconds
    end
    UIManager:scheduleIn(delay_s, self._inhibitInputUntil_func)
    self:inhibitInput(true)
end

return Input
