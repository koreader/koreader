local Generic = require("device/generic/device")
local util = require("ffi/util")
local Event = require("ui/event")
local DEBUG = require("dbg")

local function yes() return true end
local function no() return false end  -- luacheck: ignore

local function kindleEnableWifi(toggle)
    local haslipc, lipc = pcall(require, "liblipclua")
    local lipc_handle = nil
    if haslipc and lipc then
        lipc_handle = lipc.init("com.github.koreader.networkmgr")
    end
    if lipc_handle then
        lipc_handle:set_int_property("com.lab126.cmd", "wirelessEnable", toggle)
        lipc_handle:close()
    end
end


local Kindle = Generic:new{
    model = "Kindle",
    isKindle = yes,
}

function Kindle:initNetworkManager(NetworkMgr)
    NetworkMgr.turnOnWifi = function()
        kindleEnableWifi(1)
    end

    NetworkMgr.turnOffWifi = function()
        kindleEnableWifi(0)
    end
end

function Kindle:usbPlugIn()
    if self.charging_mode == false and self.screen_saver_mode == false then
        self.screen:saveCurrentBB()
        -- On FW >= 5.7.2, we sigstop awesome, but we need it to show stuff...
        if os.getenv("AWESOME_STOPPED") == "yes" then
            os.execute("killall -cont awesome")
        end
    end
    self.charging_mode = true
end

function Kindle:intoScreenSaver()
    if self.charging_mode == false and self.screen_saver_mode == false then
        self.screen:saveCurrentBB()
        self.screen_saver_mode = true
        -- On FW >= 5.7.2, we sigstop awesome, but we need it to show stuff...
        if os.getenv("AWESOME_STOPPED") == "yes" then
            os.execute("killall -cont awesome")
        end
    end
    require("ui/uimanager"):broadcastEvent(Event:new("FlushSettings"))
end

function Kindle:outofScreenSaver()
    if self.screen_saver_mode == true and self.charging_mode == false then
        -- On FW >= 5.7.2, put awesome to sleep again...
        if os.getenv("AWESOME_STOPPED") == "yes" then
            os.execute("killall -stop awesome")
        end
        -- wait for native system update screen before we recover saved
        -- Blitbuffer.
        util.usleep(1500000)
        self.screen:restoreFromSavedBB()
        self:resume()
        if self:needsScreenRefreshAfterResume() then
            self.screen:refreshFull()
        end
        self.powerd:refreshCapacity()
    end
    self.screen_saver_mode = false
end

function Kindle:usbPlugOut()
    if self.charging_mode == true and self.screen_saver_mode == false then
        -- On FW >= 5.7.2, put awesome to sleep again...
        if os.getenv("AWESOME_STOPPED") == "yes" then
            os.execute("killall -stop awesome")
        end
        -- Same as when going out of screensaver, wait for the native system
        util.usleep(1500000)
        self.screen:restoreFromSavedBB()
        self.screen:refreshFull()
        self.powerd:refreshCapacity()
    end

    --@TODO signal filemanager for file changes  13.06 2012 (houqp)
    self.charging_mode = false
end


local Kindle2 = Kindle:new{
    model = "Kindle2",
    hasKeyboard = yes,
    hasKeys = yes,
    hasDPad = yes,
}

local KindleDXG = Kindle:new{
    model = "KindleDXG",
    hasKeyboard = yes,
    hasKeys = yes,
    hasDPad = yes,
}

local Kindle3 = Kindle:new{
    model = "Kindle3",
    hasKeyboard = yes,
    hasKeys = yes,
    hasDPad = yes,
}

local Kindle4 = Kindle:new{
    model = "Kindle4",
    hasKeys = yes,
    hasDPad = yes,
}

local KindleTouch = Kindle:new{
    model = "KindleTouch",
    isTouchDevice = yes,
    hasKeys = yes,
    touch_dev = "/dev/input/event3",
}

local KindlePaperWhite = Kindle:new{
    model = "KindlePaperWhite",
    isTouchDevice = yes,
    hasFrontlight = yes,
    display_dpi = 212,
    touch_dev = "/dev/input/event0",
}

