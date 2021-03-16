local Generic = require("device/generic/device") -- <= look at this file!
local logger = require("logger")

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

local EV_ABS = 3
local ABS_X = 00
local ABS_Y = 01
local ABS_MT_POSITION_X = 53
local ABS_MT_POSITION_Y = 54
-- Resolutions from libremarkable src/framebuffer/common.rs
local screen_width = 1404 -- unscaled_size_check: ignore
local screen_height = 1872 -- unscaled_size_check: ignore
local wacom_width = 15725 -- unscaled_size_check: ignore
local wacom_height = 20967 -- unscaled_size_check: ignore
local wacom_scale_x = screen_width / wacom_width
local wacom_scale_y = screen_height / wacom_height
local isRm2, rm_model = getModel()

local Remarkable = Generic:new{
    isRemarkable = yes,
    model = rm_model,
    hasKeys = yes,
    needsScreenRefreshAfterResume = no,
    hasOTAUpdates = yes,
    canReboot = yes,
    canPowerOff = yes,
    isTouchDevice = yes,
    hasFrontlight = no,
    display_dpi = 226,
    -- Despite the SoC supporting it, it's finicky in practice (#6772)
    canHWInvert = no,
    home_dir = "/home/root",
}

local Remarkable1 = Remarkable:new{
    mt_width = 767, -- unscaled_size_check: ignore
    mt_height = 1023, -- unscaled_size_check: ignore
    input_wacom = "/dev/input/event0",
    input_ts = "/dev/input/event1",
    input_buttons = "/dev/input/event2",
    battery_path = "/sys/class/power_supply/bq27441-0/capacity",
    status_path = "/sys/class/power_supply/bq27441-0/status",
}

function Remarkable1:adjustTouchEvent(ev, by)
    if ev.type == EV_ABS then
        -- Mirror X and Y and scale up both X & Y as touch input is different res from
        -- display
        if ev.code == ABS_MT_POSITION_X then
            ev.value = (Remarkable1.mt_width - ev.value) *  by.mt_scale_x
        end
        if ev.code == ABS_MT_POSITION_Y then
            ev.value = (Remarkable1.mt_height - ev.value) * by.mt_scale_y
        end
    end
end

local Remarkable2 = Remarkable:new{
    mt_width = 1403, -- unscaled_size_check: ignore
    mt_height = 1871, -- unscaled_size_check: ignore
    input_wacom = "/dev/input/event1",
    input_ts = "/dev/input/event2",
    input_buttons = "/dev/input/event0",
    battery_path = "/sys/class/power_supply/max77818_battery/capacity",
    status_path = "/sys/class/power_supply/max77818-charger/status",
}

function Remarkable2:adjustTouchEvent(ev, by)
    if ev.type == EV_ABS then
        -- Mirror Y and scale up both X & Y as touch input is different res from
        -- display
        if ev.code == ABS_MT_POSITION_X then
            ev.value = (ev.value) * by.mt_scale_x
        end
        if ev.code == ABS_MT_POSITION_Y then
            ev.value = (Remarkable2.mt_height - ev.value) * by.mt_scale_y
        end
    end
end

local adjustAbsEvt = function(self, ev)
    if ev.type == EV_ABS then
        if ev.code == ABS_X then
            ev.code = ABS_Y
            ev.value = (wacom_height - ev.value) * wacom_scale_y
        elseif ev.code == ABS_Y then
            ev.code = ABS_X
            ev.value = ev.value * wacom_scale_x
        end
    end
end


function Remarkable:init()
    self.screen = require("ffi/framebuffer_mxcfb"):new{device = self, debug = logger.dbg}
    self.powerd = require("device/remarkable/powerd"):new{
        device = self,
        capacity_file = self.battery_path,
        status_file = self.status_path,
    }
    self.input = require("device/input"):new{
        device = self,
        event_map = require("device/remarkable/event_map"),
    }

    self.input.open(self.input_wacom) -- Wacom
    self.input.open(self.input_ts) -- Touchscreen
    self.input.open(self.input_buttons) -- Buttons

    local scalex = screen_width / self.mt_width
    local scaley = screen_height / self.mt_height

    self.input:registerEventAdjustHook(adjustAbsEvt)
    self.input:registerEventAdjustHook(self.adjustTouchEvent, {mt_scale_x=scalex, mt_scale_y=scaley})

    -- USB plug/unplug, battery charge/not charging are generated as fake events
    self.input.open("fake_events")

    local rotation_mode = self.screen.ORIENTATION_PORTRAIT
    self.screen.native_rotation_mode = rotation_mode
    self.screen.cur_rotation_mode = rotation_mode

    Generic.init(self)
end

function Remarkable:supportsScreensaver() return true end

function Remarkable:initNetworkManager(NetworkMgr)
    function NetworkMgr:turnOnWifi(complete_callback)
        os.execute("./enable-wifi.sh")
        self:reconnectOrShowNetworkMenu(function()
            self:connectivityCheck(1, complete_callback)
        end)
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

    NetworkMgr.isWifiOn = function()
        return NetworkMgr:isConnected()
    end
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
    self.screen:clear()
    self.screen:refreshFull()
    os.execute("systemctl poweroff")
end

function Remarkable:reboot()
    os.execute("systemctl reboot")
end

logger.info(string.format("Starting %s", rm_model))

if isRm2 then
    if not os.getenv("RM2FB_SHIM") then
        error("reMarkable2 requires RM2FB to work (https://github.com/ddvk/remarkable2-framebuffer)")
    end
    return Remarkable2
else
    return Remarkable1
end
