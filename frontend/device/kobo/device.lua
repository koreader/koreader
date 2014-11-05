local Generic = require("device/generic/device")
local lfs = require("libs/libkoreader-lfs")
local Geom = require("ui/geometry")

local function yes() return true end

local Kobo = Generic:new{
    model = "Kobo",
    isKobo = yes,
    isTouchDevice = yes, -- all of them are

    -- most Kobos have X/Y switched for the touch screen
    touch_switch_xy = true,
    -- most Kobos have also mirrored X coordinates
    touch_mirrored_x = true,
}

-- TODO: hasKeys for some devices?

local KoboTrilogy = Kobo:new{
    model = "Kobo_trilogy",
    touch_switch_xy = false,
}

local KoboPixie = Kobo:new{
    model = "Kobo_pixie",
    display_dpi = 200,
}

local KoboDahlia = Kobo:new{
    model = "Kobo_dahlia",
    hasFrontlight = yes,
    touch_phoenix_protocol = true,
    display_dpi = 265,
    -- bezel:
    viewport = Geom:new{x=0, y=10, w=1080, h=1430},
}

local KoboDragon = Kobo:new{
    model = "Kobo_dragon",
    hasFrontlight = yes,
    display_dpi = 265,
}

local KoboKraken = Kobo:new{
    model = "Kobo_kraken",
    hasFrontlight = yes,
    display_dpi = 212,
}

local KoboPhoenix = Kobo:new{
    model = "Kobo_phoenix",
    hasFrontlight = yes,
    touch_phoenix_protocol = true,
    display_dpi = 212.8,
    -- bezel:
    viewport = Geom:new{x=6, y=12, w=752, h=1012},
}

function Kobo:init()
    self.screen = require("device/screen"):new{device = self}
    self.powerd = require("device/kobo/powerd"):new{device = self}
    self.input = require("device/input"):new{
        device = self,
        event_map = {
            [59] = "Power_SleepCover",
            [90] = "Light",
            [116] = "Power",
        }
    }

    Generic.init(self)

    self.input.open("/dev/input/event0") -- Light button and sleep slider
    self.input.open("/dev/input/event1")

    -- it's called KOBO_TOUCH_MIRRORED in defaults.lua, but what it
    -- actually did in its original implementation was to switch X/Y.
    if self.touch_switch_xy and not KOBO_TOUCH_MIRRORED
    or not self.touch_switch_xy and KOBO_TOUCH_MIRRORED
    then
        self.input:registerEventAdjustHook(self.input.adjustTouchSwitchXY)
    end

    if self.touch_mirrored_x then
        self.input:registerEventAdjustHook(
            self.input.adjustTouchMirrorX,
            self.screen:getScreenWidth()
        )
    end

    if self.touch_phoenix_protocol then
        self.input.handleTouchEv = self.input.handleTouchEvPhoenix
    end
end

function Kobo:getCodeName()
    local std_out = io.popen("/bin/kobo_config.sh 2>/dev/null", "r")
    local codename = std_out:read()
    std_out:close()
    return codename
end

function Kobo:getFirmwareVersion()
    local version_file = io.open("/mnt/onboard/.kobo/version", "r")
    self.firmware_rev = string.sub(version_file:read(),24,28)
    version_file:close()
end

function Kobo:Suspend()
    if KOBO_LIGHT_OFF_ON_SUSPEND then
        self.powerd:setIntensity(0)
    end
    os.execute("./suspend.sh")
end

function Kobo:Resume()
    os.execute("echo 0 > /sys/power/state-extended")
    if self.powerd then
        if KOBO_LIGHT_ON_START and tonumber(KOBO_LIGHT_ON_START) > -1 then
            self.powerd:setIntensity(math.max(math.min(KOBO_LIGHT_ON_START,100),0))
        elseif powerd.fl ~= nil then
            self.powerd.fl:restore()
        end
    end

    Generic.Resume(self)
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
else
    error("unrecognized Kobo model "..codename)
end



