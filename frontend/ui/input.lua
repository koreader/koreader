local Device = require("ui/device")
local GestureDetector = require("ui/gesturedetector")
local Event = require("ui/event")
local TimeVal = require("ui/timeval")
local Screen = require("ui/screen")
local Math = require("optmath")
local DEBUG = require("dbg")
local _ = require("gettext")
local util = require("ffi/util")

-- constants from <linux/input.h>
local EV_SYN = 0
local EV_KEY = 1
local EV_ABS = 3

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
an interface for key presses
]]

local Key = {}

function Key:new(key, modifiers)
    local o = { key = key, modifiers = modifiers }

    -- we're a hash map, too
    o[key] = true
    for mod, pressed in pairs(modifiers) do
        if pressed then
            o[mod] = true
        end
    end

    setmetatable(o, self)
    self.__index = self
    return o
end

function Key:__tostring()
    return table.concat(self:getSequence(), "-")
end

--[[
get a sequence that can be matched against later

use this to let the user press a sequence and then
store this as configuration data (configurable
shortcuts)
]]
function Key:getSequence()
    local seq = {}
    for mod, pressed in pairs(self.modifiers) do
        if pressed then
            table.insert(seq, mod)
        end
    end
    table.insert(seq, self.key)
end

--[[
this will match a key against a sequence

the sequence should be a table of key names that
must be pressed together to match.
if an entry in this table is itself a table, at
least one key in this table must match.

E.g.:

Key:match({ "Alt", "K" }) -- match Alt-K
Key:match({ "Alt", { "K", "L" }}) -- match Alt-K _or_ Alt-L
]]
function Key:match(sequence)
    local mod_keys = {} -- a hash table for checked modifiers
    for _, key in ipairs(sequence) do
        if type(key) == "table" then
            local found = false
            for _, variant in ipairs(key) do
                if self[variant] then
                    found = true
                    break
                end
            end
            if not found then
                -- one of the needed keys is not pressed
                return false
            end
        elseif not self[key] then
            -- needed key not pressed
            return false
        elseif self.modifiers[key] ~= nil then
            -- checked key is a modifier key
            mod_keys[key] = true
        end
    end

    for mod, pressed in pairs(self.modifiers) do
        if pressed and not mod_keys[mod] then
            -- additional modifier keys are pressed, don't match
            return false
        end
    end

    return true
end

--[[
an interface to get input events
]]
local Input = {
    event_map = {},
    modifiers = {},
    rotation_map = {
        [0] = {},
        [1] = { Up = "Right", Right = "Down", Down = "Left", Left = "Up" },
        [2] = { Up = "Down", Right = "Left", Down = "Up", Left = "Right" },
        [3] = { Up = "Left", Right = "Up", Down = "Right", Left = "Down" }
    },
    timer_callbacks = {},
    disable_double_tap = DGESDETECT_DISABLE_DOUBLE_TAP,
}

function Input:initKeyMap()
    self.event_map = {
        [2]  = "1", [3]  = "2", [4]  = "3", [5]  = "4", [6]  = "5", [7]  = "6", [8]  = "7", [9]  = "8", [10] = "9", [11] = "0",
        [16] = "Q", [17] = "W", [18] = "E", [19] = "R", [20] = "T", [21] = "Y", [22] = "U", [23] = "I", [24] = "O", [25] = "P",
        [30] = "A", [31] = "S", [32] = "D", [33] = "F", [34] = "G", [35] = "H", [36] = "J", [37] = "K", [38] = "L", [14] = "Del",
        [44] = "Z", [45] = "X", [46] = "C", [47] = "V", [48] = "B", [49] = "N", [50] = "M", [52] = ".", [53] = "/", -- only KDX

        [28] = "Enter",
        [29] = "ScreenKB", -- K[4]
        [42] = "Shift",
        [56] = "Alt",
        [57] = " ",
        [90] = "AA", -- KDX
        [91] = "Back", -- KDX
        [92] = "Press", -- KDX
        [94] = "Sym", -- KDX
        [98] = "Home", -- KDX
        [102] = "Home", -- K[3] & k[4]
        [104] = "LPgBack", -- K[3] only
        [103] = "Up", -- K[3] & k[4]
        [105] = "Left",
        [106] = "Right",
        [108] = "Down", -- K[3] & k[4]
        [109] = "RPgBack",
        [114] = "VMinus",
        [115] = "VPlus",
        [122] = "Up", -- KDX
        [123] = "Down", -- KDX
        [124] = "RPgFwd", -- KDX
        [126] = "Sym", -- K[3]
        [139] = "Menu",
        [158] = "Back", -- K[3] & K[4]
        [190] = "AA", -- K[3]
        [191] = "RPgFwd", -- K[3] & k[4]
        [193] = "LPgFwd", -- K[3] only
        [194] = "Press", -- K[3] & k[4]
    }
    self.sdl_event_map = {
        [10] = "1", [11] = "2", [12] = "3", [13] = "4", [14] = "5", [15] = "6", [16] = "7", [17] = "8", [18] = "9", [19] = "0",
        [24] = "Q", [25] = "W", [26] = "E", [27] = "R", [28] = "T", [29] = "Y", [30] = "U", [31] = "I", [32] = "O", [33] = "P",
        [38] = "A", [39] = "S", [40] = "D", [41] = "F", [42] = "G", [43] = "H", [44] = "J", [45] = "K", [46] = "L",
        [52] = "Z", [53] = "X", [54] = "C", [55] = "V", [56] = "B", [57] = "N", [58] = "M",

        [22] = "Back", -- Backspace
        [36] = "Enter", -- Enter
        [50] = "Shift", -- left shift
        [60] = ".",
        [61] = "/",
        [62] = "Sym", -- right shift key
        [64] = "Alt", -- left alt
        [65] = " ", -- Spacebar
        [67] = "Menu", -- F[1]
        [72] = "LPgBack", -- F[6]
        [73] = "LPgFwd", -- F[7]
        [95] = "VPlus", -- F[11]
        [96] = "VMinus", -- F[12]
        [105] = "AA", -- right alt key
        [110] = "Home", -- Home
        [111] = "Up", -- arrow up
        [112] = "RPgBack", -- normal PageUp
        [113] = "Left", -- arrow left
        [114] = "Right", -- arrow right
        [115] = "Press", -- End (above arrows)
        [116] = "Down", -- arrow down
        [117] = "RPgFwd", -- normal PageDown
        [119] = "Del", -- Delete
    }
    self.modifiers = {
        Alt = false,
        Shift = false
    }
    -- these groups are just helpers:
    self.group = {
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
        }
    }
