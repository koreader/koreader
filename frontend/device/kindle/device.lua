local Generic = require("device/generic/device")
local logger = require("logger")

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

--[[
Test if a kindle device has Special Offers
--]]
local function isSpecialOffers()
    -- Look at the current blanket modules to see if the SO screensavers are enabled...
    local haslipc, lipc = pcall(require, "liblipclua")
    if not (haslipc and lipc) then
        logger.warn("could not load liblibclua")
        return true
    end
    local lipc_handle = lipc.init("com.github.koreader.device")
    if not lipc_handle then
        logger.warn("could not get lipc handle")
        return true
    end
    local is_so
    local loaded_blanket_modules = lipc_handle:get_string_property("com.lab126.blanket", "load")
    if string.find(loaded_blanket_modules, "ad_screensaver") then
        is_so = true
    else
        is_so = false
    end
    lipc_handle:close()
    return is_so
end

function Kindle:supportsScreensaver()
    if isSpecialOffers() then
        return false
    else
        return true
    end
end

function Kindle:setDateTime(year, month, day, hour, min, sec)
    if hour == nil or min == nil then return true end
    local command
    if year and month and day then
        command = string.format("date -s '%d-%d-%d %d:%d:%d'", year, month, day, hour, min, sec)
    else
        command = string.format("date -s '%d:%d'",hour, min)
    end
    if os.execute(command) == 0 then
        os.execute('hwclock -u -w')
        return true
    else
        return false
    end
end

function Kindle:usbPlugIn()
    -- NOTE: We cannot support running in USBMS mode (we cannot, we live on the partition being exported!).
    --       But since that's the default state of the Kindle system, we have to try to make nice...
    --       To that end, we're currently SIGSTOPping volumd to inhibit the system's USBMS mode handling.
    --       It's not perfect (f.g., if the system is setup for USBMS and not USBNet,
    --       the frontlight will be turned off when plugged in), but it at least prevents users from completely
    --       shooting themselves in the foot (c.f., https://github.com/koreader/koreader/issues/3220)!
    --       On the upside, we don't have to bother waking up the WM to show us the USBMS screen :D.
    -- NOTE: If the device is put in USBNet mode before we even start, everything's peachy, though :).
    self.charging_mode = true
end

function Kindle:intoScreenSaver()
    local Screensaver = require("ui/screensaver")
    if self:supportsScreensaver() then
        -- NOTE: Meaning this is not a SO device ;)
        if self.screen_saver_mode == false then
            Screensaver:show()
        end
    else
        -- Let the native system handle screensavers on SO devices...
        if self.screen_saver_mode == false then
            if os.getenv("AWESOME_STOPPED") == "yes" then
                os.execute("killall -cont awesome")
            end
        end
    end
    self.powerd:beforeSuspend()
    self.screen_saver_mode = true
end

function Kindle:outofScreenSaver()
    if self.screen_saver_mode == true then
        local Screensaver = require("ui/screensaver")
        if self:supportsScreensaver() then
            Screensaver:close()
        else
            -- Stop awesome again if need be...
            if os.getenv("AWESOME_STOPPED") == "yes" then
                os.execute("killall -stop awesome")
            end
        end
        local UIManager = require("ui/uimanager")
        UIManager:nextTick(function() UIManager:setDirty("all", "full") end)
    end
    self.powerd:afterResume()
    self.screen_saver_mode = false
end

function Kindle:usbPlugOut()
    -- NOTE: See usbPlugIn(), we don't have anything fancy to do here either.

    --@TODO signal filemanager for file changes  13.06 2012 (houqp)
    self.charging_mode = false
end

function Kindle:ambientBrightnessLevel()
    local haslipc, lipc = pcall(require, "liblipclua")
    if not haslipc or lipc == nil then return 0 end
    local lipc_handle = lipc.init("com.github.koreader.ambientbrightness")
    if not lipc_handle then return 0 end
    local value = lipc_handle:get_int_property("com.lab126.powerd", "alsLux")
    lipc_handle:close()
    if type(value) ~= "number" then return 0 end
    if value < 10 then return 0 end
    if value < 96 then return 1 end
    if value < 192 then return 2 end
    if value < 32768 then return 3 end
    return 4
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

local KindleOasis2 = Kindle:new{
    model = "KindleOasis2",
    isTouchDevice = yes,
    hasFrontlight = yes,
    hasKeys = yes,
    display_dpi = 300,
    touch_dev = "/dev/input/by-path/platform-30a30000.i2c-event",
}

local KindleBasic2 = Kindle:new{
    model = "KindleBasic2",
    isTouchDevice = yes,
    touch_dev = "/dev/input/event0",
}

function Kindle2:init()
    self.screen = require("ffi/framebuffer_einkfb"):new{device = self, debug = logger.dbg}
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
    self.screen = require("ffi/framebuffer_einkfb"):new{device = self, debug = logger.dbg}
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
    self.screen = require("ffi/framebuffer_einkfb"):new{device = self, debug = logger.dbg}
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
    self.screen = require("ffi/framebuffer_einkfb"):new{device = self, debug = logger.dbg}
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
    self.input.open("fake_events")
    Kindle.init(self)
end

