local Generic = require("device/generic/device")
local UIManager
local time = require("ui/time")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")

-- We're going to need a few <linux/fb.h> & <linux/input.h> constants...
local ffi = require("ffi")
local C = ffi.C
require("ffi/linux_fb_h")
require("ffi/linux_input_h")
require("ffi/posix_h")

local function yes() return true end
local function no() return false end  -- luacheck: ignore

local function kindleEnableWifi(toggle)
    local haslipc, lipc = pcall(require, "liblipclua")
    local lipc_handle = nil
    if haslipc and lipc then
        lipc_handle = lipc.init("com.github.koreader.networkmgr")
    end
    if lipc_handle then
        -- Be extremely thorough... c.f., #6019
        -- NOTE: I *assume* this'll also ensure we prefer Wi-Fi over 3G/4G, which is a plus in my book...
        if toggle == 1 then
            lipc_handle:set_int_property("com.lab126.cmd", "wirelessEnable", 1)
            lipc_handle:set_int_property("com.lab126.wifid", "enable", 1)
        else
            lipc_handle:set_int_property("com.lab126.wifid", "enable", 0)
            lipc_handle:set_int_property("com.lab126.cmd", "wirelessEnable", 0)
        end
        lipc_handle:close()
    else
        -- No liblipclua on FW < 5.x ;)
        -- Always kill 3G first...
        os.execute("lipc-set-prop -i com.lab126.wan enable 0")
        os.execute("lipc-set-prop -i com.lab126.wifid enable " .. toggle)
    end
end

-- Check if wifid thinks that the WiFi is enabled
--[[
local function isWifiUp()
    local haslipc, lipc = pcall(require, "liblipclua")
    local lipc_handle = nil
    if haslipc and lipc then
        lipc_handle = lipc.init("com.github.koreader.networkmgr")
    end
    if lipc_handle then
        local status = lipc_handle:get_int_property("com.lab126.wifid", "enable") or 0
        lipc_handle:close()

        return status == 1
    else
        local std_out = io.popen("lipc-get-prop -i com.lab126.wifid enable", "r")
        if std_out then
            local result = std_out:read("*number")
            std_out:close()

            if not result then
                return false
            end

            return result == 1
        else
            return false
        end
    end
end
--]]

--[[
Test if a kindle device is flagged as a Special Offers device (i.e., ad supported) (FW >= 5.x)
--]]
local function isSpecialOffers()
    -- Look at the current blanket modules to see if the SO screensavers are enabled...
    local haslipc, lipc = pcall(require, "liblipclua")
    if not (haslipc and lipc) then
        logger.warn("could not load liblipclua:", lipc)
        return true
    end
    local lipc_handle = lipc.init("com.github.koreader.device")
    if not lipc_handle then
        logger.warn("could not get lipc handle")
        return true
    end
    local is_so
    local loaded_blanket_modules = lipc_handle:get_string_property("com.lab126.blanket", "load")
    if not loaded_blanket_modules then
        logger.warn("could not get lipc property")
        return true
    end
    if string.find(loaded_blanket_modules, "ad_screensaver") then
        is_so = true
    else
        is_so = false
    end
    lipc_handle:close()
    return is_so
end

--[[
Test if a kindle device has *received* Special Offers (FW < 5.x)
--]]
local function hasSpecialOffers()
    if lfs.attributes("/mnt/us/system/.assets", "mode") == "directory" then
        return true
    else
        return false
    end
end

local function frameworkStopped()
    if os.getenv("STOP_FRAMEWORK") == "yes" then
        local haslipc, lipc = pcall(require, "liblipclua")
        if not (haslipc and lipc) then
            logger.warn("could not load liblibclua")
            return
        end
        local lipc_handle = lipc.init("com.lab126.kaf")
        if not lipc_handle then
            logger.warn("could not get lipc handle")
            return
        end
        local frameworkStarted = lipc_handle:register_int_property("frameworkStarted", "r")
        frameworkStarted.value = 1
        lipc_handle:set_string_property("com.lab126.blanket", "unload", "splash")
        lipc_handle:set_string_property("com.lab126.blanket", "unload", "screensaver")
        return lipc_handle
    end
end