end

function Input:initTouchState()
    self.cur_slot = 0
    self.MTSlots = {}
    self.ev_slots = {
        [0] = {
            slot = 0,
        }
    }
end

function Input:init()
    if Device:hasKeyboard() then
        self:initKeyMap()
    end
    if Device:isTouchDevice() then
        self:initTouchState()
    end
    -- set up fake event map
    self.event_map[10000] = "IntoSS" -- go into screen saver
    self.event_map[10001] = "OutOfSS" -- go out of screen saver
    self.event_map[10020] = "Charging"
    self.event_map[10021] = "NotCharging"

    if util.isEmulated() then
        self:initKeyMap()
        os.remove("/tmp/emu_event")
        os.execute("mkfifo /tmp/emu_event")
        input.open("/tmp/emu_event")
        -- SDL key codes
        self.event_map = self.sdl_event_map
    else
        local dev_mod = Device:getModel()
        if not Device:isKobo() then
            input.open("fake_events")
        end
        if dev_mod == "KindlePaperWhite" then
            DEBUG("Auto-detected Kindle PaperWhite")
            Device:setTouchInputDev("/dev/input/event0")
            input.open("/dev/input/event0")
        elseif dev_mod == "KindlePaperWhite2" then
            DEBUG("Auto-detected Kindle PaperWhite")
            Device:setTouchInputDev("/dev/input/event1")
            input.open("/dev/input/event1")
        elseif dev_mod == "KindleTouch" then
            -- event0 in KindleTouch is "WM8962 Beep Generator" (useless)
            -- event1 in KindleTouch is "imx-yoshi Headset" (useless)
            Device:setTouchInputDev("/dev/input/event3")
            input.open("/dev/input/event2") -- Home button
            input.open("/dev/input/event3") -- touchscreen
            -- KT does have one key!
            self.event_map[102] = "Home"
            -- update event hook
            function Input:eventAdjustHook(ev)
                if ev.type == EV_ABS then
                    --@TODO handle coordinates properly after
                    --screen rotate.    (houqp)
                    if ev.code == ABS_MT_POSITION_X then
                        ev.value = Math.round(ev.value * (600/4095))
                    elseif ev.code == ABS_MT_POSITION_Y then
                        ev.value = Math.round(ev.value * (800/4095))
                    end
                end
                return ev
            end
            DEBUG("Auto-detected Kindle Touch")
        elseif Device:isKobo() then
            local firm_rev = Device:getFirmVer()
            input.open("/dev/input/event1")
            Device:setTouchInputDev("/dev/input/event1")
            input.open("/dev/input/event0") -- Light button and sleep slider
            DEBUG("Auto-detected Kobo")
            DEBUG("Device model=", dev_mod)
            DEBUG("Firmware revision", firm_rev)
            DEBUG("Screen width =", Screen:getWidth())
            DEBUG("Screen height =", Screen:getHeight())
            self:adjustKoboEventMap()
            if dev_mod ~= 'Kobo_trilogy' then
                function Input:eventAdjustHook(ev)
                    if ev.type == EV_ABS then
                        if ev.code == ABS_X then
                            ev.code = ABS_Y
                        elseif ev.code == ABS_Y then
                            ev.code = ABS_X
                            -- We always have to substract from the physical x,
                            -- regardless of the orientation
                            if (Screen:getWidth()<Screen:getHeight()) then
                                ev.value = Screen:getWidth() - ev.value
                            else
                                ev.value = Screen:getHeight() - ev.value
                            end
                        end
                        -- same thing for multitouch events (phoenix)
                        if ev.code == ABS_MT_POSITION_X then
                            ev.code = ABS_MT_POSITION_Y
                        elseif ev.code == ABS_MT_POSITION_Y then
                            ev.code = ABS_MT_POSITION_X
                            -- We always have to substract from the physical x,
                            -- regardless of the orientation
                            if (Screen:getWidth()<Screen:getHeight()) then
                                ev.value = Screen:getWidth() - ev.value
                            else
                                ev.value = Screen:getHeight() - ev.value
                            end
                        end
                    end
                    return ev
                end
            else -- kobo touch (trilogy)
                -- FIXME some touch models should be treated as the other models,
                -- depending on board revision
                function Input:eventAdjustHook(ev)
                    if ev.code == ABS_X then
                        -- We always have to substract from the physical x,
                        -- regardless of the orientation
                        if (Screen:getWidth()<Screen:getHeight()) then
                            ev.value = Screen:getWidth() - ev.value
                        else
                            ev.value = Screen:getHeight() - ev.value
                        end
                    end
                    return ev
                end
            end
        elseif dev_mod == "Kindle4" then
            DEBUG("Auto-detected Kindle 4")
            input.open("/dev/input/event1")
            self:adjustKindle4EventMap()
        elseif dev_mod == "Kindle3" then
            DEBUG("Auto-detected Kindle 3")
            input.open("/dev/input/event1")
            input.open("/dev/input/event2")
        elseif dev_mod == "KindleDXG" then
            DEBUG("Auto-detected Kindle DXG")
            input.open("/dev/input/event1")
        elseif dev_mod == "Kindle2" then
            DEBUG("Auto-detected Kindle 2")
            input.open("/dev/input/event1")
        elseif util.isAndroid() then
            DEBUG("Auto-detected Android")
        else
            DEBUG("Not supported device model!")
        end
    end

    if Device:getModel() ~= 'Kobo_phoenix' then
        function Input:handleTouchEv(ev)
            return Input:handleTypeBTouchEv(ev)
        end
    else
        function Input:handleTouchEv(ev)
            return Input:handlePhoenixTouchEv(ev)
        end
    end
