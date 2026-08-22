local Generic = require("device/generic/device") -- <= look at this file!
local Event = require("ui/event")
local UIManager
local ffiUtil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")

local function yes() return true end
local function no() return false end

--[[
Bookeen Devices Serial structure : AABBCDDEGYMDSSSSFL

+---------------------------------------------------+
| AA    | Reseller                                  |
| BB    | Screen Type                               |
| C     | Device Generation                         |
| DD    | Device Color                              |
| E     | Hardware Revision                         |
| G     | Option fitted on the hardware             |
| Y     | Year of manufacture                       |
| M     | Month of manufacture                      |
| D     | Day of manufacture                        |
| SSSS  | Build Number of this day of manufacture   |
| F     | Factory                                   |
| L     | Factory's Line                            |
----------------------------------------------------|

Known models:
    Cybook Orizon                   (CYBOR10-BK):   BK60BK021   2011
    Cybook Orizon                   (CYBOR10-BK):   BK60BK02K   2011
    Cybook Odyssey                  (CYBOY10-ADL):  AL60?????   2011
    Cybook Odyssey HD Frontlight    (CYBOY3F-BK):   BK615BK3F   2012    OMAP 3611
    Cybook Odyssey Frontlight       (CYBOY4F-BK):   ?           2013    OMAP 3611
    Nolim                           (CYBOY4F-CF):   ?           2013    OMAP 3611
    Nolimbook+                      (CYBOY4S-CF):   CF605WE4F   2013    Allwinner A13
    Saraiva Lev                     (CYBOY4S-SA):   ?           2014    Allwinner A13
    Saraiva Lev com luz             (CYBOY4F-SA):   ?           2014    Allwinner A13
    Cybook Odyssey Essential        (CYBOY5S-BK):   ?           2014
    Cybook Odyssey Frontlight 2     (CYBOY5F-BK):   ?           2014
    Cybook Muse                     (CYBME1S-BK):   ?           2014
    Cybook Muse Essential           (CYBFT1S-BK):   ?           2014
    Cybook Muse Frontlight          (CYBFT1F-BK):   BK646BK1F   2014    Allwinner A13
    Cybook Ocean                    (CYBON1F-BK):   BK816BK1F   2014    OMAP 3611
    Cybook Ocean                    (CYBON1F-BK):   BK826BK1F   2014    OMAP 3611
    Cybook Muse Light               (CYBME1F-BK):   BK666BK1F
    Cybook Muse Frontlight 2        (CYBME2F-BK):   BK676BK2F
    Cybook Muse HD                  (CYBFT6F-BK):   BK656GY6F   2016
    Nolimbook HD                    (CYBFT1S-CF):   ?           2014
    Nolimbook HD+                   (CYBFT1F-CF):   ?           2014
    Letto Frontlight                (CYBFT1F-AL):   ?           2014
    Nolim XL (Cybook Ocean)         (?):            CF816WE1F
    Saga                            (CYBSB2F-BK):   BK677BK2F   2017
    Diva                            (CYBD1F-BK):    BK658WE1G   2019
    Diva HD                         (CYBD6F-BK):    ?

Screen Type seems to be XY where
- X is Screen Size (6" or 8")
- Y is still unknown

Sources:
* https://blog.soutade.fr/post/2015/03/game_over.html#comment_291
* https://github.com/yoannsculo/blog/blob/master/devices/index.html.markdown2#L12
--]]

local BOOKEEN_RESELLER_ADLIBRIS     = "AL"
local BOOKEEN_RESELLER_BOOKEEN      = "BK"
local BOOKEEN_RESELLER_CARREFOUR    = "CF"
local BOOKEEN_RESELLER_VIRGIN       = "VG"

local BOOKEEN_GENERATION_GEN3_OPUS  = 0x3
local BOOKEEN_GENERATION_ORIZON     = 0x4
local BOOKEEN_GENERATION_ODYSSEY    = 0x5
local BOOKEEN_GENERATION_MUSE_OCEAN = 0x6
local BOOKEEN_GENERATION_SAGA       = 0x7
local BOOKEEN_GENERATION_DIVA       = 0x8

