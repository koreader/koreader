local Generic = require("device/generic/device") -- <= look at this file!
local PluginShare = require("pluginshare")
local logger = require("logger")
local time = require("ui/time")
local ffi = require("ffi")
local C = ffi.C
require("ffi/linux_input_h")

local function yes() return true end
local function no() return false end

-- returns isRm2, device_model
local function getModel()
    local f = io.open("/sys/devices/soc0/machine")
    if not f then
        error("missing sysfs entry for a remarkable")
    end
    local model = f:read("*line")
    f:close()
    return model == "reMarkable 2.0", model
end

-- Resolutions from libremarkable src/framebuffer/common.rs
local screen_width = 1404 -- unscaled_size_check: ignore
local screen_height = 1872 -- unscaled_size_check: ignore
local wacom_width = 15725 -- unscaled_size_check: ignore
local wacom_height = 20967 -- unscaled_size_check: ignore
local wacom_scale_x = screen_width / wacom_width
local wacom_scale_y = screen_height / wacom_height
local isRm2, rm_model = getModel()

local Remarkable = Generic:extend{
    isRemarkable = yes,
    model = rm_model,
    ota_model = "remarkable",
    hasKeys = yes,
    needsScreenRefreshAfterResume = no,
    hasOTAUpdates = yes,
    hasFastWifiStatusQuery = yes,
    hasWifiManager = yes,
    canReboot = yes,
    canPowerOff = yes,
    canSuspend = yes,
    isTouchDevice = yes,
    hasFrontlight = no,
    hasSystemFonts = yes,
    display_dpi = 226,
    -- Despite the SoC supporting it, it's finicky in practice (#6772)
    canHWInvert = no,
    home_dir = "/home/root",
}

local Remarkable1 = Remarkable:extend{
    mt_width = 767, -- unscaled_size_check: ignore
    mt_height = 1023, -- unscaled_size_check: ignore
    input_wacom = "/dev/input/event0",
    input_ts = "/dev/input/event1",
    input_buttons = "/dev/input/event2",
    battery_path = "/sys/class/power_supply/bq27441-0/capacity",
    status_path = "/sys/class/power_supply/bq27441-0/status",
}

function Remarkable1:adjustTouchEvent(ev, by)
    if ev.type == C.EV_ABS then
        -- Mirror X and Y and scale up both X & Y as touch input is different res from display
        if ev.code == C.ABS_MT_POSITION_X then
            ev.value = (Remarkable1.mt_width - ev.value) *  by.mt_scale_x
        end
        if ev.code == C.ABS_MT_POSITION_Y then
            ev.value = (Remarkable1.mt_height - ev.value) * by.mt_scale_y
        end
    end
end

local Remarkable2 = Remarkable:extend{
    mt_width = 1403, -- unscaled_size_check: ignore
    mt_height = 1871, -- unscaled_size_check: ignore
    input_wacom = "/dev/input/event1",
    input_ts = "/dev/input/event2",
    input_buttons = "/dev/input/event0",
    battery_path = "/sys/class/power_supply/max77818_battery/capacity",
    status_path = "/sys/class/power_supply/max77818-charger/status",
}

function Remarkable2:adjustTouchEvent(ev, by)
    if ev.type == C.EV_ABS then
        -- Mirror Y and scale up both X & Y as touch input is different res from display
        if ev.code == C.ABS_MT_POSITION_X then
            ev.value = (ev.value) * by.mt_scale_x
        end
        if ev.code == C.ABS_MT_POSITION_Y then
            ev.value = (Remarkable2.mt_height - ev.value) * by.mt_scale_y
        end
    end

    -- Wacom uses CLOCK_REALTIME, but the Touchscreen spits out frozen timestamps.
    -- Inject CLOCK_MONOTONIC timestamps at the end of every input frame in order to have consistent gesture detection across input devices.
    -- c.f., #7536
    if ev.type == C.EV_SYN and ev.code == C.SYN_REPORT then
        local sec, usec = time.split_s_us(time.now())
        ev.time = {
            sec = sec,
            usec = usec
        }
    end
end

local adjustAbsEvt = function(self, ev)
    if ev.type == C.EV_ABS then
        if ev.code == C.ABS_X then
            ev.code = C.ABS_Y
            ev.value = (wacom_height - ev.value) * wacom_scale_y
        elseif ev.code == C.ABS_Y then
            ev.code = C.ABS_X
            ev.value = ev.value * wacom_scale_x
        end
    end
end