local Kindle = Generic:extend{
    model = "Kindle",
    isKindle = yes,
    -- NOTE: We can cheat by adding a platform-specific entry here, because the only code that will check for this is here.
    isSpecialOffers = isSpecialOffers(),
    hasOTAUpdates = yes,
    hasFastWifiStatusQuery = yes,
    hasWifiRestore = yes,
    -- NOTE: HW inversion is generally safe on mxcfb Kindles
    canHWInvert = yes,
    -- NOTE: And the fb driver is generally sane on those, too
    canModifyFBInfo = yes,
    -- NOTE: Newer devices will turn the frontlight off at 0
    canTurnFrontlightOff = yes,
    -- NOTE: Via powerd.toggleSuspend
    canSuspend = yes,
    home_dir = "/mnt/us",
    -- New devices are REAGL-aware, default to REAGL
    isREAGL = yes,
    -- Rex & Zelda devices sport an updated driver.
    isZelda = no,
    isRex = no,
    -- So do devices running on a MediaTek SoC
    isMTK = no,
    -- But of course, some devices don't actually support all the features the kernel exposes...
    isNightModeChallenged = no,
    -- NOTE: While this ought to behave on Zelda/Rex, turns out, nope, it really doesn't work on *any* of 'em :/ (c.f., ko#5884).
    canHWDither = no,
    -- The time the device went into suspend
    suspend_time = 0,
    framework_lipc_handle = frameworkStopped()
}

function Kindle:initNetworkManager(NetworkMgr)
    function NetworkMgr:turnOnWifi(complete_callback)
        kindleEnableWifi(1)
        -- NOTE: As we defer the actual work to lipc,
        --       we have no guarantee the Wi-Fi state will have changed by the time kindleEnableWifi returns,
        --       so, delay the callback until we at least can ensure isConnect is true.
        if complete_callback then
            NetworkMgr:scheduleConnectivityCheck(complete_callback)
        end
    end

    function NetworkMgr:turnOffWifi(complete_callback)
        kindleEnableWifi(0)
        -- NOTE: Same here, except disconnect is simpler, so a dumb delay will do...
        if complete_callback then
            UIManager:scheduleIn(2, complete_callback)
        end
    end

    function NetworkMgr:getNetworkInterfaceName()
        return "wlan0" -- so far, all Kindles appear to use wlan0
    end

    function NetworkMgr:restoreWifiAsync()
        kindleEnableWifi(1)
    end

    NetworkMgr.isWifiOn = NetworkMgr.sysfsWifiOn
    NetworkMgr.isConnected = NetworkMgr.ifHasAnAddress
end

function Kindle:supportsScreensaver()
    if self.isSpecialOffers then
        return false
    else
        return true
    end
end

function Kindle:init()
    -- Check if the device supports deep sleep/quick boot
    if lfs.attributes("/sys/devices/platform/falconblk/uevent", "mode") == "file" then
        -- Now, poke the appreg db to see if it's actually *enabled*...
        -- NOTE: The setting is only available on registered devices, as such, it *can* be missing,
        --       which is why we check for it existing and being *disabled*, as that ensures user interaction.
        local SQ3 = require("lua-ljsqlite3/init")
        local appreg = SQ3.open("/var/local/appreg.db", "ro")
        local hibernation_disabled = tonumber(appreg:rowexec(
            "SELECT EXISTS(SELECT value FROM properties WHERE handlerId = 'dcc' AND name = 'hibernate.enabled' AND value = 0);"
        ))
        -- Check the actual delay while we're there...
        local hibernation_delay =
            appreg:rowexec("SELECT value FROM properties WHERE handlerId = 'dcc' AND name = 'hibernate.s2h.rtc.secs'") or
            appreg:rowexec("SELECT value FROM properties WHERE handlerId = 'dcd' AND name = 'hibernate.s2h.rtc.secs'") or
            3600
        appreg:close()
        if hibernation_disabled == 1 then
            self.canDeepSleep = false
        else
            self.canDeepSleep = true
            self.hibernationDelay = tonumber(hibernation_delay)
            logger.dbg("Kindle: Device supports hibernation, enters hibernation after", self.hibernationDelay, "seconds in suspend")
        end
    else
        self.canDeepSleep = false
    end

    Generic.init(self)
end

function Kindle:setDateTime(year, month, day, hour, min, sec)
    if hour == nil or min == nil then return true end

    -- Prefer using the setdate wrapper if possible, as it will poke the native UI, too.
    if lfs.attributes("/usr/sbin/setdate", "mode") == "file" then
        local t = os.date("*t") -- Start with now to make sure we have a full table
        t.year = year or t.year
        t.month = month or t.month
        t.day = day or t.day
        t.hour = hour
        t.min = min
        t.sec = sec or t.sec
        local epoch = os.time(t)

        local command = string.format("/usr/sbin/setdate '%d'", epoch)
        return os.execute(command) == 0
    else
        local command
        if year and month and day then
            command = string.format("date -s '%d-%d-%d %d:%d:%d' '+%%Y-%%m-%%d %%H:%%M:%%S'", year, month, day, hour, min, sec)
        else
            command = string.format("date -s '%d:%d' '+%%H:%%M'", hour, min)
        end
        if os.execute(command) == 0 then
            os.execute("hwclock -u -w")
            return true
        else
            return false
        end
    end
end

function Kindle:usbPlugIn()
    -- NOTE: We cannot support running in USBMS mode (we cannot, we live on the partition being exported!).
    --       But since that's the default state of the Kindle system, we have to try to make nice...
    --       To that end, we're currently SIGSTOPping volumd to inhibit the system's USBMS mode handling.
    --       It's not perfect (e.g., if the system is setup for USBMS and not USBNet,
    --       the frontlight will be turned off when plugged in), but it at least prevents users from completely
    --       shooting themselves in the foot (c.f., https://github.com/koreader/koreader/issues/3220)!
    --       On the upside, we don't have to bother waking up the WM to show us the USBMS screen :D.
    -- NOTE: If the device is put in USBNet mode before we even start, everything's peachy, though :).
end

function Kindle:intoScreenSaver()
    if not self.screen_saver_mode then
        if self:supportsScreensaver() then
            -- NOTE: Meaning this is not a SO device ;)
            local Screensaver = require("ui/screensaver")
            Screensaver:setup()
            Screensaver:show()
        else
            -- Let the native system handle screensavers on SO devices...
            if os.getenv("AWESOME_STOPPED") == "yes" then
                os.execute("killall -CONT awesome")
            elseif os.getenv("CVM_STOPPED") == "yes" then
                os.execute("killall -CONT cvm")
            end

            -- Don't forget to flag ourselves in ScreenSaver mode like Screensaver:show would,
            -- so that we do the right thing on resume ;).
            self.screen_saver_mode = true
        end

        self.powerd:beforeSuspend()
    end
