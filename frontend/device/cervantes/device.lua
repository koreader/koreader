local Generic = require("device/generic/device")
local logger = require("logger")

local function yes() return true end
local function no() return false end

local function getProductId()
    local ntxinfo_pcb = io.popen("/usr/bin/ntxinfo /dev/mmcblk0 | grep pcb | cut -d ':' -f2", "r")
    if not ntxinfo_pcb then return 0 end
    local product_id = ntxinfo_pcb:read("*number") or 0
    ntxinfo_pcb:close()
    return product_id
end

local function isMassStorageSupported()
    -- we rely on 3rd party package for that. It should be installed as part of KOReader prerequisites,
    local safemode_version = io.open("/usr/share/safemode/version", "rb")
    if not safemode_version then return false end
    safemode_version:close()
    return true
end

local Cervantes = Generic:extend{
    model = "Cervantes",
    ota_model = "cervantes",
    isCervantes = yes,
    isAlwaysPortrait = yes,
    isTouchDevice = yes,
    touch_legacy = true, -- SingleTouch input events
    touch_switch_xy = true,
    touch_mirrored_x = true,
    hasOTAUpdates = yes,
    hasFastWifiStatusQuery = yes,
    hasKeys = yes,
    hasWifiManager = yes,
    hasWifiRestore = yes,
    canReboot = yes,
    canPowerOff = yes,
    canSuspend = yes,
    supportsScreensaver = yes,
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
local CervantesTouch = Cervantes:extend{
    model = "CervantesTouch",
    display_dpi = 167,
    hasFrontlight = no,
    hasMultitouch = no,
}
-- Cervantes TouchLight / Fnac Touch Plus
local CervantesTouchLight = Cervantes:extend{
    model = "CervantesTouchLight",
    display_dpi = 167,
    hasMultitouch = no,
}
-- Cervantes 2013 / Fnac Touch Light
local Cervantes2013 = Cervantes:extend{
    model = "Cervantes2013",
    display_dpi = 212,
    hasMultitouch = no,
    --- @fixme: Possibly requires canHWInvert = no, as it seems to be based on a similar board as the Kobo Aura...
}
-- Cervantes 3 / Fnac Touch Light 2
local Cervantes3 = Cervantes:extend{
    model = "Cervantes3",
    display_dpi = 300,
    hasMultitouch = no,
}
-- Cervantes 4
local Cervantes4 = Cervantes:extend{
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
function Cervantes:initEventAdjustHooks()
    if self.touch_switch_xy and self.touch_mirrored_x then
        self.input:registerEventAdjustHook(
            self.input.adjustTouchSwitchAxesAndMirrorX,
            (self.screen:getWidth() - 1)
        )
    end

    if self.touch_legacy then
        self.input.handleTouchEv = self.input.handleTouchEvLegacy
    end
end

function Cervantes:init()
    self.screen = require("ffi/framebuffer_mxcfb"):new{device = self, debug = logger.dbg, is_always_portrait = self.isAlwaysPortrait()}

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
    self.input:open("/dev/input/event0") -- Keys
    self.input:open("/dev/input/event1") -- touchscreen
    self.input:open("fake_events") -- usb events
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
        logger.info("Cervantes: disabling Wi-Fi")
        self:releaseIP()
        os.execute("./disable-wifi.sh")
        if complete_callback then
            complete_callback()
        end
    end
    function NetworkMgr:turnOnWifi(complete_callback, interactive)
        logger.info("Cervantes: enabling Wi-Fi")
        os.execute("./enable-wifi.sh")
        return self:reconnectOrShowNetworkMenu(complete_callback, interactive)
    end
    function NetworkMgr:getNetworkInterfaceName()
        return "eth0"
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
    NetworkMgr.isWifiOn = NetworkMgr.sysfsWifiOn
    NetworkMgr.isConnected = NetworkMgr.ifHasAnAddress
end

-- power functions: suspend, resume, reboot, poweroff
function Cervantes:suspend()
    os.execute("./suspend.sh")
end
function Cervantes:resume()
    os.execute("./resume.sh")
end
function Cervantes:reboot()
    os.execute("sleep 1 && reboot &")
end
function Cervantes:powerOff()
    os.execute("sleep 1 && halt &")
end

-- This method is the same as the one in kobo/device.lua except the sleep cover part.
function Cervantes:setEventHandlers(UIManager)
    -- We do not want auto suspend procedure to waste battery during
    -- suspend. So let's unschedule it when suspending, and restart it after
    -- resume. Done via the plugin's onSuspend/onResume handlers.
    UIManager.event_handlers.Suspend = function()
        self:onPowerEvent("Suspend")
    end
    UIManager.event_handlers.Resume = function()
        self:onPowerEvent("Resume")
    end
    UIManager.event_handlers.PowerPress = function()
        -- Always schedule power off.
        -- Press the power button for 2+ seconds to shutdown directly from suspend.
        UIManager:scheduleIn(2, UIManager.poweroff_action)
    end
    UIManager.event_handlers.PowerRelease = function()
        if not UIManager._entered_poweroff_stage then
            UIManager:unschedule(UIManager.poweroff_action)
            -- resume if we were suspended
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
    -- USB plug events with a power-only charger
    UIManager.event_handlers.Charging = function()
        self:_beforeCharging()
        -- NOTE: Plug/unplug events will wake the device up, which is why we put it back to sleep.
        if self.screen_saver_mode and not self.screen_saver_lock then
           UIManager.event_handlers.Suspend()
        end
    end
    UIManager.event_handlers.NotCharging = function()
        -- We need to put the device into suspension, other things need to be done before it.
        self:usbPlugOut()
        self:_afterNotCharging()
        if self.screen_saver_mode and not self.screen_saver_lock then
           UIManager.event_handlers.Suspend()
        end
    end
    -- USB plug events with a data-aware host
    UIManager.event_handlers.UsbPlugIn = function()
        self:_beforeCharging()
        -- NOTE: Plug/unplug events will wake the device up, which is why we put it back to sleep.
        if self.screen_saver_mode and not self.screen_saver_lock then
            UIManager.event_handlers.Suspend()
        elseif not self.screen_saver_lock then
            -- Potentially start an USBMS session
            local MassStorage = require("ui/elements/mass_storage")
            MassStorage:start()
        end
    end
    UIManager.event_handlers.UsbPlugOut = function()
        -- We need to put the device into suspension, other things need to be done before it.
        self:usbPlugOut()
        self:_afterNotCharging()
        if self.screen_saver_mode and not self.screen_saver_lock then
            UIManager.event_handlers.Suspend()
        elseif not self.screen_saver_lock then
            -- Potentially dismiss the USBMS ConfirmBox
            local MassStorage = require("ui/elements/mass_storage")
            MassStorage:dismiss()
        end
    end
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