local BOOKEEN_DEVICE_COLOR_BLACK    = "BK"
local BOOKEEN_DEVICE_COLOR_BORDEAUX = "BX"
local BOOKEEN_DEVICE_COLOR_GREEN    = "GN"
local BOOKEEN_DEVICE_COLOR_GREY     = "GY"
local BOOKEEN_DEVICE_COLOR_YELLOW   = "YW"
local BOOKEEN_DEVICE_COLOR_WHITE    = "WE"

local function getSerial()
    local std_out = io.popen("nvram -s|cut -d= -f2")
    local serial = nil
    if std_out ~= nil then
        serial = std_out:read()
        std_out:close()
    end
    -- `nvram` fails outright when /priv is mounted read-only or the private
    -- partition was wiped (S40factory_reset.sh erases it), and then `cut` yields
    -- an empty line rather than nothing at all. Normalise every such case to nil
    -- so the accessors below can report "unknown" instead of indexing a string
    -- that is too short, or returning nil out of tonumber() and having callers
    -- silently compare nil against a generation constant.
    if serial == "" then
        serial = nil
    end
    return serial
end

local Bookeen = Generic:extend{
    model = "Bookeen",
    isBookeen = yes,
    hasKeys = yes,
    hasOTAUpdates = yes,
    hasWifiManager = yes,
    hasFastWifiStatusQuery = yes,
    hasWifiRestore = yes,
    canReboot = yes,
    canPowerOff = yes,
    canSuspend = yes,
    canHWInvert = no,
    isTouchDevice = yes,
    isAlwaysPortrait = yes,
    hasMultitouch = yes,
    hasFrontlight = yes,
    touch_switch_xy = true,
    touch_mirrored_x = true,
    display_dpi = 212,
    serial = getSerial(),
    just_toggled_frontlight = 0
}

-- All of the below decode fixed offsets of the 18-char serial documented at the
-- top of this file. Every one returns nil when the serial is missing or too
-- short, rather than raising: `nvram` is not guaranteed to work (see getSerial),
-- and none of these values is important enough to abort startup over. Callers
-- MUST therefore treat nil as "unknown" and pick a safe default -- do not
-- compare the result against a generation constant and assume a false result
-- means "some other generation".
local function serialField(serial, first, last)
    if type(serial) ~= "string" or #serial < last then
        return nil
    end
    return serial:sub(first, last)
end

function Bookeen:getReseller()
    return serialField(self.serial, 1, 2)
end

function Bookeen:getScreenType()
    return tonumber(serialField(self.serial, 3, 4) or "", 16)
end

function Bookeen:getDeviceGeneration()
    return tonumber(serialField(self.serial, 5, 5) or "", 16)
end

function Bookeen:getDeviceColor()
    return serialField(self.serial, 6, 7)
end

function Bookeen:getHardwareRevision()
    return tonumber(serialField(self.serial, 8, 8) or "", 16)
end

function Bookeen:getHardwareOptions()
    return tonumber(serialField(self.serial, 9, 9) or "", 16)
end

local function bookeenEnableWifi(toggle)
    local ok, how, status
    if toggle == 1 then
        logger.info("Bookeen: enabling Wifi")
        ok, how, status = os.execute("./wlan.sh start")
    else
        logger.info("Bookeen: disabling Wifi")
        ok, how, status = os.execute("./wlan.sh stop")
    end
    if type(ok) == "number" then
        return ok == 0
    end
    return ok == true and (status == nil or status == 0)
end

function Bookeen:initNetworkManager(NetworkMgr)
    function NetworkMgr:turnOffWifi(complete_callback)
        os.execute("./restore-wifi-async.sh stop")
        self:releaseIP()
        bookeenEnableWifi(0)
        if complete_callback then
            complete_callback()
        end
    end

    function NetworkMgr:turnOnWifi(complete_callback, interactive)
        if not bookeenEnableWifi(1) then
            logger.warn("Bookeen: wlan.sh start failed")
            return false
        end
        return self:reconnectOrShowNetworkMenu(complete_callback, interactive)
    end

    function NetworkMgr:getNetworkInterfaceName()
        return "wlan0"
    end

    NetworkMgr:setWirelessBackend(
        "wpa_supplicant", {ctrl_interface = "/var/run/wpa_supplicant/wlan0"})

    function NetworkMgr:obtainIP()
        os.execute("./obtain-ip.sh")
    end
    function NetworkMgr:releaseIP()
        os.execute("./release-ip.sh")
    end
    function NetworkMgr:restoreWifiAsync()
        os.execute("./restore-wifi-async.sh")
    end

    NetworkMgr.isWifiOn = NetworkMgr.sysfsWifiOn
    NetworkMgr.isConnected = NetworkMgr.ifHasAnAddress
    NetworkMgr.interface = NetworkMgr:getNetworkInterfaceName()

    -- Same guard kobo has: if we were launched with the module loaded but no
    -- address (a supplicant that died, a lease that was never obtained, or the
    -- stock reader having left the radio on), the state is inconsistent and every
    -- beforeWifiAction would see isWifiOn() and skip connecting. Tear it down so
    -- the first request starts clean.
    if NetworkMgr:isWifiOn() and not NetworkMgr:isConnected() then
        logger.info("Bookeen Wi-Fi: left in an inconsistent state, resetting")
        NetworkMgr:releaseIP()
        bookeenEnableWifi(0)
    end
