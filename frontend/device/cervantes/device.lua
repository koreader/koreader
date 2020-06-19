local Generic = require("device/generic/device")
local TimeVal = require("ui/timeval")
local logger = require("logger")

local function yes() return true end
local function no() return false end

local function getProductId()
    local ntxinfo_pcb = io.popen("/usr/bin/ntxinfo /dev/mmcblk0 | grep pcb | cut -d ':' -f2", "r")
    if not ntxinfo_pcb then return 0 end
    local product_id = tonumber(ntxinfo_pcb:read()) or 0
    ntxinfo_pcb:close()
    return product_id
end

local function isConnected()
    -- read carrier state from sysfs (for eth0)
    local file = io.open("/sys/class/net/eth0/carrier", "rb")

    -- file exists while wifi module is loaded.
    if not file then return 0 end

    -- 0 means not connected, 1 connected
    local out = file:read("*all")
    file:close()

    -- strip NaN from file read (ie: line endings, error messages)
    local carrier
    if type(out) ~= "number" then
        carrier = tonumber(out)
    else
        carrier = out
    end

    -- finally return if we're connected or not
    if type(carrier) == "number" then
        return carrier
    else
        return 0
    end
end

local function isMassStorageSupported()
    -- we rely on 3rd party package for that. It should be installed as part of KOReader prerequisites,
    local safemode_version = io.open("/usr/share/safemode/version", "rb")
    if not safemode_version then return false end
    safemode_version:close()
    return true
end

local Cervantes = Generic:new{
    model = "Cervantes",
    isCervantes = yes,
    isAlwaysPortrait = yes,
    isTouchDevice = yes,
    touch_legacy = true, -- SingleTouch input events
    touch_switch_xy = true,
    touch_mirrored_x = true,
    touch_probe_ev_epoch_time = true,
    hasOTAUpdates = yes,
    hasKeys = yes,
    hasWifiManager = yes,
    canReboot = yes,
    canPowerOff = yes,
    home_dir = "/mnt/public",

    -- do we support usb mass storage?
    canToggleMassStorage = function() return isMassStorageSupported() end,

    -- all devices, except the original Cervantes Touch, have frontlight
    hasFrontlight = yes,

    -- currently only Cervantes 4 has coloured frontlight
    hasNaturalLight = no,
    hasNaturalLightMixer = no,

    -- HW inversion is generally safe on Cervantes, except on a few boards/kernels
    canHWInvert = yes,
}
-- Cervantes Touch
local CervantesTouch = Cervantes:new{
    model = "CervantesTouch",
    display_dpi = 167,
    hasFrontlight = no,
    hasMultitouch = no,
}
-- Cervantes TouchLight / Fnac Touch Plus
local CervantesTouchLight = Cervantes:new{
    model = "CervantesTouchLight",
    display_dpi = 167,
    hasMultitouch = no,
}
-- Cervantes 2013 / Fnac Touch Light
local Cervantes2013 = Cervantes:new{
    model = "Cervantes2013",
    display_dpi = 212,
    hasMultitouch = no,
    --- @fixme: Possibly requires canHWInvert = no, as it seems to be based on a similar board as the Kobo Aura...
}
-- Cervantes 3 / Fnac Touch Light 2
local Cervantes3 = Cervantes:new{
    model = "Cervantes3",
    display_dpi = 300,
    hasMultitouch = no,
}
-- Cervantes 4
local Cervantes4 = Cervantes:new{
    model = "Cervantes4",
    display_dpi = 300,
    hasNaturalLight = yes,
    frontlight_settings = {
        frontlight_white = "/sys/class/backlight/mxc_msp430_fl.0/brightness",
        frontlight_mixer = "/sys/class/backlight/lm3630a_led/color",
        nl_min = 0,
        nl_max = 10,
        nl_inverted = true,
    },
}

-- input events
local probeEvEpochTime
-- this function will update itself after the first touch event
probeEvEpochTime = function(self, ev)
    local now = TimeVal:now()
    -- This check should work as long as main UI loop is not blocked for more
    -- than 10 minute before handling the first touch event.
    if ev.time.sec <= now.sec - 600 then
        -- time is seconds since boot, force it to epoch
        probeEvEpochTime = function(_, _ev)
            _ev.time = TimeVal:now()
        end
        ev.time = now
    else
        -- time is already epoch time, no need to do anything
        probeEvEpochTime = function(_, _) end
    end