-- luacheck: push
-- luacheck: ignore
local ABS_MT_POSITION_X = 53
local ABS_MT_POSITION_Y = 54
-- luacheck: pop
function KindleTouch:init()
    self.screen = require("ffi/framebuffer_mxcfb"):new{device = self, debug = logger.dbg}
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
    self.screen = require("ffi/framebuffer_mxcfb"):new{device = self, debug = logger.dbg}
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
    self.screen = require("ffi/framebuffer_mxcfb"):new{device = self, debug = logger.dbg}
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
    self.screen = require("ffi/framebuffer_mxcfb"):new{device = self, debug = logger.dbg}
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
    self.screen = require("ffi/framebuffer_mxcfb"):new{device = self, debug = logger.dbg}
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
    self.screen = require("ffi/framebuffer_mxcfb"):new{device = self, debug = logger.dbg}
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
    self.screen = require("ffi/framebuffer_mxcfb"):new{device = self, debug = logger.dbg}
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
    local std_out = io.popen("grep -e 'Handlers\\|EV=' /proc/bus/input/devices | grep -B1 'EV=d' | grep -o 'event[0-9]'", "r")
    if std_out then
        local rotation_dev = std_out:read()
        std_out:close()
        if rotation_dev then
            self.input.open("/dev/input/"..rotation_dev)
        end
    end

    self.input.open("fake_events")
end

function KindleOasis2:init()
    self.screen = require("ffi/framebuffer_mxcfb"):new{device = self, debug = logger.dbg}
    self.powerd = require("device/kindle/powerd"):new{
        device = self,
        fl_intensity_file = "/sys/class/backlight/max77796-bl/brightness",
        batt_capacity_file = "/sys/class/power_supply/max77796-battery/capacity",
        is_charging_file = "/sys/class/power_supply/max77796-charger/charging",
    }

    self.input = require("device/input"):new{
        device = self,

        -- Top, Bottom (yes, it's the reverse than on non-Oasis devices)
        event_map = {
            [104] = "RPgFwd",
            [109] = "RPgBack",
        }
    }

    -- FIXME: When starting KOReader with the device upside down ("D"), touch input is registered wrong
    --        (i.e., probably upside down).
    --        If it's started upright ("U"), everything's okay, and turning it upside down after that works just fine.
    --        See #2206 & #2209 for the original KOA implementation, which obviously doesn't quite cut it here...
    --        See also https://www.mobileread.com/forums/showthread.php?t=298302&page=5
    -- NOTE: It'd take some effort to actually start KOReader while in a LANDSCAPE orientation,
    --       since they're only exposed inside the stock reader, and not the Home/KUAL Booklets.
    local haslipc, lipc = pcall(require, "liblipclua")
    if haslipc and lipc then
        local lipc_handle = lipc.init("com.github.koreader.screen")
        if lipc_handle then
            local orientation_code = lipc_handle:get_string_property(
                "com.lab126.winmgr", "accelerometer")
            local rotation_mode = 0
            if orientation_code then
                if orientation_code == "U" then
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
    self.input.open("/dev/input/by-path/platform-gpio-keys-event")

    -- Get accelerometer device by looking for EV=d
    local std_out = io.popen("grep -e 'Handlers\\|EV=' /proc/bus/input/devices | grep -B1 'EV=d' | grep -o 'event[0-9]\\{1,2\\}'", "r")
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
    self.screen = require("ffi/framebuffer_mxcfb"):new{device = self, debug = logger.dbg}
    self.powerd = require("device/kindle/powerd"):new{
        device = self,
        batt_capacity_file = "/sys/class/power_supply/bd7181x_bat/capacity",
        is_charging_file = "/sys/class/power_supply/bd7181x_bat/charging",
    }

    Kindle.init(self)

    self.input.open(self.touch_dev)
    self.input.open("fake_events")
end

function KindleTouch:exit()
    Generic.exit(self)
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
end
KindlePaperWhite.exit = KindleTouch.exit
KindlePaperWhite2.exit = KindleTouch.exit
KindleBasic.exit = KindleTouch.exit
KindleVoyage.exit = KindleTouch.exit
KindlePaperWhite3.exit = KindleTouch.exit
KindleOasis.exit = KindleTouch.exit
KindleOasis2.exit = KindleTouch.exit
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
--       c.f., https://wiki.mobileread.com/wiki/Kindle_Serial_Numbers for identified variants
--       c.f., https://github.com/NiLuJe/KindleTool/blob/master/KindleTool/kindle_tool.h#L174 for all variants
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
                  "0KB", "0KC", "0KD", "0KE", "0KF", "0KG", "0LK", "0LL" }
local koa_set = Set { "0GC", "0GD", "0GR", "0GS", "0GT", "0GU" }
local koa2_set = Set { "0LM", "0LN", "0LP", "0LQ", "0P1", "0P2", "0P6",
                  "0P7", "0P8", "0S1", "0S2", "0S3", "0S4", "0S7", "0SA" }
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
elseif koa2_set[kindle_devcode_v2] then
    return KindleOasis2
elseif kt3_set[kindle_devcode_v2] then
    return KindleBasic2
end

error("unknown Kindle model "..kindle_devcode.." ("..kindle_devcode_v2..")")