end


-- input events
function Bookeen:initEventAdjustHooks()
    if self.touch_switch_xy and self.touch_mirrored_x then
        self.input:registerEventAdjustHook(
            self.input.adjustTouchSwitchAxesAndMirrorX,
            (self.screen:getWidth() - 1)
        )
    end
end

function Bookeen:init()
    self.screen = require("ffi/framebuffer_mxcfb"):new{device = self, debug = logger.dbg, is_always_portrait = self.isAlwaysPortrait()}
    self.powerd = require("device/bookeen/powerd"):new{device = self}
    self.input = require("device/input"):new{
        device = self,
        event_map = {
            [407] = "LPgFwd",
            [158] = "LPgBack",
            [139] = "Home",
            [116] = "Power",
            [353] = "Light",
        },
        event_map_adapter = {
            Light = function(ev)
                if self.input:isEvKeyRelease(ev) then
                    self.powerd:toggleFrontlight()
                end
            end,
        }
    }

    if self:getDeviceGeneration() == BOOKEEN_GENERATION_MUSE_OCEAN then
        -- On the Cybook Muse Frontlight and Ocean
        -- pressing the Home button 1 second toggle the frontlight
        self.input.event_map_adapter.Home = function(ev)
            if self.input:isEvKeyRepeat(ev) then
                self.just_toggled_frontlight = 1
                self.powerd:toggleFrontlight()
                if self.powerd:isFrontlightOn() and self.powerd:frontlightIntensity() == 0 then
                    self.powerd:setIntensity(1)
                end
            elseif self.input:isEvKeyRelease(ev) then
                if self.just_toggled_frontlight == 1 then
                   self.just_toggled_frontlight = 0
                else
                   return Event:new("Home")
                end
            end
        end
    end

    self.input:open("/dev/input/event0") -- Face buttons
    self.input:open("/dev/input/event1") -- Power button
    self.input:open("/dev/input/event2") -- Touch screen

    -- Accelerometer. Probe for the node instead of inferring it from the serial:
    -- getDeviceGeneration() reads a single hex digit out of `nvram -s` output, and
    -- gets it wrong whenever nvram is unreadable or the serial is formatted
    -- unexpectedly -- in which case this used to be a *fatal* open() on hardware
    -- that has no accelerometer at all (the Muse/Ocean generation). devtmpfs only
    -- creates nodes that exist, so lfs is authoritative where the serial is not.
    --
    -- Note nothing reads this device yet: hasGSensor is still `no`, so there is no
    -- consumer for its events anywhere in the tree, and the knxjif driver reports
    -- nothing until its `enable` sysfs knob is written anyway. It is opened only so
    -- the fd exists, so failing to open it is in no way fatal.
    if lfs.attributes("/dev/input/event3", "mode") == "char device" then
        self.input:open("/dev/input/event3")
    else
        logger.dbg("Bookeen: no accelerometer at /dev/input/event3, skipping")
    end

    self.input.handleTouchEv = self.input.handleBookeenTouchEvent
    self:initEventAdjustHooks()

    -- Charger/USB uevents, via the forked helper in input-bookeen.h. There is
    -- plenty of room: input.c's inputfds array holds 8 fds and we have used 4.
    -- (The old "no free slots :(" comment here was simply wrong.)
    self.input:open("fake_events")

    local rotation_mode = self.screen.DEVICE_ROTATED_UPRIGHT
    self.screen.native_rotation_mode = rotation_mode
    self.screen.cur_rotation_mode = rotation_mode

    Generic.init(self)