end
function Cervantes:initEventAdjustHooks()
    if self.touch_switch_xy then
        self.input:registerEventAdjustHook(self.input.adjustTouchSwitchXY)
    end
    if self.touch_mirrored_x then
        self.input:registerEventAdjustHook(
            self.input.adjustTouchMirrorX,
            self.screen:getWidth()
        )
    end
    if self.touch_probe_ev_epoch_time then
        self.input:registerEventAdjustHook(function(_, ev)
            probeEvEpochTime(_, ev)
        end)
    end

    if self.touch_legacy then
        self.input.handleTouchEv = self.input.handleTouchEvLegacy
    end
end

-- Make sure the C BB cannot be used on devices with unsafe HW inversion, as otherwise NightMode would be ineffective.
function Cervantes:blacklistCBB()
    local ffi = require("ffi")
    local dummy = require("ffi/posix_h")
    local C = ffi.C

    -- NOTE: canUseCBB is never no on Cervantes ;).
    if not self:canUseCBB() or not self:canHWInvert() then
        logger.info("Blacklisting the C BB on this device")
        if ffi.os == "Windows" then
            C._putenv("KO_NO_CBB=true")
        else
            C.setenv("KO_NO_CBB", "true", 1)
        end
        -- Enforce the global setting, too, so the Dev menu is accurate...
        G_reader_settings:saveSetting("dev_no_c_blitter", true)
    end
end

function Cervantes:init()
    -- Blacklist the C BB before the first BB require...
    self:blacklistCBB()

    self.screen = require("ffi/framebuffer_mxcfb"):new{device = self, debug = logger.dbg}

    -- Automagically set this so we never have to remember to do it manually ;p
    if self:hasNaturalLight() and self.frontlight_settings and self.frontlight_settings.frontlight_mixer then
        self.hasNaturalLightMixer = yes
    end

    self.powerd = require("device/cervantes/powerd"):new{device = self}
    self.input = require("device/input"):new{
        device = self,
        event_map = {
            [61] = "Home",
            [116] = "Power",
        }
    }
    self.input.open("/dev/input/event0") -- Keys
    self.input.open("/dev/input/event1") -- touchscreen
    self.input.open("fake_events") -- usb events
    self:initEventAdjustHooks()
    Generic.init(self)
end

function Cervantes:setDateTime(year, month, day, hour, min, sec)
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

function Cervantes:saveSettings()
    self.powerd:saveSettings()
end

-- wireless
function Cervantes:initNetworkManager(NetworkMgr)
    function NetworkMgr:turnOffWifi(complete_callback)
        logger.info("Cervantes: disabling WiFi")
        self:releaseIP()
        os.execute("./disable-wifi.sh")
        if complete_callback then
            complete_callback()
        end
    end
    function NetworkMgr:turnOnWifi(complete_callback)
        logger.info("Cervantes: enabling WiFi")
        os.execute("./enable-wifi.sh")
        self:reconnectOrShowNetworkMenu(complete_callback)
    end
    NetworkMgr:setWirelessBackend("wpa_supplicant", {ctrl_interface = "/var/run/wpa_supplicant/eth0"})
    function NetworkMgr:obtainIP()
        os.execute("./obtain-ip.sh")
    end
    function NetworkMgr:releaseIP()
        os.execute("./release-ip.sh")
    end
    function NetworkMgr:restoreWifiAsync()
        os.execute("./restore-wifi-async.sh")
    end
    function NetworkMgr:isWifiOn()
        return 1 == isConnected()
    end
end

-- screensaver
function Cervantes:supportsScreensaver()
    return true
end
function Cervantes:intoScreenSaver()
    local Screensaver = require("ui/screensaver")
    if self.screen_saver_mode == false then
        Screensaver:show()
    end
    self.powerd:beforeSuspend()
    self.screen_saver_mode = true
end
function Cervantes:outofScreenSaver()
    if self.screen_saver_mode == true then
        local Screensaver = require("ui/screensaver")
        Screensaver:close()
        local UIManager = require("ui/uimanager")
        UIManager:nextTick(function() UIManager:setDirty("all", "full") end)
    end
    self.powerd:afterResume()
    self.screen_saver_mode = false
end

-- power functions: suspend, resume, reboot, poweroff
function Cervantes:suspend()
    os.execute("./suspend.sh")
end
function Cervantes:resume()
    os.execute("./resume.sh")
end
function Cervantes:reboot()
    os.execute("reboot")
end
function Cervantes:powerOff()
    os.execute("halt")
end

-------------- device probe ------------
local product_id = getProductId()

if product_id == 22 then
    return CervantesTouch
elseif product_id == 23 then
    return CervantesTouchLight
elseif product_id == 33 then
    return Cervantes2013
elseif product_id == 51 then
    return Cervantes3
elseif product_id == 68 then
    return Cervantes4
else
    error("unrecognized Cervantes: board id " .. product_id)
end