end

--[[
different device models shoudl overload this method if
necessary to make event compatible to KPV.
--]]
function Input:eventAdjustHook(ev)
    -- do nothing by default
    return ev
end

function Input:adjustKindle4EventMap()
    self.event_map[193] = "LPgBack"
    self.event_map[104] = "LPgFwd"
end

function Input:adjustKoboEventMap()
    self.event_map[59] = "Power_SleepCover"
    self.event_map[90] = "Light"
    self.event_map[116] = "Power"
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
    if self.rotation_map[Screen:getRotationMode()][keycode] then
        keycode = self.rotation_map[Screen:getRotationMode()][keycode]
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
function Input:handleTypeBTouchEv(ev)
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
            local touch_ges = GestureDetector:feedEvent(self.MTSlots)
            self.MTSlots = {}
            if touch_ges then
                return Event:new("Gesture",
                    GestureDetector:adjustGesCoordinate(touch_ges)
                )
            end
        end
    end
end

function Input:handlePhoenixTouchEv(ev)
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
            local touch_ges = GestureDetector:feedEvent(self.MTSlots)
            self.MTSlots = {}
            if touch_ges then
                return Event:new("Gesture",
                    GestureDetector:adjustGesCoordinate(touch_ges)
                )
            end
        end
    end
end

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
                            Input.timer_callbacks = {}
                            return Event:new("Gesture",
                                GestureDetector:adjustGesCoordinate(touch_ges)
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
        if ev == "Waiting for input failed: timeout\n" then
            -- don't report an error on timeout
            ev = nil
            break
        elseif ev == "application forced to quit" then
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
        ev = self:eventAdjustHook(ev)
        if ev.type == EV_KEY then
            return self:handleKeyBoardEv(ev)
        elseif ev.type == EV_ABS or ev.type == EV_SYN then
            return self:handleTouchEv(ev)
        else
            -- some other kind of event that we do not know yet
            return Event:new("GenericInput", ev)
        end
    elseif not ok and ev then
        return Event:new("InputError", ev)
    end
end

--[[
helper function for formatting sequence definitions for output
]]
function Input:sequenceToString(sequence)
    local modifiers = {}
    local keystring = {"",""} -- first entries reserved for modifier specification
    for _, key in ipairs(sequence) do
        if type(key) == "table" then
            local alternatives = {}
            for _, alternative in ipairs(key) do
                table.insert(alternatives, alternative)
            end
            table.insert(keystring, "{")
            table.insert(keystring, table.concat(alternatives, "|"))
            table.insert(keystring, "}")
        elseif self.modifiers[key] ~= nil then
            table.insert(modifiers, key)
        else
            table.insert(keystring, key)
        end
    end
    if #modifiers then
        keystring[1] = table.concat(modifiers, "-")
        keystring[2] = "-"
    end
    return table.concat(keystring)
end

-- initialize the GestureDectector
-- so it can modify our (Input) state
GestureDetector.input = Input

return Input
