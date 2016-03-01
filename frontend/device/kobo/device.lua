local Generic = require("device/generic/device")
local Geom = require("ui/geometry")
local DEBUG = require("dbg")

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
}

-- TODO: hasKeys for some devices?

-- Kobo Touch:
local KoboTrilogy = Kobo:new{
    model = "Kobo_trilogy",
    touch_switch_xy = false,
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

function Kobo:init()
    self.screen = require("ffi/framebuffer_mxcfb"):new{device = self, debug = DEBUG}
    self.powerd = require("device/kobo/powerd"):new{device = self}
    self.input = require("device/input"):new{
        device = self,
        event_map = {
            [59] = "Power_SleepCover",
            [90] = "Light",
            [102] = "Home",
            [116] = "Power",
        }
    }

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

    if self.touch_alyssum_protocol then
        self.input:registerEventAdjustHook(self.input.adjustTouchAlyssum)
    end

    if self.touch_phoenix_protocol then
        self.input.handleTouchEv = self.input.handleTouchEvPhoenix
    end

    Generic.init(self)

    self.input.open("/dev/input/event0") -- Light button and sleep slider
    self.input.open("/dev/input/event1")
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
    -- cf. #1862, I can reliably break IR touch input on resume...
    if os.getenv("FROM_NICKEL") == "true" then
        local f = io.open("/sys/devices/virtual/input/input1/neocmd", "r")
        if f ~= nil then
            io.close(f)
            os.execute("echo 'a' > /sys/devices/virtual/input/input1/neocmd")
        end
    end
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
else
    error("unrecognized Kobo model "..codename)
end