end

function Kindle:outofScreenSaver()
    if self.screen_saver_mode then
        if self:supportsScreensaver() then
            local Screensaver = require("ui/screensaver")
            local widget_was_closed = Screensaver:close()
            if widget_was_closed then
                -- And redraw everything in case the framework managed to screw us over...
                UIManager:nextTick(function() UIManager:setDirty("all", "full") end)
            end

            -- If the device supports deep sleep, and we woke up from hibernation (which kicks in at the 1H mark),
            -- chuck an extra tiny refresh to get rid of the "waking up" banner if the above refresh was too early...
            if self.canDeepSleep and self.last_suspend_time > time.s(self.hibernationDelay) then
                if lfs.attributes("/var/local/system/powerd/hibernate_session_tracker", "mode") == "file" then
                    local mtime = lfs.attributes("/var/local/system/powerd/hibernate_session_tracker", "modification")
                    local now = os.time()
                    if math.abs(now - mtime) <= 60 then
                        -- That was less than a minute ago, assume we're golden.
                        logger.dbg("Kindle: Woke up from hibernation")
                        -- The banner on a 1236x1648 PW5 is 1235x125; we refresh the bottom 10% of the screen to be safe.
                        local Geom = require("ui/geometry")
                        local screen_height = self.screen:getHeight()
                        local refresh_height = math.ceil(screen_height * (1/10))
                        local refresh_region = Geom:new{
                            x = 0,
                            y = screen_height - 1 - refresh_height,
                            w = self.screen:getWidth(),
                            h = refresh_height
                        }
                        UIManager:scheduleIn(1.5, function()
                            UIManager:setDirty("all", "ui", refresh_region)
                        end)
                    end
                end
            end
        else
            -- Stop awesome again if need be...
            if os.getenv("AWESOME_STOPPED") == "yes" then
                os.execute("killall -STOP awesome")
            elseif os.getenv("CVM_STOPPED") == "yes" then
                os.execute("killall -STOP cvm")
            end
            -- NOTE: We redraw after a slightly longer delay to take care of the potentially dynamic ad screen...
            --       This is obviously brittle as all hell. Tested on a slow-ass PW1.
            UIManager:scheduleIn(3, function() UIManager:setDirty("all", "full") end)
            -- Flip the switch again
            self.screen_saver_mode = false
        end

        self.powerd:afterResume()
    end
end

function Kindle:usbPlugOut()
    -- NOTE: See usbPlugIn(), we don't have anything fancy to do here either.
end

function Kindle:wakeupFromSuspend()
    self.powerd:wakeupFromSuspend()
    self.last_suspend_time = time.boottime_or_realtime_coarse() - self.suspend_time
    self.total_suspend_time = self.total_suspend_time + self.last_suspend_time
end

function Kindle:readyToSuspend()
    self.powerd:readyToSuspend()
    self.suspend_time = time.boottime_or_realtime_coarse()
end

-- We add --no-same-permissions --no-same-owner to make the userstore fuse proxy happy...
function Kindle:untar(archive, extract_to)
    return os.execute(("./tar --no-same-permissions --no-same-owner -xf %q -C %q"):format(archive, extract_to))
end

function Kindle:UIManagerReady(uimgr)
    UIManager = uimgr
end

function Kindle:setEventHandlers(uimgr)
    UIManager.event_handlers.Suspend = function()
        self.powerd:toggleSuspend()
    end
    UIManager.event_handlers.IntoSS = function()
        self:intoScreenSaver()
    end
    UIManager.event_handlers.OutOfSS = function()
        self:outofScreenSaver()
    end
    UIManager.event_handlers.Charging = function()
        self:_beforeCharging()
        self:usbPlugIn()
    end
    UIManager.event_handlers.NotCharging = function()
        self:usbPlugOut()
        self:_afterNotCharging()
    end
    UIManager.event_handlers.WakeupFromSuspend = function()
        self:wakeupFromSuspend()
    end
    UIManager.event_handlers.ReadyToSuspend = function()
        self:readyToSuspend()
    end
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

local Kindle2 = Kindle:extend{
    model = "Kindle2",
    isREAGL = no,
    hasKeyboard = yes,
    hasKeys = yes,
    hasDPad = yes,
    canHWInvert = no,
    canModifyFBInfo = no,
    canUseCBB = no, -- 4bpp
    canUseWAL = no, -- Kernel too old to support mmap'ed I/O on /mnt/us
    supportsScreensaver = yes, -- The first ad-supported device was the K3
}

local KindleDXG = Kindle:extend{
    model = "KindleDXG",
    isREAGL = no,
    hasKeyboard = yes,
    hasKeys = yes,
    hasDPad = yes,
    canHWInvert = no,
    canModifyFBInfo = no,
    canUseCBB = no, -- 4bpp
    canUseWAL = no, -- Kernel too old to support mmap'ed I/O on /mnt/us
    supportsScreensaver = yes, -- The first ad-supported device was the K3
}