local KindlePaperWhite2 = Kindle:new{
    model = "KindlePaperWhite2",
    isTouchDevice = yes,
    hasFrontlight = yes,
    display_dpi = 212,
    touch_dev = "/dev/input/event1",
}

local KindleBasic = Kindle:new{
    model = "KindleBasic",
    isTouchDevice = yes,
    touch_dev = "/dev/input/event1",
}

local KindleVoyage = Kindle:new{
    model = "KindleVoyage",
    isTouchDevice = yes,
    hasFrontlight = yes,
    hasKeys = yes,
    display_dpi = 300,
    touch_dev = "/dev/input/event1",
}

local KindlePaperWhite3 = Kindle:new{
    model = "KindlePaperWhite3",
    isTouchDevice = yes,
    hasFrontlight = yes,
    display_dpi = 300,
    touch_dev = "/dev/input/event1",
}

local KindleOasis = Kindle:new{
    model = "KindleOasis",
    isTouchDevice = yes,
    hasFrontlight = yes,
    hasKeys = yes,
    display_dpi = 300,
    --[[
    -- NOTE: Points to event3 on WiFi devices, event4 on 3G devices...
    --       3G devices apparently have an extra SX9500 Proximity/Capacitive controller for mysterious purposes...
    --       This evidently screws with the ordering, so, use the udev by-path path instead to avoid hackier workarounds.
    --       cf. #2181
    --]]
    touch_dev = "/dev/input/by-path/platform-imx-i2c.1-event",
}

local KindleBasic2 = Kindle:new{
    model = "KindleBasic2",
    isTouchDevice = yes,
    touch_dev = "/dev/input/event0",
}

function Kindle2:init()
    self.screen = require("ffi/framebuffer_einkfb"):new{device = self, debug = DEBUG}
    self.powerd = require("device/kindle/powerd"):new{
        device = self,
        is_charging_file = "/sys/devices/platform/charger/charging",
    }
    self.input = require("device/input"):new{
        device = self,
        event_map = require("device/kindle/event_map_keyboard"),
    }
    self.input.open("/dev/input/event0")
    self.input.open("/dev/input/event1")
    Kindle.init(self)
end

function KindleDXG:init()
    self.screen = require("ffi/framebuffer_einkfb"):new{device = self, debug = DEBUG}
    self.powerd = require("device/kindle/powerd"):new{
        device = self,
        is_charging_file = "/sys/devices/platform/charger/charging",
    }
    self.input = require("device/input"):new{
        device = self,
        event_map = require("device/kindle/event_map_keyboard"),
    }
    self.keyboard_layout = require("device/kindle/keyboard_layout")
    self.input.open("/dev/input/event0")
    self.input.open("/dev/input/event1")
    Kindle.init(self)
end

function Kindle3:init()
    self.screen = require("ffi/framebuffer_einkfb"):new{device = self, debug = DEBUG}
    self.powerd = require("device/kindle/powerd"):new{
        device = self,
        batt_capacity_file = "/sys/devices/system/luigi_battery/luigi_battery0/battery_capacity",
        is_charging_file = "/sys/devices/platform/fsl-usb2-udc/charging",
    }
    self.input = require("device/input"):new{
        device = self,
        event_map = require("device/kindle/event_map_keyboard"),
    }
    self.keyboard_layout = require("device/kindle/keyboard_layout")
    self.input.open("/dev/input/event0")
    self.input.open("/dev/input/event1")
    Kindle.init(self)
end

function Kindle4:init()
    self.screen = require("ffi/framebuffer_einkfb"):new{device = self, debug = DEBUG}
    self.powerd = require("device/kindle/powerd"):new{
        device = self,
        batt_capacity_file = "/sys/devices/system/yoshi_battery/yoshi_battery0/battery_capacity",
        is_charging_file = "/sys/devices/platform/fsl-usb2-udc/charging",
    }
    self.input = require("device/input"):new{
        device = self,
        event_map = require("device/kindle/event_map_kindle4"),
    }
    self.input.open("/dev/input/event0")
    self.input.open("/dev/input/event1")
    Kindle.init(self)
end