function Remarkable:init()
    local oxide_running = os.execute("systemctl is-active --quiet tarnish") == 0
    logger.info(string.format("Oxide running?: %s", oxide_running))

    -- experiment
    -- logger.info("PPID:")
    -- local parent_process = os.execute("echo $PPID")
    -- os.execute("ps | grep $PPID")
    -- logger.info(string.format("parent process is oxide?: %s", parent_process_is_oxide))

    self.screen = require("ffi/framebuffer_mxcfb"):new{device = self, debug = logger.dbg}
    self.powerd = require("device/remarkable/powerd"):new{
        device = self,
        capacity_file = self.battery_path,
        status_file = self.status_path,
    }

    local event_map = dofile("frontend/device/remarkable/event_map.lua")
    -- If we are launched while Oxide is running, remove Power from the event map
    if oxide_running then
        event_map[116] = nil
    end

    self.input = require("device/input"):new{
        device = self,
        event_map = dofile("frontend/device/remarkable/event_map.lua"),
        wacom_protocol = true,
    }

    -- Assume input stuff is saner on mainline kernels...
    -- (c.f., https://github.com/koreader/koreader/issues/10012)
    local is_mainline = false
    --- @fixme: Find a better way to discriminate mainline from stock...
    local std_out = io.popen("uname -r", "r")
    if std_out then
        local release = std_out:read("*line")
        std_out:close()
        release = release:match("^(%d+%.%d+)%.%d+.*$")
        release = tonumber(release)
        if release and release >= 6.2 then
            is_mainline = true
        end
    end

    if is_mainline then
        self.input_wacom = "/dev/input/by-path/platform-30a20000.i2c-event-mouse"
        self.input_buttons = "/dev/input/by-path/platform-30370000.snvs:snvs-powerkey-event"
        self.input_ts = "/dev/input/touchscreen0"
    end

    self.input:open(self.input_wacom) -- Wacom
    self.input:open(self.input_ts) -- Touchscreen
    self.input:open(self.input_buttons) -- Buttons

    local scalex = screen_width / self.mt_width
    local scaley = screen_height / self.mt_height

    if is_mainline then
        -- NOTE: The panel sends *both* ABS_MT_ & ABS_ coordinates, while the pen only sends ABS_ coordinates.
        --       Since we have to apply *different* mangling to each of them,
        --       we use a custom input handler that'll ignore ABS_ coordinates from the panel...
        self.input.handleTouchEv = self.input.handleMixedTouchEv
        local mt_height = self.mt_height
        local mainlineInputMangling = function(this, ev)
            if ev.type == C.EV_ABS then
                -- Mirror Y for the touch panel
                if ev.code == C.ABS_MT_POSITION_Y then
                    ev.value = mt_height - ev.value
                -- Handle the Wacom pen
                elseif ev.code == C.ABS_X then
                    ev.code = C.ABS_Y
                    ev.value = (wacom_height - ev.value) * wacom_scale_y
                elseif ev.code == C.ABS_Y then
                    ev.code = C.ABS_X
                    ev.value = ev.value * wacom_scale_x
                end
            end
        end
        self.input:registerEventAdjustHook(mainlineInputMangling)
    else
        self.input:registerEventAdjustHook(adjustAbsEvt)
        self.input:registerEventAdjustHook(self.adjustTouchEvent, {mt_scale_x=scalex, mt_scale_y=scaley})
    end

    -- USB plug/unplug, battery charge/not charging are generated as fake events
    self.input:open("fake_events")

    local rotation_mode = self.screen.DEVICE_ROTATED_UPRIGHT
    self.screen.native_rotation_mode = rotation_mode
    self.screen.cur_rotation_mode = rotation_mode

    if oxide_running then
        -- Disable autosuspend on this device
        PluginShare.pause_auto_suspend = true
    end

    Generic.init(self)
end

function Remarkable:supportsScreensaver() return true end

function Remarkable:initNetworkManager(NetworkMgr)
    function NetworkMgr:turnOnWifi(complete_callback, interactive)
        os.execute("./enable-wifi.sh")
        return self:reconnectOrShowNetworkMenu(complete_callback, interactive)
    end

    function NetworkMgr:turnOffWifi(complete_callback)
        os.execute("./disable-wifi.sh")
        if complete_callback then
            complete_callback()
        end
    end

    function NetworkMgr:getNetworkInterfaceName()
        return "wlan0"
    end

    NetworkMgr:setWirelessBackend("wpa_supplicant", {ctrl_interface = "/var/run/wpa_supplicant/wlan0"})

    NetworkMgr.isWifiOn = NetworkMgr.sysfsWifiOn
    NetworkMgr.isConnected = NetworkMgr.ifHasAnAddress
end

function Remarkable:setDateTime(year, month, day, hour, min, sec)
    if hour == nil or min == nil then return true end
    local command
    if year and month and day then
        command = string.format("timedatectl set-time '%d-%d-%d %d:%d:%d'", year, month, day, hour, min, sec)
    else
        command = string.format("timedatectl set-time '%d:%d'",hour, min)
    end
    return os.execute(command) == 0
end

function Remarkable:resume()
end

function Remarkable:suspend()
    os.execute("./disable-wifi.sh")
    os.execute("systemctl suspend")
end

function Remarkable:powerOff()
    os.execute("systemctl poweroff")
end

function Remarkable:reboot()
    os.execute("systemctl reboot")
end

logger.info(string.format("Starting %s", rm_model))

function Remarkable:getDefaultCoverPath()
    return "/usr/share/remarkable/poweroff.png"
end

function Remarkable:setEventHandlers(UIManager)
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
end

if isRm2 then
    if not os.getenv("RM2FB_SHIM") then
        error("reMarkable2 requires RM2FB to work (https://github.com/ddvk/remarkable2-framebuffer)")
    end
    return Remarkable2
else
    return Remarkable1
end