local Kindle3 = Kindle:extend{
    model = "Kindle3",
    isREAGL = no,
    hasKeyboard = yes,
    hasKeys = yes,
    hasDPad = yes,
    canHWInvert = no,
    canModifyFBInfo = no,
    canUseCBB = no, -- 4bpp
    isSpecialOffers = hasSpecialOffers(),
}

local Kindle4 = Kindle:extend{
    model = "Kindle4",
    isREAGL = no,
    hasKeys = yes,
    hasDPad = yes,
    canHWInvert = no,
    canModifyFBInfo = no,
    -- NOTE: It could *technically* use the C BB, as it's running @ 8bpp, but it's expecting an inverted palette...
    canUseCBB = no,
    isSpecialOffers = hasSpecialOffers(),
}

local KindleTouch = Kindle:extend{
    model = "KindleTouch",
    isREAGL = no,
    isTouchDevice = yes,
    hasKeys = yes,
    touch_dev = "/dev/input/event3",
}

local KindlePaperWhite = Kindle:extend{
    model = "KindlePaperWhite",
    isREAGL = no,
    isTouchDevice = yes,
    hasFrontlight = yes,
    canTurnFrontlightOff = no,
    display_dpi = 212,
    touch_dev = "/dev/input/event0",
}

local KindlePaperWhite2 = Kindle:extend{
    model = "KindlePaperWhite2",
    isTouchDevice = yes,
    hasFrontlight = yes,
    canTurnFrontlightOff = no,
    display_dpi = 212,
    touch_dev = "/dev/input/event1",
}

local KindleBasic = Kindle:extend{
    model = "KindleBasic",
    isTouchDevice = yes,
    touch_dev = "/dev/input/event1",
}

local KindleVoyage = Kindle:extend{
    model = "KindleVoyage",
    isTouchDevice = yes,
    hasFrontlight = yes,
    canTurnFrontlightOff = no,
    hasKeys = yes,
    display_dpi = 300,
    touch_dev = "/dev/input/event1",
}

local KindlePaperWhite3 = Kindle:extend{
    model = "KindlePaperWhite3",
    isTouchDevice = yes,
    hasFrontlight = yes,
    canTurnFrontlightOff = no,
    display_dpi = 300,
    touch_dev = "/dev/input/event1",
}

local KindleOasis = Kindle:extend{
    model = "KindleOasis",
    isTouchDevice = yes,
    hasFrontlight = yes,
    hasKeys = yes,
    hasGSensor = yes,
    display_dpi = 300,
    --[[
    -- NOTE: Points to event3 on Wi-Fi devices, event4 on 3G devices...
    --       3G devices apparently have an extra SX9500 Proximity/Capacitive controller for mysterious purposes...
    --       This evidently screws with the ordering, so, use the udev by-path path instead to avoid hackier workarounds.
    --       cf. #2181
    --]]
    touch_dev = "/dev/input/by-path/platform-imx-i2c.1-event",
}

local KindleOasis2 = Kindle:extend{
    model = "KindleOasis2",
    isZelda = yes,
    isTouchDevice = yes,
    hasFrontlight = yes,
    hasKeys = yes,
    hasGSensor = yes,
    display_dpi = 300,
    touch_dev = "/dev/input/by-path/platform-30a30000.i2c-event",
}

local KindleOasis3 = Kindle:extend{
    model = "KindleOasis3",
    isZelda = yes,
    isTouchDevice = yes,
    hasFrontlight = yes,
    hasNaturalLight = yes,
    hasNaturalLightMixer = yes,
    hasKeys = yes,
    hasGSensor = yes,
    display_dpi = 300,
    touch_dev = "/dev/input/by-path/platform-30a30000.i2c-event",
}

local KindleBasic2 = Kindle:extend{
    model = "KindleBasic2",
    isTouchDevice = yes,
    touch_dev = "/dev/input/event0",
}

local KindlePaperWhite4 = Kindle:extend{
    model = "KindlePaperWhite4",
    isRex = yes,
    isTouchDevice = yes,
    hasFrontlight = yes,
    display_dpi = 300,
    -- NOTE: LTE devices once again have a mysterious extra SX9310 proximity sensor...
    --       Except this time, we can't rely on by-path, because there's no entry for the TS :/.
    --       Should be event2 on Wi-Fi, event3 on LTE, we'll fix it in init.
    touch_dev = "/dev/input/event2",
}

local KindleBasic3 = Kindle:extend{
    model = "KindleBasic3",
    isRex = yes,
    -- NOTE: Apparently, the KT4 doesn't actually support the fancy nightmode waveforms, c.f., ko/#5076
    --       It also doesn't handle HW dithering, c.f., base/#1039
    isNightModeChallenged = yes,
    isTouchDevice = yes,
    hasFrontlight = yes,
    touch_dev = "/dev/input/event2",
}

local KindlePaperWhite5 = Kindle:extend{
    model = "KindlePaperWhite5",
    isMTK = yes,
    isTouchDevice = yes,
    hasFrontlight = yes,
    hasNaturalLight = yes,
    -- NOTE: We *can* technically control both LEDs independently,
    --       but the mix is device-specific, we don't have access to the LUT for the mix powerd is using,
    --       and the widget is designed for the Kobo Aura One anyway, so, hahaha, nope.
    hasNaturalLightMixer = yes,
    display_dpi = 300,
    touch_dev = "/dev/input/by-path/platform-1001e000.i2c-event",
    -- NOTE: While hardware dithering (via MDP) should be a thing, it doesn't appear to do anything right now :/.
    canHWDither = no,
    canDoSwipeAnimation = yes,
}