-- luacheck: push
-- luacheck: ignore
local ABS_MT_POSITION_X = 53
local ABS_MT_POSITION_Y = 54
-- luacheck: pop
function KindleTouch:init()
    self.screen = require("ffi/framebuffer_mxcfb"):new{device = self, debug = DEBUG}
    self.powerd = require("device/kindle/powerd"):new{
        device = self,
        batt_capacity_file = "/sys/devices/system/yoshi_battery/yoshi_battery0/battery_capacity",
        is_charging_file = "/sys/devices/platform/fsl-usb2-udc/charging",
    }
    self.input = require("device/input"):new{
        device = self,
        -- Kindle Touch has a single button
        event_map = { [102] = "Home" },
    }

    -- Kindle Touch needs event modification for proper coordinates
    self.input:registerEventAdjustHook(self.input.adjustTouchScale, {x=600/4095, y=800/4095})

    -- event0 in KindleTouch is "WM8962 Beep Generator" (useless)
    -- event1 in KindleTouch is "imx-yoshi Headset" (useless)
    self.input.open("/dev/input/event2") -- Home button
    self.input.open(self.touch_dev) -- touchscreen
    self.input.open("fake_events")
    Kindle.init(self)
end

function KindlePaperWhite:init()
    self.screen = require("ffi/framebuffer_mxcfb"):new{device = self, debug = DEBUG}
    self.powerd = require("device/kindle/powerd"):new{
        device = self,
        fl_intensity_file = "/sys/devices/system/fl_tps6116x/fl_tps6116x0/fl_intensity",
        batt_capacity_file = "/sys/devices/system/yoshi_battery/yoshi_battery0/battery_capacity",
        is_charging_file = "/sys/devices/platform/aplite_charger.0/charging",
    }

    Kindle.init(self)

    self.input.open(self.touch_dev)
    self.input.open("fake_events")
end

function KindlePaperWhite2:init()
    self.screen = require("ffi/framebuffer_mxcfb"):new{device = self, debug = DEBUG}
    self.powerd = require("device/kindle/powerd"):new{
        device = self,
        fl_intensity_file = "/sys/class/backlight/max77696-bl/brightness",
        batt_capacity_file = "/sys/devices/system/wario_battery/wario_battery0/battery_capacity",
        is_charging_file = "/sys/devices/system/wario_charger/wario_charger0/charging",
    }

    Kindle.init(self)

    self.input.open(self.touch_dev)
    self.input.open("fake_events")
end

function KindleBasic:init()
    self.screen = require("ffi/framebuffer_mxcfb"):new{device = self, debug = DEBUG}
    self.powerd = require("device/kindle/powerd"):new{
        device = self,
        batt_capacity_file = "/sys/devices/system/wario_battery/wario_battery0/battery_capacity",
        is_charging_file = "/sys/devices/system/wario_charger/wario_charger0/charging",
    }

    Kindle.init(self)

    self.input.open(self.touch_dev)
    self.input.open("fake_events")
end

function KindleVoyage:init()
    self.screen = require("ffi/framebuffer_mxcfb"):new{device = self, debug = DEBUG}
    self.powerd = require("device/kindle/powerd"):new{
        device = self,
        fl_intensity_file = "/sys/class/backlight/max77696-bl/brightness",
        batt_capacity_file = "/sys/devices/system/wario_battery/wario_battery0/battery_capacity",
        is_charging_file = "/sys/devices/system/wario_charger/wario_charger0/charging",
    }
    self.input = require("device/input"):new{
        device = self,
        event_map = {
            [104] = "LPgBack",
            [109] = "LPgFwd",
        },
    }
    -- touch gestures fall into these cold spots defined by (x, y, r)
    -- will be rewritten to 'none' ges thus being ignored
    -- x, y is the absolute position disregard of screen mode, r is spot radius
    self.cold_spots = {
        {
            x = 1080 + 50, y = 485, r = 80
        },
        {
            x = 1080 + 70, y = 910, r = 120
        },
        {
            x = -50, y = 485, r = 80
        },
        {
            x = -70, y = 910, r = 120
        },
    }

    self.input:registerGestureAdjustHook(function(_, ges)
        if ges then
            local pos = ges.pos
            for _, spot in ipairs(self.cold_spots) do
                if (spot.x - pos.x) * (spot.x - pos.x) +
                   (spot.y - pos.y) * (spot.y - pos.y) < spot.r * spot.r then
                   ges.ges = "none"
                end
            end
        end
    end)

    Kindle.init(self)

    self.input.open(self.touch_dev)
    self.input.open("/dev/input/event2") -- WhisperTouch
    self.input.open("fake_events")
