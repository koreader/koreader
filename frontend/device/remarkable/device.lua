local Generic = require("device/generic/device") -- <= look at this file!
local logger = require("logger")

local function yes() return true end
local function no() return false end

local Remarkable = Generic:new{
    isRemarkable = yes,
    model = "reMarkable",
    hasKeys = yes,
    needsScreenRefreshAfterResume = no,
    hasOTAUpdates = yes,
    canReboot = yes,
    canPowerOff = yes,
    isTouchDevice = yes,
    invertX = yes,
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
    -- TODO: older firmware doesn't have the -0 on the end of the file path
    battery_path = "/sys/class/power_supply/bq27441-0/capacity",
    status_path = "/sys/class/power_supply/bq27441-0/status",
}

local Remarkable2 = Remarkable:new{
    model = "reMarkable 2",
    home_dir = "/mnt/root",
    invertX = no,
    mt_width = 1403,
    mt_height = 1871,
    input_wacom = "/dev/input/event1",
    input_ts = "/dev/input/event2",
    input_buttons = "/dev/input/event0",
    battery_path = "/sys/class/power_supply/max77818_battery/capacity",
    status_path = "/sys/class/power_supply/max77818-charger/status",
}


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
local TimeVal = require('ui/timeval')

local adjustAbsEvt = function(self, ev)
    -- for the rm2
    ev.time = TimeVal:now()
    if ev.type == EV_ABS then
        -- The Wacom input layer is non-multi-touch and
        -- uses its own scaling factor.
        -- The X and Y coordinates are swapped, and the (real) Y
        -- coordinate has to be inverted.
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

    self.input:registerEventAdjustHook(adjustAbsEvt)

    if self.invertX() then
        self.input:registerEventAdjustHook(self.input.adjustTouchMirrorX, self.mt_width)
    end

    local mt_scale_x = self.mt_width / screen_width
    local mt_scale_y = self.mt_height / screen_height

    self.input:registerEventAdjustHook(self.input.adjustTouchMirrorY, self.mt_height)
    self.input:registerEventAdjustHook(self.input.adjustTouchScale, {x=mt_scale_x, y=mt_scale_y})

    -- USB plug/unplug, battery charge/not charging are generated as fake events
    self.input.open("fake_events")

    local rotation_mode = self.screen.ORIENTATION_PORTRAIT
    self.screen.native_rotation_mode = rotation_mode
    self.screen.cur_rotation_mode = rotation_mode

    Generic.init(self)
end

function Remarkable:supportsScreensaver() return true end

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

function Remarkable:_clearScreen()
    self.screen:clear()
    self.screen:refreshFull()
end

function Remarkable:suspend()
    self:_clearScreen()
    os.execute("systemctl suspend")
end

function Remarkable:resume()
end

function Remarkable:powerOff()
    self:_clearScreen()
    os.execute("systemctl poweroff")
end

function Remarkable:reboot()
    self:_clearScreen()
    os.execute("systemctl reboot")
end

local f = io.open("/sys/devices/soc0/machine")
if not f then error("missing sysfs entry for a remarkable") end

local deviceType = f:read("*all") 
if deviceType == "reMarkable 2.0\n" then
    logger.info("rm2 ", deviceType)
    if not os.getenv("RM2FB_SHIM") then
        error("reMarkable2 requires RM2FB to work")
    end

    return Remarkable2
else 
    return Remarkable1
end