local KindleBasic4 = Kindle:extend{
    model = "KindleBasic4",
    isMTK = yes,
    isTouchDevice = yes,
    hasFrontlight = yes,
    display_dpi = 300,
    -- TBD
    touch_dev = "/dev/input/by-path/platform-1001e000.i2c-event",
    canHWDither = no,
    canDoSwipeAnimation = yes,
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
    self.input.open("fake_events")
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
    self.input.open("fake_events")
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
        event_map = require("device/kindle/event_map_kindle4"),
    }
    self.keyboard_layout = require("device/kindle/keyboard_layout")
    self.input.open("/dev/input/event0")
    self.input.open("/dev/input/event1")
    self.input.open("fake_events")
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
        hall_file = "/sys/devices/system/wario_hall/wario_hall0/hall_enable",
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
        hall_file = "/sys/devices/system/wario_hall/wario_hall0/hall_enable",
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
        hall_file = "/sys/devices/system/wario_hall/wario_hall0/hall_enable",
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

    -- reenable WhisperTouch keys when started without framework
    if self.framework_lipc_handle then
        self.framework_lipc_handle:set_int_property("com.lab126.deviced", "fsrkeypadEnable", 1)
        self.framework_lipc_handle:set_int_property("com.lab126.deviced", "fsrkeypadPrevEnable", 1)
        self.framework_lipc_handle:set_int_property("com.lab126.deviced", "fsrkeypadNextEnable", 1)
    end
end

function KindlePaperWhite3:init()
    self.screen = require("ffi/framebuffer_mxcfb"):new{device = self, debug = logger.dbg}
    self.powerd = require("device/kindle/powerd"):new{
        device = self,
        fl_intensity_file = "/sys/class/backlight/max77696-bl/brightness",
        batt_capacity_file = "/sys/devices/system/wario_battery/wario_battery0/battery_capacity",
        is_charging_file = "/sys/devices/system/wario_charger/wario_charger0/charging",
        hall_file = "/sys/devices/system/wario_hall/wario_hall0/hall_enable",
    }

    Kindle.init(self)

    self.input.open(self.touch_dev)
    self.input.open("fake_events")
end

-- HAL for gyro orientation switches (EV_ABS:ABS_PRESSURE (?!) w/ custom values to EV_MSC:MSC_GYRO w/ our own custom values)
local function OasisGyroTranslation(this, ev)
    local DEVICE_ORIENTATION_PORTRAIT_LEFT          = 15
    local DEVICE_ORIENTATION_PORTRAIT_RIGHT         = 17
    local DEVICE_ORIENTATION_PORTRAIT               = 19
    local DEVICE_ORIENTATION_PORTRAIT_ROTATED_LEFT  = 16
    local DEVICE_ORIENTATION_PORTRAIT_ROTATED_RIGHT = 18
    local DEVICE_ORIENTATION_PORTRAIT_ROTATED       = 20
    local DEVICE_ORIENTATION_LANDSCAPE              = 21
    local DEVICE_ORIENTATION_LANDSCAPE_ROTATED      = 22

    if ev.type == C.EV_ABS and ev.code == C.ABS_PRESSURE then
        if ev.value == DEVICE_ORIENTATION_PORTRAIT
            or ev.value == DEVICE_ORIENTATION_PORTRAIT_LEFT
            or ev.value == DEVICE_ORIENTATION_PORTRAIT_RIGHT then
            -- i.e., UR
            ev.type = C.EV_MSC
            ev.code = C.MSC_GYRO
            ev.value = C.DEVICE_ROTATED_UPRIGHT
        elseif ev.value == DEVICE_ORIENTATION_LANDSCAPE then
            -- i.e., CW
            ev.type = C.EV_MSC
            ev.code = C.MSC_GYRO
            ev.value = C.DEVICE_ROTATED_CLOCKWISE
        elseif ev.value == DEVICE_ORIENTATION_PORTRAIT_ROTATED
            or ev.value == DEVICE_ORIENTATION_PORTRAIT_ROTATED_LEFT
            or ev.value == DEVICE_ORIENTATION_PORTRAIT_ROTATED_RIGHT then
            -- i.e., UD
            ev.type = C.EV_MSC
            ev.code = C.MSC_GYRO
            ev.value = C.DEVICE_ROTATED_UPSIDE_DOWN
        elseif ev.value == DEVICE_ORIENTATION_LANDSCAPE_ROTATED then
            -- i.e., CCW
            ev.type = C.EV_MSC
            ev.code = C.MSC_GYRO
            ev.value = C.DEVICE_ROTATED_COUNTER_CLOCKWISE
        end
    end
end

