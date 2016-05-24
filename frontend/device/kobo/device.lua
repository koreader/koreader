local Generic = require("device/generic/device")
local TimeVal = require("ui/timeval")
local Geom = require("ui/geometry")
local dbg = require("dbg")

local function yes() return true end

local Kobo = Generic:new{
    model = "Kobo",
    isKobo = yes,
    isTouchDevice = yes, -- all of them are

    -- most Kobos have X/Y switched for the touch screen
    touch_switch_xy = true,
    -- most Kobos have also mirrored X coordinates
    touch_mirrored_x = true,
    -- enforce protrait mode on Kobos:
    isAlwaysPortrait = yes,
    -- the internal storage mount point users can write to
    internal_storage_mount_point = "/mnt/onboard/"
}

-- TODO: hasKeys for some devices?

-- Kobo Touch:
local KoboTrilogy = Kobo:new{
    model = "Kobo_trilogy",
    needsTouchScreenProbe = yes,
    touch_switch_xy = false,
    -- Some Kobo Touch models' kernel does not generate touch event with epoch
    -- timestamp. This flag will probe for those models and setup event adjust
    -- hook accordingly
    touch_probe_ev_epoch_time = true,
    hasKeys = yes,
}

-- Kobo Mini:
local KoboPixie = Kobo:new{
    model = "Kobo_pixie",
    display_dpi = 200,
    -- bezel:
    viewport = Geom:new{x=0, y=2, w=596, h=794},
}

-- Kobo Aura H2O:
local KoboDahlia = Kobo:new{
    model = "Kobo_dahlia",
    hasFrontlight = yes,
    touch_phoenix_protocol = true,
    display_dpi = 265,
    -- the bezel covers the top 11 pixels:
    viewport = Geom:new{x=0, y=11, w=1080, h=1429},
}

-- Kobo Aura HD:
local KoboDragon = Kobo:new{
    model = "Kobo_dragon",
    hasFrontlight = yes,
    display_dpi = 265,
}

-- Kobo Glo:
local KoboKraken = Kobo:new{
    model = "Kobo_kraken",
    hasFrontlight = yes,
    display_dpi = 212,
}

-- Kobo Aura:
local KoboPhoenix = Kobo:new{
    model = "Kobo_phoenix",
    hasFrontlight = yes,
    touch_phoenix_protocol = true,
    display_dpi = 212,
    -- the bezel covers 12 pixels at the bottom:
    viewport = Geom:new{x=0, y=0, w=758, h=1012},
}

-- Kobo Glo HD:
local KoboAlyssum = Kobo:new{
    model = "Kobo_alyssum",
    hasFrontlight = yes,
    touch_phoenix_protocol = true,
    touch_alyssum_protocol = true,
    display_dpi = 300,
}

-- Kobo Touch 2.0:
local KoboPika = Kobo:new{
    model = "Kobo_pika",
    touch_phoenix_protocol = true,
    touch_alyssum_protocol = true,
}

function Kobo:init()
    self.screen = require("ffi/framebuffer_mxcfb"):new{device = self, debug = dbg}
    self.powerd = require("device/kobo/powerd"):new{device = self}
    self.input = require("device/input"):new{
        device = self,
        event_map = {
            [90] = "Light",
            [102] = "Home",
            [116] = "Power",
        }
    }

    if not G_reader_settings:readSetting("ignore_power_sleepcover") then
        self.input.event_map[59] = "Power_SleepCover"
    end

    Generic.init(self)

    self.input.open("/dev/input/event0") -- Light button and sleep slider
    self.input.open("/dev/input/event1")

    if not self.needsTouchScreenProbe() then
        self:initEventAdjustHooks()
    else
        -- if touch probe is required, we postpone EventAdjustHook
        -- initialization to when self:touchScreenProbe is called
        self.touchScreenProbe = function()
            -- if user has not set KOBO_TOUCH_MIRRORED yet
            if KOBO_TOUCH_MIRRORED == nil then
                local switch_xy = G_reader_settings:readSetting("kobo_touch_switch_xy")
                -- and has no probe before
                if switch_xy == nil then
                    local TouchProbe = require("utils/kobo_touch_probe")
                    local UIManager = require("ui/uimanager")
                    UIManager:show(TouchProbe:new{})
                    UIManager:run()
                    -- assuming TouchProbe sets kobo_touch_switch_xy config
                    switch_xy = G_reader_settings:readSetting("kobo_touch_switch_xy")
                end
                self.touch_switch_xy = switch_xy
            end
            self:initEventAdjustHooks()
        end
    end