end

function Bookeen:supportsScreensaver() return true end

-- platform/bookeen/koreader.sh copies itself to /tmp and re-execs from there
-- before doing anything else, so these are "what is currently running" versus
-- "what is installed". They differ exactly when an update replaced the launcher
-- underneath us, which reader.lua turns into a prompt to fully exit (a restart
-- alone would keep running the old script, since the loop lives inside it).
--
-- Both paths are md5'd rather than compared by mtime because the OTA extractor
-- preserves timestamps. sumFile returns nil for a missing file, and nil == nil
-- would wrongly read as "up to date", so require an actual hash from the
-- installed copy -- which is also what makes this correct when reader.lua was
-- launched by hand instead of through the launcher: no /tmp/koreader.sh exists,
-- so the comparison is nil vs. a hash, i.e. false... and that would nag on every
-- manual start. Hence the explicit "not running from the launcher" escape.
function Bookeen:isStartupScriptUpToDate()
    if lfs.attributes("/tmp/koreader.sh", "mode") ~= "file" then
        -- Not started via koreader.sh at all; there is nothing to be stale.
        return true
    end
    local md5 = require("ffi/MD5")
    local installed = md5.sumFile("koreader.sh")
    if not installed then
        return true
    end
    return md5.sumFile("/tmp/koreader.sh") == installed
end

function Bookeen:setDateTime(year, month, day, hour, min, sec)
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

function Bookeen:UIManagerReady(uimgr)
    UIManager = uimgr
end

function Bookeen:setEventHandlers(uimgr)
    UIManager.event_handlers.Suspend = function()
        self:onPowerEvent("Suspend")
    end
    UIManager.event_handlers.Resume = function()
        self:onPowerEvent("Resume")
    end
    UIManager.event_handlers.PowerPress = function()
        UIManager:scheduleIn(2, UIManager.poweroff_action)
    end
    UIManager.event_handlers.PowerRelease = function()
        if not UIManager._entered_poweroff_stage then
            UIManager:unschedule(UIManager.poweroff_action)
            if self.screen_saver_mode then
                if self.screen_saver_lock then
                    UIManager.event_handlers.Suspend()
                else
                    UIManager.event_handlers.Resume()
                end
            else
                UIManager.event_handlers.Suspend()
            end
        end
    end
    UIManager.event_handlers.Light = function()
        self:getPowerDevice():toggleFrontlight()
    end
    UIManager.event_handlers.Charging = function()
        self:_beforeCharging()
        -- Plug/unplug wakes the device (the AXP20 IRQ is a wakeup source), so put it back.
        if self.screen_saver_mode and not self.screen_saver_lock then
            UIManager.event_handlers.Suspend()
        end
    end
    UIManager.event_handlers.NotCharging = function()
        self:usbPlugOut()
        self:_afterNotCharging()
        if self.screen_saver_mode and not self.screen_saver_lock then
            UIManager.event_handlers.Suspend()
        end
    end
    UIManager.event_handlers.UsbPlugIn = function()
        self:_beforeCharging()
        if self.screen_saver_mode and not self.screen_saver_lock then
            UIManager.event_handlers.Suspend()
        end
    end
    UIManager.event_handlers.UsbPlugOut = function()
        self:usbPlugOut()
        self:_afterNotCharging()
        if self.screen_saver_mode and not self.screen_saver_lock then
            UIManager.event_handlers.Suspend()
        end
    end
end

function Bookeen:suspend()
    if self:hasWifiToggle() then
        local network_manager = require("ui/network/manager")
        if network_manager:isWifiOn() then
            logger.info("Bookeen suspend: had to kill Wi-Fi")
            network_manager:disableWifi()
        end
    end

    os.execute("sync")

    logger.info("Bookeen suspend: going to sleep . . .")
    local ret = ffiUtil.writeToSysfs("mem", "/sys/power/state")

    if ret then
        logger.info("Bookeen suspend: woke up!")
    else
        logger.warn("Bookeen suspend: the kernel refused to enter suspend!")
    end
end

function Bookeen:resume()
    UIManager:unschedule(self.suspend)
end

function Bookeen:powerOff()
    os.execute("/bin/busybox poweroff")
end

function Bookeen:reboot()
    os.execute("/bin/busybox reboot")
end

return Bookeen