function KindleOasis:init()
    self.screen = require("ffi/framebuffer_mxcfb"):new{device = self, debug = logger.dbg}
    self.powerd = require("device/kindle/powerd"):new{
        device = self,
        fl_intensity_file = "/sys/class/backlight/max77696-bl/brightness",
        -- NOTE: Points to the embedded battery. The one in the cover is codenamed "soda".
        batt_capacity_file = "/sys/devices/system/wario_battery/wario_battery0/battery_capacity",
        is_charging_file = "/sys/devices/system/wario_charger/wario_charger0/charging",
        hall_file = "/sys/devices/system/wario_hall/wario_hall0/hall_enable",
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
                if orientation_code == "U" then
                    rotation_mode = self.screen.DEVICE_ROTATED_UPRIGHT
                elseif orientation_code == "R" then
                    rotation_mode = self.screen.DEVICE_ROTATED_CLOCKWISE
                elseif orientation_code == "D" then
                    rotation_mode = self.screen.DEVICE_ROTATED_UPSIDE_DOWN
                elseif orientation_code == "L" then
                    rotation_mode = self.screen.DEVICE_ROTATED_COUNTER_CLOCKWISE
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

    self.input:registerEventAdjustHook(OasisGyroTranslation)
    self.input.handleMiscEv = function(this, ev)
        if ev.code == C.MSC_GYRO then
            return this:handleGyroEv(ev)
        end
    end

    self.input.open(self.touch_dev)
    self.input.open("/dev/input/by-path/platform-gpiokey.0-event")

    -- get rotate dev by EV=d
    local std_out = io.popen("grep -e 'Handlers\\|EV=' /proc/bus/input/devices | grep -B1 'EV=d' | grep -o 'event[0-9]'", "r")
    if std_out then
        local rotation_dev = std_out:read("*line")
        std_out:close()
        if rotation_dev then
            self.input.open("/dev/input/"..rotation_dev)
        end
    end

    self.input.open("fake_events")
end

-- HAL for gyro orientation switches (EV_ABS:ABS_PRESSURE (?!) w/ custom values to EV_MSC:MSC_GYRO w/ our own custom values)
local function ZeldaGyroTranslation(this, ev)
    -- c.f., drivers/input/misc/accel/bma2x2.c
    local UPWARD_PORTRAIT_UP_INTERRUPT_HAPPENED     = 15
    local UPWARD_PORTRAIT_DOWN_INTERRUPT_HAPPENED   = 16
    local UPWARD_LANDSCAPE_LEFT_INTERRUPT_HAPPENED  = 17
    local UPWARD_LANDSCAPE_RIGHT_INTERRUPT_HAPPENED = 18

    if ev.type == C.EV_ABS and ev.code == C.ABS_PRESSURE then
        if ev.value == UPWARD_PORTRAIT_UP_INTERRUPT_HAPPENED then
            -- i.e., UR
            ev.type = C.EV_MSC
            ev.code = C.MSC_GYRO
            ev.value = C.DEVICE_ROTATED_UPRIGHT
        elseif ev.value == UPWARD_LANDSCAPE_LEFT_INTERRUPT_HAPPENED then
            -- i.e., CW
            ev.type = C.EV_MSC
            ev.code = C.MSC_GYRO
            ev.value = C.DEVICE_ROTATED_CLOCKWISE
        elseif ev.value == UPWARD_PORTRAIT_DOWN_INTERRUPT_HAPPENED then
            -- i.e., UD
            ev.type = C.EV_MSC
            ev.code = C.MSC_GYRO
            ev.value = C.DEVICE_ROTATED_UPSIDE_DOWN
        elseif ev.value == UPWARD_LANDSCAPE_RIGHT_INTERRUPT_HAPPENED then
            -- i.e., CCW
            ev.type = C.EV_MSC
            ev.code = C.MSC_GYRO
            ev.value = C.DEVICE_ROTATED_COUNTER_CLOCKWISE
        end
    end
end

function KindleOasis2:init()
    self.screen = require("ffi/framebuffer_mxcfb"):new{device = self, debug = logger.dbg}
    self.powerd = require("device/kindle/powerd"):new{
        device = self,
        fl_intensity_file = "/sys/class/backlight/max77796-bl/brightness",
        batt_capacity_file = "/sys/class/power_supply/max77796-battery/capacity",
        is_charging_file = "/sys/class/power_supply/max77796-charger/charging",
        batt_status_file = "/sys/class/power_supply/max77796-charger/status",
    }

    self.input = require("device/input"):new{
        device = self,

        -- Top, Bottom (yes, it's the reverse than on non-Oasis devices)
        event_map = {
            [104] = "RPgFwd",
            [109] = "RPgBack",
        }
    }

    --- @fixme When starting KOReader with the device upside down ("D"), touch input is registered wrong
    --        (i.e., probably upside down).
    --        If it's started upright ("U"), everything's okay, and turning it upside down after that works just fine.
    --        See #2206 & #2209 for the original KOA implementation, which obviously doesn't quite cut it here...
    --        See also <https://www.mobileread.com/forums/showthread.php?t=298302&page=5>
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
                    rotation_mode = self.screen.DEVICE_ROTATED_UPRIGHT
                elseif orientation_code == "R" then
                    rotation_mode = self.screen.DEVICE_ROTATED_CLOCKWISE
                elseif orientation_code == "D" then
                    rotation_mode = self.screen.DEVICE_ROTATED_UPSIDE_DOWN
                elseif orientation_code == "L" then
                    rotation_mode = self.screen.DEVICE_ROTATED_COUNTER_CLOCKWISE
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

    self.input:registerEventAdjustHook(ZeldaGyroTranslation)
    self.input.handleMiscEv = function(this, ev)
        if ev.code == C.MSC_GYRO then
            return this:handleGyroEv(ev)
        end
    end

    self.input.open(self.touch_dev)
    self.input.open("/dev/input/by-path/platform-gpio-keys-event")

    -- Get accelerometer device by looking for EV=d
    local std_out = io.popen("grep -e 'Handlers\\|EV=' /proc/bus/input/devices | grep -B1 'EV=d' | grep -o 'event[0-9]\\{1,2\\}'", "r")
    if std_out then
        local rotation_dev = std_out:read("*line")
        std_out:close()
        if rotation_dev then
            self.input.open("/dev/input/"..rotation_dev)
        end
    end

    self.input.open("fake_events")
end

function KindleOasis3:init()
    self.screen = require("ffi/framebuffer_mxcfb"):new{device = self, debug = logger.dbg}
    self.powerd = require("device/kindle/powerd"):new{
        device = self,
        fl_intensity_file = "/sys/class/backlight/lm3697-bl1/brightness",
        warmth_intensity_file = "/sys/class/backlight/lm3697-bl0/brightness",
        batt_capacity_file = "/sys/class/power_supply/max77796-battery/capacity",
        is_charging_file = "/sys/class/power_supply/max77796-charger/charging",
        batt_status_file = "/sys/class/power_supply/max77796-charger/status",
    }

    self.input = require("device/input"):new{
        device = self,

        -- Top, Bottom (yes, it's the reverse than on non-Oasis devices)
        event_map = {
            [104] = "RPgFwd",
            [109] = "RPgBack",
        }
    }


    --- @fixme The same quirks as on the Oasis 2 apply ;).
    local haslipc, lipc = pcall(require, "liblipclua")
    if haslipc and lipc then
        local lipc_handle = lipc.init("com.github.koreader.screen")
        if lipc_handle then
            local orientation_code = lipc_handle:get_string_property(
                "com.lab126.winmgr", "accelerometer")
            local rotation_mode = 0
            if orientation_code then
                if orientation_code == "U" then
                    rotation_mode = self.screen.DEVICE_ROTATED_UPRIGHT
                elseif orientation_code == "R" then
                    rotation_mode = self.screen.DEVICE_ROTATED_CLOCKWISE
                elseif orientation_code == "D" then
                    rotation_mode = self.screen.DEVICE_ROTATED_UPSIDE_DOWN
                elseif orientation_code == "L" then
                    rotation_mode = self.screen.DEVICE_ROTATED_COUNTER_CLOCKWISE
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

    self.input:registerEventAdjustHook(ZeldaGyroTranslation)
    self.input.handleMiscEv = function(this, ev)
        if ev.code == C.MSC_GYRO then
            return this:handleGyroEv(ev)
        end
    end

    self.input.open(self.touch_dev)
    self.input.open("/dev/input/by-path/platform-gpio-keys-event")

    -- Get accelerometer device by looking for EV=d
    local std_out = io.popen("grep -e 'Handlers\\|EV=' /proc/bus/input/devices | grep -B1 'EV=d' | grep -o 'event[0-9]\\{1,2\\}'", "r")
    if std_out then
        local rotation_dev = std_out:read("*line")
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
        batt_status_file = "/sys/class/power_supply/bd7181x_bat/status",
        hall_file = "/sys/devices/system/heisenberg_hall/heisenberg_hall0/hall_enable",
    }

    Kindle.init(self)

    self.input.open(self.touch_dev)
    self.input.open("fake_events")
end

function KindlePaperWhite4:init()
    self.screen = require("ffi/framebuffer_mxcfb"):new{device = self, debug = logger.dbg}
    self.powerd = require("device/kindle/powerd"):new{
        device = self,
        fl_intensity_file = "/sys/class/backlight/bl/brightness",
        batt_capacity_file = "/sys/class/power_supply/bd71827_bat/capacity",
        is_charging_file = "/sys/class/power_supply/bd71827_bat/charging",
        batt_status_file = "/sys/class/power_supply/bd71827_bat/status",
        hall_file = "/sys/bus/platform/drivers/hall_sensor/rex_hall/hall_enable",
    }

    Kindle.init(self)

    -- So, look for a goodix TS input device (c.f., #5110)...
    local std_out = io.popen("grep -e 'Handlers\\|Name=' /proc/bus/input/devices | grep -A1 'goodix-ts' | grep -o 'event[0-9]'", "r")
    if std_out then
        local goodix_dev = std_out:read("*line")
        std_out:close()
        if goodix_dev then
            self.touch_dev = "/dev/input/" .. goodix_dev
        end
    end

    self.input.open(self.touch_dev)
    self.input.open("fake_events")
end

function KindleBasic3:init()
    self.screen = require("ffi/framebuffer_mxcfb"):new{device = self, debug = logger.dbg}
    self.powerd = require("device/kindle/powerd"):new{
        device = self,
        fl_intensity_file = "/sys/class/backlight/bl/brightness",
        batt_capacity_file = "/sys/class/power_supply/bd71827_bat/capacity",
        is_charging_file = "/sys/class/power_supply/bd71827_bat/charging",
        batt_status_file = "/sys/class/power_supply/bd71827_bat/status",
        hall_file = "/sys/bus/platform/drivers/hall_sensor/rex_hall/hall_enable",
    }

    Kindle.init(self)

    -- This device doesn't emit ABS_MT_TRACKING_ID:-1 events on contact lift,
    -- so we have to rely on contact lift detection via BTN_TOUCH:0,
    -- c.f., https://github.com/koreader/koreader/issues/5070
    self.input.snow_protocol = true
    self.input.open(self.touch_dev)
    self.input.open("fake_events")
end

function KindlePaperWhite5:init()
    self.screen = require("ffi/framebuffer_mxcfb"):new{device = self, debug = logger.dbg}
    self.powerd = require("device/kindle/powerd"):new{
        device = self,
        fl_intensity_file = "/sys/class/backlight/fp9966-bl1/brightness",
        warmth_intensity_file = "/sys/class/backlight/fp9966-bl0/brightness",
        batt_capacity_file = "/sys/class/power_supply/bd71827_bat/capacity",
        is_charging_file = "/sys/class/power_supply/bd71827_bat/charging",
        batt_status_file = "/sys/class/power_supply/bd71827_bat/status",
        hall_file = "/sys/devices/platform/eink_hall/hall_enable",
    }

    -- Enable the so-called "fast" mode, so as to prevent the driver from silently promoting refreshes to REAGL.
    self.screen:_MTK_ToggleFastMode(true)

    Kindle.init(self)

    self.input.open(self.touch_dev)
    self.input.open("fake_events")
end

function KindleBasic4:init()
    self.screen = require("ffi/framebuffer_mxcfb"):new{device = self, debug = logger.dbg}
    -- TBD, assume PW5 for now
    self.powerd = require("device/kindle/powerd"):new{
        device = self,
        fl_intensity_file = "/sys/class/backlight/fp9966-bl1/brightness",
        warmth_intensity_file = "/sys/class/backlight/fp9966-bl0/brightness",
        batt_capacity_file = "/sys/class/power_supply/bd71827_bat/capacity",
        is_charging_file = "/sys/class/power_supply/bd71827_bat/charging",
        batt_status_file = "/sys/class/power_supply/bd71827_bat/status",
    }

    -- Enable the so-called "fast" mode, so as to prevent the driver from silently promoting refreshes to REAGL.
    self.screen:_MTK_ToggleFastMode(true)

    Kindle.init(self)

    self.input.open(self.touch_dev)
    self.input.open("fake_events")
end

function KindleTouch:exit()
    if self:isMTK() then
        -- Disable the so-called "fast" mode
        self.screen:_MTK_ToggleFastMode(false)
    end

    if self.framework_lipc_handle then
        self.framework_lipc_handle:close()
    end

    self.powerd:__gc()

    Generic.exit(self)

    if self.isSpecialOffers then
        -- Wakey wakey...
        if os.getenv("AWESOME_STOPPED") == "yes" then
            os.execute("killall -CONT awesome")
        end
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
KindlePaperWhite4.exit = KindleTouch.exit
KindleBasic3.exit = KindleTouch.exit
KindleOasis3.exit = KindleTouch.exit
KindlePaperWhite5.exit = KindleTouch.exit
KindleBasic4.exit = KindleTouch.exit

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
local kindle_sn = kindle_sn_fd:read("*line")
kindle_sn_fd:close()
-- NOTE: Attempt to sanely differentiate v1 from v2,
--       c.f., https://github.com/NiLuJe/FBInk/commit/8a1161734b3f5b4461247af461d26987f6f1632e
local kindle_sn_lead = string.sub(kindle_sn, 1, 1)

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
local pw4_set = Set { "0PP", "0T1", "0T2", "0T3", "0T4", "0T5", "0T6",
                  "0T7", "0TJ", "0TK", "0TL", "0TM", "0TN", "102", "103",
                  "16Q", "16R", "16S", "16T", "16U", "16V" }
local kt4_set = Set { "10L", "0WF", "0WG", "0WH", "0WJ", "0VB" }
local koa3_set = Set { "11L", "0WQ", "0WP", "0WN", "0WM", "0WL" }
local pw5_set = Set { "1LG", "1Q0", "1PX", "1VD", "219", "21A", "2BH", "2BJ", "2DK" }
local kt5_set = Set { "22D", "25T", "23A", "2AQ", "2AP", "1XH", "22C" }

if kindle_sn_lead == "B" or kindle_sn_lead == "9" then
    local kindle_devcode = string.sub(kindle_sn, 3, 4)

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
else
    local kindle_devcode_v2 = string.sub(kindle_sn, 4, 6)

    if pw3_set[kindle_devcode_v2] then
        return KindlePaperWhite3
    elseif koa_set[kindle_devcode_v2] then
        return KindleOasis
    elseif koa2_set[kindle_devcode_v2] then
        return KindleOasis2
    elseif kt3_set[kindle_devcode_v2] then
        return KindleBasic2
    elseif pw4_set[kindle_devcode_v2] then
        return KindlePaperWhite4
    elseif kt4_set[kindle_devcode_v2] then
        return KindleBasic3
    elseif koa3_set[kindle_devcode_v2] then
        return KindleOasis3
    elseif pw5_set[kindle_devcode_v2] then
        return KindlePaperWhite5
    elseif kt5_set[kindle_devcode_v2] then
        return KindleBasic4
    end
end

local kindle_sn_prefix = string.sub(kindle_sn, 1, 6)
error("unknown Kindle model: " .. kindle_sn_prefix)