end

function KindlePaperWhite3:init()
    self.screen = require("ffi/framebuffer_mxcfb"):new{device = self, debug = DEBUG}
    self.powerd = require("device/kindle/powerd"):new{
        device = self,
        fl_intensity_file = "/sys/class/backlight/max77696-bl/brightness",
        batt_capacity_file = "/sys/devices/system/wario_battery/wario_battery0/battery_capacity",
        is_charging_file = "/sys/devices/system/wario_charger/wario_charger0/charging",
    }

    Kindle.init(self)

    self.input.open(self.touch_dev)
    self.input.open("fake_events")
end

function KindleOasis:init()
    self.screen = require("ffi/framebuffer_mxcfb"):new{device = self, debug = DEBUG}
    self.powerd = require("device/kindle/powerd"):new{
        device = self,
        fl_intensity_file = "/sys/class/backlight/max77696-bl/brightness",
        -- NOTE: Points to the embedded battery. The one in the cover is codenamed "soda".
        batt_capacity_file = "/sys/devices/system/wario_battery/wario_battery0/battery_capacity",
        is_charging_file = "/sys/devices/system/wario_charger/wario_charger0/charging",
    }

    self.input = require("device/input"):new{
        device = self,

        event_map = {
            [104] = "RPgFwd",
            [109] = "RPgBack",
        }
    }

    local haslipc, lipc = pcall(require, "liblipclua")
    if haslipc and lipc then
        local lipc_handle = lipc.init("com.github.koreader.screen")
        if lipc_handle then
            local orientation_code = lipc_handle:get_string_property(
                "com.lab126.winmgr", "accelerometer")
            local rotation_mode = 0
            if orientation_code then
                if orientation_code == "V" then
                    rotation_mode = self.screen.ORIENTATION_PORTRAIT
                elseif orientation_code == "R" then
                    rotation_mode = self.screen.ORIENTATION_LANDSCAPE
                elseif orientation_code == "D" then
                    rotation_mode = self.screen.ORIENTATION_PORTRAIT_ROTATED
                elseif orientation_code == "L" then
                    rotation_mode = self.screen.ORIENTATION_LANDSCAPE_ROTATED
                end
            end

            if rotation_mode > 0 then
                self.screen.native_rotation_mode = rotation_mode
                self.screen.cur_rotation_mode = rotation_mode
            end

            lipc_handle:close()
        end
    end

    Kindle.init(self)

    self.input:registerEventAdjustHook(self.input.adjustKindleOasisOrientation)

    self.input.open(self.touch_dev)
    self.input.open("/dev/input/by-path/platform-gpiokey.0-event")

    -- get rotate dev by EV=d
    local std_out = io.popen("cat /proc/bus/input/devices | grep -e 'Handlers\\|EV=' | grep -B1 'EV=d'| grep -o 'event[0-9]'", "r")
    if std_out then
        local rotation_dev = std_out:read()
        std_out:close()
        if rotation_dev then
            self.input.open("/dev/input/"..rotation_dev)
        end
    end

    self.input.open("fake_events")
end

function KindleBasic2:init()
    self.screen = require("ffi/framebuffer_mxcfb"):new{device = self, debug = DEBUG}
    self.powerd = require("device/kindle/powerd"):new{
        device = self,
        batt_capacity_file = "/sys/class/power_supply/bd7181x_bat/capacity",
        is_charging_file = "/sys/class/power_supply/bd7181x_bat/charging",
    }

    Kindle.init(self)

    self.input.open(self.touch_dev)
    self.input.open("fake_events")
end

