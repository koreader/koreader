local Generic = require("device/generic/device")
local DEBUG = require("dbg")

local function yes() return true end

local Kindle = Generic:new{
    model = "Kindle",
    isKindle = yes,
}

local Kindle2 = Kindle:new{
    model = "Kindle2",
    hasKeyboard = yes,
    hasKeys = yes,
}

local KindleDXG = Kindle:new{
    model = "KindleDXG",
    hasKeyboard = yes,
    hasKeys = yes,
}

local Kindle3 = Kindle2:new{
    model = "Kindle3",
    hasKeyboard = yes,
    hasKeys = yes,
}

local Kindle4 = Kindle:new{
    model = "Kindle4",
    hasKeys = yes,
}

local KindleTouch = Kindle:new{
    model = "KindleTouch",
    isTouchDevice = yes,
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
    -- FIXME!
    touch_dev = "/dev/input/event0",
}

local KindleVoyage = Kindle:new{
    model = "KindleVoyage",
    isTouchDevice = yes,
    hasFrontlight = yes,
    display_dpi = 300,
    touch_dev = "/dev/input/event1",
}

function Kindle2:init()
    self.screen = require("ffi/framebuffer_einkfb"):new{device = self, debug = DEBUG}
    self.input = require("device/input"):new{
        device = self,
        event_map = require("device/kindle/event_map_keyboard"),
    }
    self.input.open("/dev/input/event1")
    Kindle.init(self)
end

function KindleDXG:init()
    self.screen = require("ffi/framebuffer_einkfb"):new{device = self, debug = DEBUG}
    self.input = require("device/input"):new{
        device = self,
        event_map = require("device/kindle/event_map_keyboard"),
    }
    self.input.open("/dev/input/event0")
    self.input.open("/dev/input/event1")
    Kindle.init(self)
end

function Kindle3:init()
    self.screen = require("ffi/framebuffer_einkfb"):new{device = self, debug = DEBUG}
    self.input = require("device/input"):new{
        device = self,
        event_map = require("device/kindle/event_map_keyboard"),
    }
    self.input.open("/dev/input/event1")
    self.input.open("/dev/input/event2")
    Kindle.init(self)
end

function Kindle4:init()
    self.screen = require("ffi/framebuffer_einkfb"):new{device = self, debug = DEBUG}
    self.input = require("device/input"):new{
        device = self,
        event_map = require("device/kindle/event_map_kindle4"),
    }
    self.input.event_map = require("device/kindle/event_map_kindle4")
    self.input.open("/dev/input/event1")
    Kindle.init(self)
end

local ABS_MT_POSITION_X = 53
local ABS_MT_POSITION_Y = 54
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
    self.input.open("/dev/input/event3") -- touchscreen
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

    self.input.open("/dev/input/event0")
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

    self.input.open("/dev/input/event1")
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

    -- FIXME!
    self.input.open("/dev/input/event0")
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

    Kindle.init(self)

    self.input.open("/dev/input/event1")
    -- TODO: Handle the page turn 'buttons'! (/dev/input/event2)
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


local kindle_sn = io.open("/proc/usid", "r")
if not kindle_sn then return end
local kindle_devcode = string.sub(kindle_sn:read(),3,4)
kindle_sn:close()

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
end

error("unknown Kindle model "..kindle_devcode)