end

local probeEvEpochTime
-- this function will update itself after the first touch event
probeEvEpochTime = function(self, ev)
    -- this check should work if the device has uptime less than 10 years
    if ev.time.sec <= 315569260 then
        -- time is seconds since boot, force it to epoch
        probeEvEpochTime = function(_, _ev)
            _ev.time = TimeVal:now()
        end
        probeEvEpochTime(nil, ev)
    else
        -- time is already epoch time, no need to do anything
        probeEvEpochTime = function(_, _) end
    end
end

local ABS_MT_TRACKING_ID = 57
local EV_ABS = 3
local adjustTouchAlyssum = function(self, ev)
    ev.time = TimeVal:now()
    if ev.type == EV_ABS and ev.code == ABS_MT_TRACKING_ID then
        ev.value = ev.value - 1
    end
end

function Kobo:initEventAdjustHooks()
    -- it's called KOBO_TOUCH_MIRRORED in defaults.lua, but what it
    -- actually did in its original implementation was to switch X/Y.
    -- NOTE: for kobo touch, adjustTouchSwitchXY needs to be called before
    -- adjustTouchMirrorX
    if (self.touch_switch_xy and not KOBO_TOUCH_MIRRORED)
            or (not self.touch_switch_xy and KOBO_TOUCH_MIRRORED)
    then
        self.input:registerEventAdjustHook(self.input.adjustTouchSwitchXY)
    end

    if self.touch_mirrored_x then
        self.input:registerEventAdjustHook(
            self.input.adjustTouchMirrorX,
            -- FIXME: what if we change the screen protrait mode?
            self.screen:getWidth()
        )
    end

    if self.touch_alyssum_protocol then
        self.input:registerEventAdjustHook(adjustTouchAlyssum)
    end

    if self.touch_probe_ev_epoch_time then
        self.input:registerEventAdjustHook(function(_, ev)
            probeEvEpochTime(_, ev)
        end)
    end

    if self.touch_phoenix_protocol then
        self.input.handleTouchEv = self.input.handleTouchEvPhoenix
    end
end

function Kobo:getCodeName()
    -- Try to get it from the env first
    local codename = os.getenv("PRODUCT")
    -- If that fails, run the script ourselves
    if not codename then
        local std_out = io.popen("/bin/kobo_config.sh 2>/dev/null", "r")
        codename = std_out:read()
        std_out:close()
    end
    return codename
end

function Kobo:getFirmwareVersion()
    local version_file = io.open("/mnt/onboard/.kobo/version", "r")
    self.firmware_rev = string.sub(version_file:read(),24,28)
    version_file:close()
end

function Kobo:suspend()
    os.execute("./suspend.sh")
end

function Kobo:resume()
    os.execute("echo 0 > /sys/power/state-extended")
    -- HACK: wait a bit for the kernel to catch up
    os.execute("sleep 0.1")
    -- cf. #1862, I can reliably break IR touch input on resume...
    -- cf. also #1943 for the rationale behind applying this workaorund in every case...
    local f = io.open("/sys/devices/virtual/input/input1/neocmd", "r")
    if f ~= nil then
        io.close(f)
        os.execute("echo 'a' > /sys/devices/virtual/input/input1/neocmd")
    end
end

function Kobo:powerOff()
    os.execute("poweroff")
end

-------------- device probe ------------

local codename = Kobo:getCodeName()

if codename == "dahlia" then
    return KoboDahlia
elseif codename == "dragon" then
    return KoboDragon
elseif codename == "kraken" then
    return KoboKraken
elseif codename == "phoenix" then
    return KoboPhoenix
elseif codename == "trilogy" then
    return KoboTrilogy
elseif codename == "pixie" then
    return KoboPixie
elseif codename == "alyssum" then
    return KoboAlyssum
elseif codename == "pika" then
    return KoboPika
else
    error("unrecognized Kobo model "..codename)
end