--[[
Test if a kindle device has Special Offers
--]]
local function isSpecialOffers()
    -- Look at the current blanket modules to see if the SO screensavers are enabled...
    local lipc = require("liblipclua")
    if not lipc then
        DEBUG("could not load liblibclua")
        return false
    end
    local lipc_handle = lipc.init("com.github.koreader.device")
    if not lipc_handle then
        DEBUG("could not get lipc handle")
        return false
    end
    local so = false
    local loaded_blanket_modules = lipc_handle:get_string_property("com.lab126.blanket", "load")
    if string.find(loaded_blanket_modules, "ad_screensaver") then
        so = true
    end
    lipc_handle:close()
    return so
end

function KindleTouch:exit()
    if isSpecialOffers() then
        -- fake a touch event
        if self.touch_dev then
            local width, height = self.screen:getScreenWidth(), self.screen:getScreenHeight()
            require("ffi/input").fakeTapInput(self.touch_dev,
                math.min(width, height)/2,
                math.max(width, height)-30
            )
        end
    end
    Generic.exit(self)
end
KindlePaperWhite.exit = KindleTouch.exit
KindlePaperWhite2.exit = KindleTouch.exit
KindleBasic.exit = KindleTouch.exit
KindleVoyage.exit = KindleTouch.exit
KindlePaperWhite3.exit = KindleTouch.exit
KindleOasis.exit = KindleTouch.exit
KindleBasic2.exit = KindleTouch.exit

function Kindle3:exit()
    -- send double menu key press events to trigger screen refresh
    os.execute("echo 'send 139' > /proc/keypad;echo 'send 139' > /proc/keypad")

    Generic.exit(self)
end

KindleDXG.exit = Kindle3.exit


----------------- device recognition: -------------------

local function Set(list)
    local set = {}
    for _, l in ipairs(list) do set[l] = true end
    return set
end


local kindle_sn_fd = io.open("/proc/usid", "r")
if not kindle_sn_fd then return end
local kindle_sn = kindle_sn_fd:read()
kindle_sn_fd:close()
local kindle_devcode = string.sub(kindle_sn,3,4)
local kindle_devcode_v2 = string.sub(kindle_sn,4,6)

-- NOTE: Update me when new devices come out :)
local k2_set = Set { "02", "03" }
local dx_set = Set { "04", "05" }
local dxg_set = Set { "09" }
local k3_set = Set { "08", "06", "0A" }
local k4_set = Set { "0E", "23" }
local touch_set = Set { "0F", "11", "10", "12" }
local pw_set = Set { "24", "1B", "1D", "1F", "1C", "20" }
local pw2_set = Set { "D4", "5A", "D5", "D6", "D7", "D8", "F2", "17",
                  "60", "F4", "F9", "62", "61", "5F" }
local kt2_set = Set { "C6", "DD" }
local kv_set = Set { "13", "54", "2A", "4F", "52", "53" }
local pw3_set = Set { "0G1", "0G2", "0G4", "0G5", "0G6", "0G7",
                  "0KB", "0KC", "0KD", "0KE", "0KF", "0KG" }
local koa_set = Set { "0GC", "0GD", "0GR", "0GS", "0GT", "0GU" }
local kt3_set = Set { "0DU", "0K9", "0KA" }

if k2_set[kindle_devcode] then
    return Kindle2
elseif dx_set[kindle_devcode] then
    return Kindle2
elseif dxg_set[kindle_devcode] then
    return KindleDXG
elseif k3_set[kindle_devcode] then
    return Kindle3
elseif k4_set[kindle_devcode] then
    return Kindle4
elseif touch_set[kindle_devcode] then
    return KindleTouch
elseif pw_set[kindle_devcode] then
    return KindlePaperWhite
elseif pw2_set[kindle_devcode] then
    return KindlePaperWhite2
elseif kt2_set[kindle_devcode] then
    return KindleBasic
elseif kv_set[kindle_devcode] then
    return KindleVoyage
elseif pw3_set[kindle_devcode_v2] then
    return KindlePaperWhite3
elseif koa_set[kindle_devcode_v2] then
    return KindleOasis
elseif kt3_set[kindle_devcode_v2] then
    return KindleBasic2
end

error("unknown Kindle model "..kindle_devcode.." ("..kindle_devcode_v2..")")
