local Generic = require("device/generic/device") -- <= look at this file!
local PluginShare = require("pluginshare")
local UIManager
local ffi = require("ffi")
local logger = require("logger")

local C = ffi.C
require("ffi/linux_input_h")

local function yes() return true end
local function no() return false end

local SonyPRSTUX = Generic:extend{
    model = "Sony PRSTUX",
    isSonyPRSTUX = yes,
    hasKeys = yes,
    hasOTAUpdates = no,
    hasWifiManager = yes,
    canReboot = yes,
    canPowerOff = yes,
    canSuspend = yes,
    usbPluggedIn = false,
    home_dir = nil,
}



-- sony's driver does not inform of ID, so we overwrite the TOUCH_MAJOR
-- event to fake an ID event. a width == 0 means the finger was lifted.
-- after all events are received, we reset the counter

local next_touch_id = 0
local adjustTouchEvt = function(self, ev)
    if ev.type == C.EV_ABS and ev.code == C.ABS_MT_TOUCH_MAJOR then
        ev.code = C.ABS_MT_TRACKING_ID
        if ev.value ~= 0 then
            ev.value = next_touch_id
        else
            ev.value = -1
        end

        next_touch_id = next_touch_id + 1

        logger.dbg("adjusted id: ", ev.value)
    elseif ev.type == C.EV_SYN and ev.code == C.SYN_REPORT then
        next_touch_id = 0
        logger.dbg("reset id: ", ev.code, ev.value)
        ev.code = C.SYN_MT_REPORT
    elseif ev.type == C.EV_SYN and ev.code == C.SYN_MT_REPORT then
        ev.code = C.SYN_REPORT
    end
end

function SonyPRSTUX:init()
    self.screen = require("ffi/framebuffer_mxcfb"):new{device = self, debug = logger.dbg}
    self.powerd = require("device/sony-prstux/powerd"):new{device = self}
    self.input = require("device/input"):new{
        device = self,
        event_map = dofile("frontend/device/sony-prstux/event_map.lua"),
    }

    self.input:open("/dev/input/event0") -- Keys
    self.input:open("/dev/input/event1") -- touchscreen
    self.input:open("/dev/input/event2") -- power button
    self.input:open("fake_events") -- usb plug-in/out and charging/not-charging
    self.input:registerEventAdjustHook(adjustTouchEvt)

    local rotation_mode = self.screen.DEVICE_ROTATED_COUNTER_CLOCKWISE
    self.screen.native_rotation_mode = rotation_mode
    self.screen.cur_rotation_mode = rotation_mode

    Generic.init(self)
end

function SonyPRSTUX:supportsScreensaver() return true end

function SonyPRSTUX:setDateTime(year, month, day, hour, min, sec)
    if hour == nil or min == nil then return true end
    local command
    if year and month and day then
        command = string.format("date -s '%d-%d-%d %d:%d:%d'", year, month, day, hour, min, sec)
    else
        command = string.format("date -s '%d:%d'",hour, min)
    end
    if os.execute(command) == 0 then
        os.execute("hwclock -u -w")
        return true
    else
        return false
    end
end

function SonyPRSTUX:intoScreenSaver()
    local Screensaver = require("ui/screensaver")
    if not self.screen_saver_mode then
        Screensaver:setup()
        Screensaver:show()
    end
    self.powerd:beforeSuspend()
end

function SonyPRSTUX:outofScreenSaver()
    if self.screen_saver_mode then
        local Screensaver = require("ui/screensaver")
        Screensaver:close()
        UIManager:nextTick(function() UIManager:setDirty("all", "full") end)
    end
    self.powerd:afterResume()
end

function SonyPRSTUX:suspend()
    os.execute("./suspend.sh")
end

function SonyPRSTUX:resume()
    os.execute("./resume.sh")
end

function SonyPRSTUX:powerOff()
    os.execute("sleep 1 && poweroff &")
end

function SonyPRSTUX:reboot()
    os.execute("sleep 1 && reboot &")
end

function SonyPRSTUX:usbPlugIn()
    self.usb_plugged_in = true
    PluginShare.pause_auto_suspend = true
end

function SonyPRSTUX:usbPlugOut()
    self.usb_plugged_in = false
    PluginShare.pause_auto_suspend = false
end

function SonyPRSTUX:usbPluggedIn()
    return self.usb_plugged_in
end

function SonyPRSTUX:initNetworkManager(NetworkMgr)
    function NetworkMgr:turnOffWifi(complete_callback)
       self:releaseIP()
       os.execute("./set-wifi.sh off")
       if complete_callback then
           complete_callback()
       end
    end

    function NetworkMgr:turnOnWifi(complete_callback, interactive)
       os.execute("./set-wifi.sh on")
       return self:reconnectOrShowNetworkMenu(complete_callback, interactive)
    end

    function NetworkMgr:getNetworkInterfaceName()
        return "wlan0"
    end

    NetworkMgr:setWirelessBackend("wpa_supplicant", {ctrl_interface = "/var/run/wpa_supplicant/wlan0"})

    function NetworkMgr:obtainIP()
        self:releaseIP()
        os.execute("dhclient wlan0")
    end

    function NetworkMgr:releaseIP()
        logger.info("killing dhclient")
        os.execute("dhclient -x wlan0")
    end

    --[[
    function NetworkMgr:isWifiOn()
        return 0 == os.execute("wmiconfig -i wlan0 --wlan query | grep -q enabled")
    end
    --]]
    NetworkMgr.isWifiOn = NetworkMgr.sysfsWifiOn
    NetworkMgr.isConnected = NetworkMgr.ifHasAnAddress
end


function SonyPRSTUX:getSoftwareVersion()
    return ffi.string("PRSTUX")
end

function SonyPRSTUX:getDeviceModel()
    return ffi.string("PRS-T2")
end

function SonyPRSTUX:UIManagerReady(uimgr)
    UIManager = uimgr
end

function SonyPRSTUX:setEventHandlers(uimgr)
    UIManager.event_handlers.Suspend = function()
        self:intoScreenSaver()
        self:suspend()
    end
    UIManager.event_handlers.Resume = function()
        self:resume()
        self:outofScreenSaver()
    end
    UIManager.event_handlers.PowerPress = function()
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
    UIManager.event_handlers.Charging = function()
        self:_beforeCharging()
    end
    UIManager.event_handlers.NotCharging = function()
        self:_afterNotCharging()
    end
    UIManager.event_handlers.UsbPlugIn = function()
        if self.screen_saver_mode and not self.screen_saver_lock then
            self:resume()
            self:outofScreenSaver()
        end
        self:usbPlugIn()
    end
    UIManager.event_handlers.UsbPlugOut = function()
        self:usbPlugOut()
    end
end

-- For Sony PRS-T2
local SonyPRSTUX_T2 = SonyPRSTUX:extend{
    isTouchDevice = yes,
    hasKeys = yes,
    hasFrontlight = no,
    display_dpi = 166,
}

logger.info("SoftwareVersion: ", SonyPRSTUX:getSoftwareVersion())

local codename = SonyPRSTUX:getDeviceModel()

if codename == "PRS-T2" then
    return SonyPRSTUX_T2
else
    error("unrecognized Sony PRSTUX model " .. codename)
end
