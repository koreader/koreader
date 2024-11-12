local Generic = require("device/generic/device")
local Geom = require("ui/geometry")
local UIManager
local WakeupMgr = require("device/wakeupmgr")
local ffiUtil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local time = require("ui/time")
local util = require("util")
local _ = require("gettext")

-- We're going to need a few <linux/fb.h> & <linux/input.h> constants...
local ffi = require("ffi")
local C = ffi.C
require("ffi/linux_fb_h")
require("ffi/linux_input_h")
require("ffi/posix_h")
require("ffi/fbink_input_h")

local function yes() return true end
local function no() return false end
local function NOP() return end

local function koboEnableWifi(toggle)
    if toggle == true then
        logger.info("Kobo Wi-Fi: enabling Wi-Fi")
        os.execute("./enable-wifi.sh")
    else
        logger.info("Kobo Wi-Fi: disabling Wi-Fi")
        os.execute("./disable-wifi.sh")
    end
end

-- checks if standby is available on the device
local function checkStandby(target_state)
    logger.dbg("Kobo: checking if standby is possible ...")
    local f = io.open("/sys/power/state")
    if not f then
        return no
    end
    local mode = f:read()
    f:close()
    logger.dbg("Kobo: available power states:", mode)
    if mode and mode:find(target_state) then
        logger.dbg("Kobo: target standby state '" .. target_state .. "' is supported")
        return yes
    end
    logger.dbg("Kobo: target standby state '" .. target_state .. "' is unsupported")
    return no
end

-- Return the highest core number
local function getCPUCount()
    local fd = io.open("/sys/devices/system/cpu/possible", "re")
    if fd then
        local str = fd:read("*line")
        fd:close()

        -- Format is n-N, where n is the first core, and N the last (e.g., 0-3)
        return tonumber(str:match("%d+$")) or 1
    else
        return 1
    end
end

local function getCPUGovernor(knob)
    local fd = io.open(knob, "re")
    if fd then
        local str = fd:read("*line")
        fd:close()
        -- If we're currently using the userspace governor, fudge that to conservative, as we won't ever standby with Wi-Fi on.
        -- (userspace is only used on i.MX5 for DVFS shenanigans when Wi-Fi is enabled)
        if str == "userspace" then
            str = "conservative"
        end
        return str
    else
        return nil
    end
end

local function getRTCName()
    local fd = io.open("/sys/class/rtc/rtc0/name", "re")
    if fd then
        local str = fd:read("*line")
        fd:close()
        return str
    else
        return nil
    end
end

local Kobo = Generic:extend{
    model = "Kobo",
    ota_model = "kobo",
    isKobo = yes,
    isTouchDevice = yes, -- all of them are
    hasOTAUpdates = yes,
    hasFastWifiStatusQuery = yes,
    hasWifiManager = yes,
    hasWifiRestore = yes,
    canStandby = no, -- will get updated by checkStandby()
    canReboot = yes,
    canPowerOff = yes,
    canSuspend = yes,
    supportsScreensaver = yes,
    -- most Kobos are MT-capable
    hasMultitouch = yes,
    -- most Kobos have X/Y switched for the touch screen
    touch_switch_xy = true,
    -- most Kobos have also mirrored X coordinates
    touch_mirrored_x = true,
    -- but a few mirror on the Y axis instead
    touch_mirrored_y = false,
    -- enforce portrait mode on Kobos
    --- @note: In practice, the check that is used for in ffi/framebuffer is no longer relevant,
    ---        since, in almost every case, we enforce a hardware Portrait rotation via fbdepth on startup by default ;).
    ---        We still want to keep it in case an unfortunate soul on an older device disables the bitdepth switch...
    isAlwaysPortrait = yes,
    -- we don't need an extra refreshFull on resume, thank you very much.
    needsScreenRefreshAfterResume = no,
    -- some devices have coloured frontlights
    hasNaturalLight = no,
    hasNaturalLightMixer = no,
    -- HW inversion is generally safe on Kobo, except on a few boards/kernels
    canHWInvert = yes,
    home_dir = "/mnt/onboard",
    canToggleMassStorage = yes,
    -- New devices *may* be REAGL-aware, but generally don't expect explicit REAGL requests, default to not.
    isREAGL = no,
    -- Mark 7 devices sport an updated driver.
    isMk7 = no,
    -- MXCFB_WAIT_FOR_UPDATE_COMPLETE ioctls are generally reliable
    hasReliableMxcWaitFor = yes,
    -- AllWinner SoCs require a completely different fb backend...
    isSunxi = no,
    -- The fb backend also needs to know if we're on a MediaTek SoC.
    isMTK = no,
    -- On sunxi, "native" panel layout used to compute the G2D rotation handle (e.g., deviceQuirks.nxtBootRota in FBInk).
    boot_rota = nil,
    -- Standard sysfs path to the battery directory
    battery_sysfs = "/sys/class/power_supply/mc13892_bat",
    -- Stable path to the NTX input device
    ntx_dev = "/dev/input/event0",
    ntx_fd = nil,
    -- Stable path to the Touch input device
    touch_dev = "/dev/input/event1",
    -- Event code to use to detect contact pressure
    pressure_event = nil,
    -- Device features multiple CPU cores
    isSMP = no,
    -- Device supports "eclipse" waveform modes (i.e., optimized for nightmode).
    hasEclipseWfm = no,
    -- Device ships with various hardware revisions under the same device code, requiring automatic hardware detection (PMIC & FL)...
    automagic_sysfs = false,
    -- The standard "standby" power state
    standby_state = "standby",

    unexpected_wakeup_count = 0,
}

local KoboTrilogyA = Kobo:extend{
    model = "Kobo_trilogy_A",
    -- Unlike its B brethren, this one doesn't do the weird translation dance when ABS_PRESSURE is 0...
    hasKeys = yes,
    hasMultitouch = no,
}
-- Kobo Touch B:
local KoboTrilogyB = Kobo:extend{
    model = "Kobo_trilogy_B",
    touch_kobo_mk3_protocol = true,
    hasKeys = yes,
    hasMultitouch = no,
}
-- Kobo Touch C:
local KoboTrilogyC = Kobo:extend{
    model = "Kobo_trilogy_C",
    hasKeys = yes,
    hasMultitouch = no,
}

-- Kobo Mini:
local KoboPixie = Kobo:extend{
    model = "Kobo_pixie",
    display_dpi = 200,
    hasMultitouch = no,
    -- bezel:
    viewport = Geom:new{x=0, y=2, w=596, h=794},
}

-- Kobo Aura One:
local KoboDaylight = Kobo:extend{
    model = "Kobo_daylight",
    hasFrontlight = yes,
    touch_phoenix_protocol = true,
    display_dpi = 300,
    hasNaturalLight = yes,
    frontlight_settings = {
        frontlight_white = "/sys/class/backlight/lm3630a_led1b",
        frontlight_red = "/sys/class/backlight/lm3630a_led1a",
        frontlight_green = "/sys/class/backlight/lm3630a_ledb",
    },
}

-- Kobo Aura H2O:
local KoboDahlia = Kobo:extend{
    model = "Kobo_dahlia",
    canToggleChargingLED = yes,
    led_uses_channel_3 = true,
    hasFrontlight = yes,
    touch_phoenix_protocol = true,
    -- There's no slot 0, the first finger gets assigned slot 1, and the second slot 2.
    -- NOTE: Could be queried at runtime via EVIOCGABS on C.ABS_MT_TRACKING_ID (minimum field).
    --       Used to be handled via an adjustTouchAlyssum hook that just mangled ABS_MT_TRACKING_ID values.
    main_finger_slot = 1,
    display_dpi = 265,
    -- the bezel covers the top 11 pixels:
    viewport = Geom:new{x=0, y=11, w=1080, h=1429},
}

-- Kobo Aura HD:
local KoboDragon = Kobo:extend{
    model = "Kobo_dragon",
    hasFrontlight = yes,
    hasMultitouch = no,
    display_dpi = 265,
}

-- Kobo Glo:
local KoboKraken = Kobo:extend{
    model = "Kobo_kraken",
    hasFrontlight = yes,
    hasMultitouch = no,
    display_dpi = 212,
}

-- Kobo Aura:
local KoboPhoenix = Kobo:extend{
    model = "Kobo_phoenix",
    hasFrontlight = yes,
    touch_phoenix_protocol = true,
    display_dpi = 212,
    -- The bezel covers 10 pixels at the bottom:
    viewport = Geom:new{x=0, y=0, w=758, h=1014},
    -- NOTE: AFAICT, the Aura was the only one explicitly requiring REAGL requests...
    isREAGL = yes,
    -- NOTE: May have a buggy kernel, according to the nightmode hack...
    canHWInvert = no,
}

-- Kobo Aura H2O2:
local KoboSnow = Kobo:extend{
    model = "Kobo_snow",
    hasFrontlight = yes,
    touch_snow_protocol = true,
    touch_mirrored_x = false,
    display_dpi = 265,
    hasNaturalLight = yes,
    frontlight_settings = {
        frontlight_white = "/sys/class/backlight/lm3630a_ledb",
        frontlight_red = "/sys/class/backlight/lm3630a_led",
        frontlight_green = "/sys/class/backlight/lm3630a_leda",
    },
}

-- Kobo Aura H2O2, Rev2:
--- @fixme Check if the Clara fix actually helps here... (#4015)
local KoboSnowRev2 = Kobo:extend{
    model = "Kobo_snow_r2",
    isMk7 = yes,
    hasFrontlight = yes,
    touch_snow_protocol = true,
    display_dpi = 265,
    hasNaturalLight = yes,
    frontlight_settings = {
        frontlight_white = "/sys/class/backlight/lm3630a_ledb",
        frontlight_red = "/sys/class/backlight/lm3630a_leda",
    },
}

-- Kobo Aura second edition:
local KoboStar = Kobo:extend{
    model = "Kobo_star",
    hasFrontlight = yes,
    touch_phoenix_protocol = true,
    display_dpi = 212,
}

-- Kobo Aura second edition, Rev 2:
local KoboStarRev2 = Kobo:extend{
    model = "Kobo_star_r2",
    isMk7 = yes,
    hasFrontlight = yes,
    touch_phoenix_protocol = true,
    display_dpi = 212,
}

-- Kobo Glo HD:
local KoboAlyssum = Kobo:extend{
    model = "Kobo_alyssum",
    hasFrontlight = yes,
    touch_phoenix_protocol = true,
    main_finger_slot = 1,
    display_dpi = 300,
}

-- Kobo Touch 2.0:
local KoboPika = Kobo:extend{
    model = "Kobo_pika",
    touch_phoenix_protocol = true,
    main_finger_slot = 1,
}

-- Kobo Clara HD:
local KoboNova = Kobo:extend{
    model = "Kobo_nova",
    isMk7 = yes,
    canToggleChargingLED = yes,
    hasFrontlight = yes,
    touch_snow_protocol = true,
    display_dpi = 300,
    hasNaturalLight = yes,
    frontlight_settings = {
        frontlight_white = "/sys/class/backlight/mxc_msp430.0/brightness",
        frontlight_mixer = "/sys/class/backlight/lm3630a_led/color",
        nl_min = 0,
        nl_max = 10,
        nl_inverted = true,
    },
}

-- Kobo Forma:
-- NOTE: Right now, we enforce Portrait orientation on startup to avoid getting touch coordinates wrong,
--       no matter the rotation we were started from (c.f., platform/kobo/koreader.sh).
-- NOTE: For the FL, assume brightness is WO, and actual_brightness is RO!
--       i.e., we could have a real KoboPowerD:frontlightIntensityHW() by reading actual_brightness ;).
-- NOTE: Rotation events *may* not be enabled if Nickel has never been brought up in that power cycle.
--       i.e., this will affect KSM users.
--       c.f., https://github.com/koreader/koreader/pull/4414#issuecomment-449652335
--       There's also a CM_ROTARY_ENABLE command, but which seems to do as much nothing as the STATUS one...
local KoboFrost = Kobo:extend{
    model = "Kobo_frost",
    isMk7 = yes,
    canToggleChargingLED = yes,
    hasFrontlight = yes,
    hasKeys = yes,
    hasGSensor = yes,
    touch_snow_protocol = true,
    display_dpi = 300,
    hasNaturalLight = yes,
    frontlight_settings = {
        frontlight_white = "/sys/class/backlight/mxc_msp430.0/brightness",
        frontlight_mixer = "/sys/class/backlight/tlc5947_bl/color",
        -- Warmth goes from 0 to 10 on the device's side (our own internal scale is still normalized to [0...100])
        -- NOTE: Those three extra keys are *MANDATORY* if frontlight_mixer is set!
        nl_min = 0,
        nl_max = 10,
        nl_inverted = true,
    },
}

-- Kobo Libra:
-- NOTE: Assume the same quirks as the Forma apply.
local KoboStorm = Kobo:extend{
    model = "Kobo_storm",
    isMk7 = yes,
    canToggleChargingLED = yes,
    hasFrontlight = yes,
    hasKeys = yes,
    hasGSensor = yes,
    touch_snow_protocol = true,
    display_dpi = 300,
    hasNaturalLight = yes,
    frontlight_settings = {
        frontlight_white = "/sys/class/backlight/mxc_msp430.0/brightness",
        frontlight_mixer = "/sys/class/backlight/lm3630a_led/color",
        -- Warmth goes from 0 to 10 on the device's side (our own internal scale is still normalized to [0...100])
        -- NOTE: Those three extra keys are *MANDATORY* if frontlight_mixer is set!
        nl_min = 0,
        nl_max = 10,
        nl_inverted = true,
    },
    -- NOTE: The Libra apparently suffers from a mysterious issue where completely innocuous WAIT_FOR_UPDATE_COMPLETE ioctls
    --       will mysteriously fail with a timeout (5s)...
    --       This obviously leads to *terrible* user experience,
    --       so we've tried a few things over the years to attempt to deal with it.
    --       c.f., https://github.com/koreader/koreader/issues/7340 for the genesis of all that.
    -- NOTE: On a possibly related note, on NXP devices (even earlier ones), Nickel will *always* wait for markers in pairs:
    --       the "expected" marker to wait for, and the *previous* one right before that.
    --       Of course, that first wait will mostly always return early, because that refresh is usually much older and already dealt with.
    --       This weird quirk was dropped on sunxi & MTK, FWIW.
    hasReliableMxcWaitFor = no,
}

-- Kobo Nia:
local KoboLuna = Kobo:extend{
    model = "Kobo_luna",
    isMk7 = yes,
    canToggleChargingLED = yes,
    hasFrontlight = yes,
    touch_phoenix_protocol = true,
    display_dpi = 212,
    hasReliableMxcWaitFor = no, -- Board is similar to the Libra 2, but it's such an unpopular device that reports are scarce.
    -- Handle the HW revision w/ a BD71828 PMIC
    automagic_sysfs = true,
}

-- Kobo Elipsa
local KoboEuropa = Kobo:extend{
    model = "Kobo_europa",
    isSunxi = yes,
    hasEclipseWfm = yes,
    canToggleChargingLED = yes,
    led_uses_channel_3 = true,
    hasFrontlight = yes,
    hasGSensor = yes,
    pressure_event = C.ABS_MT_PRESSURE,
    display_dpi = 227,
    boot_rota = C.FB_ROTATE_CCW,
    battery_sysfs = "/sys/class/power_supply/battery",
    isSMP = yes,
}

-- Kobo Sage
local KoboCadmus = Kobo:extend{
    model = "Kobo_cadmus",
    isSunxi = yes,
    hasEclipseWfm = yes,
    canToggleChargingLED = yes,
    led_uses_channel_3 = true,
    hasFrontlight = yes,
    hasKeys = yes,
    hasGSensor = yes,
    pressure_event = C.ABS_MT_PRESSURE,
    display_dpi = 300,
    hasNaturalLight = yes,
    frontlight_settings = {
        frontlight_white = "/sys/class/backlight/mxc_msp430.0/brightness",
        frontlight_mixer = "/sys/class/leds/aw99703-bl_FL1/color",
        -- Warmth goes from 0 to 10 on the device's side (our own internal scale is still normalized to [0...100])
        -- NOTE: Those three extra keys are *MANDATORY* if frontlight_mixer is set!
        nl_min = 0,
        nl_max = 10,
        nl_inverted = false,
    },
    boot_rota = C.FB_ROTATE_CW,
    battery_sysfs = "/sys/class/power_supply/battery",
    hasAuxBattery = yes,
    aux_battery_sysfs = "/sys/class/misc/cilix",
    isSMP = yes,
    -- Much like the Libra 2, there are at least two different HW revisions, with different PMICs...
    automagic_sysfs = true,
}

-- Kobo Libra 2:
local KoboIo = Kobo:extend{
    model = "Kobo_io",
    isMk7 = yes,
    hasEclipseWfm = yes,
    canToggleChargingLED = yes,
    hasFrontlight = yes,
    hasKeys = yes,
    hasGSensor = yes,
    pressure_event = C.ABS_MT_PRESSURE,
    touch_mirrored_x = false,
    display_dpi = 300,
    hasNaturalLight = yes,
    frontlight_settings = {
        frontlight_white = "/sys/class/backlight/mxc_msp430.0/brightness",
        -- Warmth goes from 0 to 10 on the device's side (our own internal scale is still normalized to [0...100])
        -- NOTE: Those three extra keys are *MANDATORY* if frontlight_mixer is set!
        nl_min = 0,
        nl_max = 10,
        nl_inverted = true,
    },
    -- It would appear that the Libra 2 inherited its ancestor's quirks, and more...
    -- c.f., https://github.com/koreader/koreader/issues/8414 & https://github.com/koreader/koreader/issues/8664
    hasReliableMxcWaitFor = no,
    -- NOTE: There are at least two hardware revisions of this device (*without* a device code change, this time),
    --       with *significant* hardware changes, so we'll handle this by making the sysfs path discovery automagic.
    --       c.f., https://github.com/koreader/koreader/issues/9218
    automagic_sysfs = true,
}

-- Kobo Clara 2E:
local KoboGoldfinch = Kobo:extend{
    model = "Kobo_goldfinch",
    isMk7 = yes,
    hasEclipseWfm = yes,
    canToggleChargingLED = yes,
    led_uses_channel_3 = true,
    hasFrontlight = yes,
    display_dpi = 300,
    hasNaturalLight = yes,
    frontlight_settings = {
        frontlight_white = "/sys/class/backlight/mxc_msp430.0/brightness",
        frontlight_mixer = "/sys/class/leds/aw99703-bl_FL1/color",
        nl_min = 0,
        nl_max = 10,
        nl_inverted = true,
    },
    battery_sysfs = "/sys/class/power_supply/battery",
    -- Board is eerily similar to the Libra 2, so, it inherits the same quirks...
    -- c.f., https://github.com/koreader/koreader/issues/9552#issuecomment-1293000313
    hasReliableMxcWaitFor = no,
}

-- Kobo Elipsa 2E:
local KoboCondor = Kobo:extend{
    model = "Kobo_condor",
    isMTK = yes,
    hasEclipseWfm = yes,
    canToggleChargingLED = yes,
    hasFrontlight = yes,
    hasGSensor = yes,
    display_dpi = 227,
    pressure_event = C.ABS_MT_PRESSURE,
    touch_mirrored_x = false,
    touch_mirrored_y = true,
    hasNaturalLight = yes,
    frontlight_settings = {
        frontlight_white = "/sys/class/backlight/mxc_msp430.0/brightness",
        frontlight_mixer = "/sys/class/leds/aw99703-bl_FL1/color",
        nl_min = 0,
        nl_max = 10,
        nl_inverted = true,
    },
    battery_sysfs = "/sys/class/power_supply/bd71827_bat",
    isSMP = yes,
}

-- Kobo Libra Colour:
local KoboMonza = Kobo:extend{
    model = "Kobo_monza",
    isMTK = yes,
    hasEclipseWfm = yes,
    canToggleChargingLED = yes,
    hasFrontlight = yes,
    hasKeys = yes,
    hasGSensor = yes,
    display_dpi = 300,
    pressure_event = C.ABS_MT_PRESSURE,
    touch_mirrored_x = false,
    touch_mirrored_y = true,
    hasNaturalLight = yes,
    frontlight_settings = {
        frontlight_white = "/sys/class/backlight/mxc_msp430.0/brightness",
        frontlight_mixer = "/sys/class/backlight/lm3630a_led/color",
        nl_min = 0,
        nl_max = 10,
        nl_inverted = true,
    },
    battery_sysfs = "/sys/class/power_supply/bd71827_bat",
    isSMP = yes,
    hasColorScreen = yes,
}

-- Kobo Clara B/W:
local KoboSpaBW = Kobo:extend{
    model = "Kobo_spaBW",
    isMTK = yes,
    hasEclipseWfm = yes,
    canToggleChargingLED = yes,
    hasFrontlight = yes,
    touch_snow_protocol = true,
    display_dpi = 300,
    hasNaturalLight = yes,
    frontlight_settings = {
        frontlight_white = "/sys/class/backlight/mxc_msp430.0/brightness",
        frontlight_mixer = "/sys/class/backlight/lm3630a_led/color",
        nl_min = 0,
        nl_max = 10,
        nl_inverted = true,
    },
    battery_sysfs = "/sys/class/power_supply/bd71827_bat",
}

-- Kobo Clara Colour:
local KoboSpaColour = Kobo:extend{
    model = "Kobo_spaColour",
    isMTK = yes,
    hasEclipseWfm = yes,
    canToggleChargingLED = yes,
    hasFrontlight = yes,
    touch_snow_protocol = true,
    display_dpi = 300,
    hasNaturalLight = yes,
    frontlight_settings = {
        frontlight_white = "/sys/class/backlight/mxc_msp430.0/brightness",
        frontlight_mixer = "/sys/class/backlight/lm3630a_led/color",
        nl_min = 0,
        nl_max = 10,
        nl_inverted = true,
    },
    battery_sysfs = "/sys/class/power_supply/bd71827_bat",
    isSMP = yes,
    hasColorScreen = yes,
}

function Kobo:setupChargingLED()
    if G_reader_settings:nilOrTrue("enable_charging_led") then
        if self:hasAuxBattery() and self.powerd:isAuxBatteryConnected() then
            self:toggleChargingLED(self.powerd:isAuxCharging() and not self.powerd:isAuxCharged())
        else
            self:toggleChargingLED(self.powerd:isCharging() and not self.powerd:isCharged())
        end
    end
end

function Kobo:getKeyRepeat()
    -- Sanity check (mostly for the testsuite's benefit...)
    if not self.ntx_fd then
        return false
    end

    self.key_repeat = ffi.new("unsigned int[?]", C.REP_CNT)
    if C.ioctl(self.ntx_fd, C.EVIOCGREP, self.key_repeat) < 0 then
        local err = ffi.errno()
        logger.warn("Device:getKeyRepeat: EVIOCGREP ioctl on fd", self.ntx_fd, "failed:", ffi.string(C.strerror(err)))
        return false
    else
        logger.dbg("Key repeat is set up to repeat every", self.key_repeat[C.REP_PERIOD], "ms after a delay of", self.key_repeat[C.REP_DELAY], "ms")
        self.canKeyRepeat = yes
        return true
    end
end

function Kobo:disableKeyRepeat()
    -- NOTE: LuaJIT zero inits, and PERIOD == 0 with DELAY == 0 disables repeats ;).
    local key_repeat = ffi.new("unsigned int[?]", C.REP_CNT)
    if C.ioctl(self.ntx_fd, C.EVIOCSREP, key_repeat) < 0 then
        local err = ffi.errno()
        logger.warn("Device:disableKeyRepeat: EVIOCSREP ioctl on fd", self.ntx_fd, "failed:", ffi.string(C.strerror(err)))
    end
end

function Kobo:restoreKeyRepeat()
    if C.ioctl(self.ntx_fd, C.EVIOCSREP, self.key_repeat) < 0 then
        local err = ffi.errno()
        logger.warn("Device:restoreKeyRepeat: EVIOCSREP ioctl on fd", self.ntx_fd, "failed:", ffi.string(C.strerror(err)))
    end
end

function Kobo:toggleKeyRepeat(toggle)
    local key_repeat = ffi.new("unsigned int[?]", C.REP_CNT)
    if toggle == true then
        -- Use the defaults from a Sage, as we can't guarantee the state of the setup on startup, so we can't just use self.key_repeat
        key_repeat[C.REP_DELAY] = 400
        key_repeat[C.REP_PERIOD] = 80
    elseif toggle == false then
        key_repeat[C.REP_DELAY] = 0
        key_repeat[C.REP_PERIOD] = 0
    else
        -- Check the current (kernel) state to know what to do
        if C.ioctl(self.ntx_fd, C.EVIOCGREP, key_repeat) < 0 then
            local err = ffi.errno()
            logger.warn("Device:toggleKeyRepeat: EVIOCGREP ioctl on fd", self.ntx_fd, "failed:", ffi.string(C.strerror(err)))
            return false
        else
            if key_repeat[C.REP_DELAY] == 0 and key_repeat[C.REP_PERIOD] == 0 then
                return self:toggleKeyRepeat(true)
            else
                return self:toggleKeyRepeat(false)
            end
        end
    end

    if C.ioctl(self.ntx_fd, C.EVIOCSREP, key_repeat) < 0 then
        local err = ffi.errno()
        logger.warn("Device:toggleKeyRepeat: EVIOCSREP ioctl on fd", self.ntx_fd, "failed:", ffi.string(C.strerror(err)))
        return false
    end

    return true
end

function Kobo:init()
    -- Check if we need to disable MXCFB_WAIT_FOR_UPDATE_COMPLETE ioctls...
    local mxcfb_bypass_wait_for
    if G_reader_settings:has("mxcfb_bypass_wait_for") then
        mxcfb_bypass_wait_for = G_reader_settings:isTrue("mxcfb_bypass_wait_for")
    else
        mxcfb_bypass_wait_for = not self:hasReliableMxcWaitFor()
    end

    if self:isSunxi() then
        self.screen = require("ffi/framebuffer_sunxi"):new{
            device = self,
            debug = logger.dbg,
            is_always_portrait = self.isAlwaysPortrait(),
            mxcfb_bypass_wait_for = mxcfb_bypass_wait_for,
            boot_rota = self.boot_rota,
        }

        -- Sunxi means no HW inversion :(
        self.canHWInvert = no
    else
        self.screen = require("ffi/framebuffer_mxcfb"):new{
            device = self,
            debug = logger.dbg,
            is_always_portrait = self.isAlwaysPortrait(),
            mxcfb_bypass_wait_for = mxcfb_bypass_wait_for,
            no_cfa_post_processing = G_reader_settings:isTrue("no_cfa_post_processing"),
        }
        if self.screen.fb_bpp == 32 and self.screen._vinfo.red.offset ~= 0 then
            -- Ensure we decode images properly, as our framebuffer is BGRA...
            logger.info("Enabling Kobo @ 32bpp BGR tweaks")
            self.hasBGRFrameBuffer = yes
        end
    end

    -- So far, MTK kernels do not export a per-request inversion flag
    if self:isMTK() then
        -- Instead, there's a global flag that we can *set* (but not *get*) via a procfs knob...
        -- Overload the HWNightMode stuff to implement that properly, like we do on Kindle
        function self.screen:setHWNightmode(toggle)
            -- No getter, so, keep track of our own state
            self.hw_night_mode = toggle
            -- Flip the global invert_fb flag
            ffiUtil.writeToSysfs(toggle and "night_mode 4" or "night_mode 0", "/proc/hwtcon/cmd")
        end

        function self.screen:getHWNightmode()
            -- Return false on nil for reader.lua's sake, mostly.
            -- (We want to disable this on exit, always, as it will never be used by Nickel, which does SW inversion).
            return self.hw_night_mode == true
        end
    end

    -- Just to be safe, we absolutely don't want to call open on this, so just use stat
    self.has_wakeup_count = util.pathExists("/sys/power/wakeup_count")

    -- Automagic sysfs discovery
    if self.automagic_sysfs then
        -- Battery
        if util.pathExists("/sys/class/power_supply/battery") then
            -- Newer devices (circa sunxi)
            self.battery_sysfs = "/sys/class/power_supply/battery"
        elseif util.fileExists("/sys/class/power_supply/bd71827_bat") then
            self.battery_sysfs = "/sys/class/power_supply/bd71827_bat"
        else
            self.battery_sysfs = "/sys/class/power_supply/mc13892_bat"
        end

        -- Frontlight
        if self:hasNaturalLight() then
            if util.fileExists("/sys/class/leds/aw99703-bl_FL1/color") then
                -- HWConfig FL_PWM is AW99703x2
                self.frontlight_settings.frontlight_mixer = "/sys/class/leds/aw99703-bl_FL1/color"
            elseif util.fileExists("/sys/class/backlight/lm3630a_led/color") then
                -- HWConfig FL_PWM is LM3630
                self.frontlight_settings.frontlight_mixer = "/sys/class/backlight/lm3630a_led/color"
            elseif util.fileExists("/sys/class/backlight/tlc5947_bl/color") then
                -- HWConfig FL_PWM is TLC5947
                self.frontlight_settings.frontlight_mixer = "/sys/class/backlight/tlc5947_bl/color"
            end
        end
    end

    -- NOTE: i.MX5 devices have a wonky RTC that doesn't like alarms set further away that UINT16_MAX seconds from now...
    --       (c.f., WakeupMgr for more details).
    -- NOTE: getRTCName is currently hardcoded to rtc0 (which is also WakeupMgr's default).
    local dodgy_rtc = false
    if getRTCName() == "pmic_rtc" then
        -- This *should* match the 'RTC' (46) NTX HWConfig field being set to 'MSP430' (0).
        dodgy_rtc = true
    end

    -- Detect the various CPU governor sysfs knobs...
    if util.pathExists("/sys/devices/system/cpu/cpufreq/policy0") then
        self.cpu_governor_knob = "/sys/devices/system/cpu/cpufreq/policy0/scaling_governor"
    else
        self.cpu_governor_knob = "/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"
    end
    self.default_cpu_governor = getCPUGovernor(self.cpu_governor_knob)
    -- NOP unsupported methods
    if not self.default_cpu_governor then
        self.performanceCPUGovernor = NOP
        self.defaultCPUGovernor = NOP
    end

    -- And while we're on CPU-related endeavors...
    self.cpu_count = self:isSMP() and getCPUCount() or 1
    -- NOP unsupported methods
    if self.cpu_count == 1 then
        self.enableCPUCores = NOP
    end

    -- Automagically set this so we never have to remember to do it manually ;p
    if self:hasNaturalLight() and self.frontlight_settings and self.frontlight_settings.frontlight_mixer then
        self.hasNaturalLightMixer = yes
    end
    -- Ditto
    if self:isMk7() or self:isMTK() then
        self.canHWDither = yes
    end

    -- Enable Kaleido waveform modes on supported devices
    if self:hasColorScreen() and self:isMTK() then
        self.hasKaleidoWfm = yes
    end

    -- NOTE: Devices with an AW99703 frontlight PWM controller feature a hardware smooth ramp when setting the frontlight intensity.
    ---      A side-effect of this behavior is that if you queue a series of intensity changes ending at 0,
    ---      it won't ramp *at all*, jumping straight to zero instead.
    ---      So we delay the final ramp off step to prevent (both) the native and our ramping from being optimized out.
    if self:hasNaturalLightMixer() and self.frontlight_settings.frontlight_mixer:find("aw99703", 12, true) then
        self.frontlight_settings.ramp_off_delay = 0.5
    end

    -- I don't know how this PWM controller behaves on earlier devices, but it's... not great here.
    if self:hasNaturalLightMixer() and self:isMTK() and self.frontlight_settings.frontlight_mixer:find("lm3630a_led", 12, true) then
        -- First, we need a delay between ioctls
        self.frontlight_settings.ramp_delay =  0.025
        -- Second, it *really* doesn't like being interleaved with screen refreshes
        self.frontlight_settings.delay_ramp_start = true
    end

    self.powerd = require("device/kobo/powerd"):new{
        device = self,
        battery_sysfs = self.battery_sysfs,
        aux_battery_sysfs = self.aux_battery_sysfs,
    }
    -- NOTE: For the Forma, with the buttons on the right, 193 is Top, 194 Bottom.
    self.input = require("device/input"):new{
        device = self,
        event_map = {
            [35] = "SleepCover",  -- KEY_H, Elipsa
            [59] = "SleepCover",
            [90] = "LightButton",
            [102] = "Home",
            [116] = "Power",
            [193] = "RPgBack",
            [194] = "RPgFwd",
            [331] = "Eraser",
            [332] = "Highlighter",
        },
        event_map_adapter = {
            SleepCover = function(ev)
                if self.input:isEvKeyPress(ev) then
                    return "SleepCoverClosed"
                elseif self.input:isEvKeyRelease(ev) then
                    return "SleepCoverOpened"
                end
            end,
            LightButton = function(ev)
                if self.input:isEvKeyRelease(ev) then
                    return "Light"
                end
            end,
        },
        main_finger_slot = self.main_finger_slot or 0,
        pressure_event = self.pressure_event,
    }
    self.wakeup_mgr = WakeupMgr:new{
        dodgy_rtc = dodgy_rtc,
    }

    -- Input handling on Kobo is a thing of nightmares, start by setting up the actual evdev handler...
    self:setTouchEventHandler()
    -- And then handle the extra shenanigans if necessary.
    self:initEventAdjustHooks()

    -- Auto-detect input devices (via FBInk's fbink_input_scan)
    local ok, FBInkInput = pcall(ffi.loadlib, "fbink_input", 1)
    if not ok then
        print("fbink_input not loaded:", FBInkInput)
        -- NOP fallback for the testsuite...
        FBInkInput = { fbink_input_scan = NOP }
    end
    local dev_count = ffi.new("size_t[1]")
    -- We care about: the touchscreen, the stylus, the power button, the sleep cover, and pagination buttons
    -- (and technically rotation events, but we'll get it with the device that provides the buttons on NTX).
    -- We exclude keyboards to play nice with the ExternalKeyboard plugin, which will handle potential keyboards on its own.
    local match_mask = bit.bor(C.INPUT_TOUCHSCREEN, C.INPUT_TABLET, C.INPUT_POWER_BUTTON, C.INPUT_SLEEP_COVER, C.INPUT_PAGINATION_BUTTONS)
    local devices = FBInkInput.fbink_input_scan(match_mask, C.INPUT_KEYBOARD, 0, dev_count)
    if devices ~= nil then
        for i = 0, tonumber(dev_count[0]) - 1 do
            local dev = devices[i]
            if dev.matched then
                -- We need to single out whichever device provides pagination buttons or sleep cover events, as we'll want to tweak key repeat there...
                -- The first one will do, as it's extremely likely to be event0, and that's pretty fairly set in stone on NTX boards.
                if (bit.band(dev.type, C.INPUT_PAGINATION_BUTTONS) ~= 0 or bit.band(dev.type, C.INPUT_SLEEP_COVER) ~= 0) and not self.ntx_fd then
                    self.ntx_fd = self.input:fdopen(tonumber(dev.fd), ffi.string(dev.path), ffi.string(dev.name))
                else
                    self.input:fdopen(tonumber(dev.fd), ffi.string(dev.path), ffi.string(dev.name))
                end
            end
        end
        C.free(devices)
    else
        -- Auto-detection failed, warn and fall back to defaults
        logger.warn("We failed to auto-detect the proper input devices, input handling may be inconsistent!")
        -- Various HW Buttons, Switches & Synthetic NTX events
        self.ntx_fd = self.input:open(self.ntx_dev)
        -- Touch panel
        self.input:open(self.touch_dev)
    end

    -- NOTE: On devices with a gyro, there may be a dedicated input device outputting the raw accelerometer data
    --       (3-Axis Orientation/Motion Detection).
    --       We skip it because we don't need it (synthetic rotation change events are sent to the main ntx input device),
    --       and it's usually *extremely* verbose, so it'd just be a waste of processing power.
    -- fake_events is only used for usb plug & charge events so far (generated via uevent, c.f., input/iput-kobo.h in base).
    -- NOTE: usb hotplug event is also available in /tmp/nickel-hardware-status (... but only when Nickel is running ;p)
    self.input:open("fake_events")

    -- See if the device supports key repeat
    -- This is *not* behind a hasKeys check, because we mainly use it to stop SleepCover chatter,
    -- and sleep covers are available on a number of devices without keys ;).
    self:getKeyRepeat()
    if not self:canKeyRepeat() then
        -- NOP unsupported methods
        self.disableKeyRepeat = NOP
        self.restoreKeyRepeat = NOP
        self.toggleKeyRepeat  = NOP
    end

    -- Detect the NTX charging LED sysfs knob
    if util.pathExists("/sys/class/leds/LED") then
        self.charging_led_sysfs_knob = "/sys/class/leds/LED/brightness"
    elseif util.pathExists("/sys/class/leds/GLED") then
        self.charging_led_sysfs_knob = "/sys/class/leds/GLED/brightness"
    elseif util.pathExists("/sys/class/leds/bd71828-green-led") then
        self.charging_led_sysfs_knob = "/sys/class/leds/bd71828-green-led/brightness"
    elseif util.pathExists("/sys/devices/platform/ntx_led/lit") then
        self.ntx_lit_sysfs_knob = "/sys/devices/platform/ntx_led/lit"
    elseif util.pathExists("/sys/devices/platform/pmic_light.1/lit") then
        self.ntx_lit_sysfs_knob = "/sys/devices/platform/pmic_light.1/lit"
    else
        self.canToggleChargingLED = no
    end

    -- Switch to the simple standard implementation if available
    if self.charging_led_sysfs_knob then
        self.charging_led_imp = self._LinuxChargingLEDToggle
    else
        self.charging_led_imp = self._NTXChargingLEDToggle
    end

    -- NOP unsupported methods
    if not self:canToggleChargingLED() then
        self.toggleChargingLED = NOP
        self.setupChargingLED = NOP
    end

    -- We have no way of querying the current state of the charging LED, so, start from scratch.
    -- Much like Nickel, start by turning it off.
    self:toggleChargingLED(false)
    self:setupChargingLED()

    -- Only enable a single core on startup
    self:enableCPUCores(1)

    -- On MTK, the "standby" power state is unavailable, and Nickel instead uses "mem" (and /sys/power/mem_sleep doesn't exist either)
    if self:isMTK() then
        self.standby_state = "mem"
    end

    self.canStandby = checkStandby(self.standby_state)
    if self.canStandby() and (self:isMk7() or self:isSunxi()) then
        -- NOTE: Do *NOT* enable this on MTK. What happens if you do can only be described as "shit hits the fan".
        --       (Nickel doesn't).
        self.canPowerSaveWhileCharging = yes
    end

    -- Check if the device has a Neonode IR grid (to tone down the chatter on resume ;)).
    if lfs.attributes("/sys/devices/virtual/input/input1/neocmd", "mode") == "file" then
        -- As found on (at least), the Aura H2O
        self.hasIRGridSysfsKnob = "/sys/devices/virtual/input/input1/neocmd"
    elseif lfs.attributes("/sys/devices/platform/imx-i2c.1/i2c-1/1-0050/neocmd", "mode") == "file" then
        -- As found on (at least) the Glo HD (c.f., https://github.com/koreader/koreader/pull/9377#issuecomment-1213544478)
        self.hasIRGridSysfsKnob = "/sys/devices/platform/imx-i2c.1/i2c-1/1-0050/neocmd"
    end

    -- Disable key repeat if requested
    if G_reader_settings:isTrue("input_no_key_repeat") then
        self:toggleKeyRepeat(false)
    end

    -- Switch to the proper packages on FW 5.x
    -- NOTE: We don't distribute kobov4 binaries, the omission is on purpose.
    if util.fileExists("/usr/bin/hwdetect.sh") then
        self.ota_model = "kobov5"
    end

    -- Finally, Let Generic properly setup the standard stuff.
    -- (Of particular import, this needs to come *after* we've set our input hooks, so that the viewport translation runs last).
    Generic.init(self)
end

function Kobo:exit()
    -- Re-enable key repeat on exit, that's the default state
    self:toggleKeyRepeat(true)

    Generic.exit(self)
end

function Kobo:setDateTime(year, month, day, hour, min, sec)
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

function Kobo:initNetworkManager(NetworkMgr)
    function NetworkMgr:turnOffWifi(complete_callback)
        self:releaseIP()
        koboEnableWifi(false)
        if complete_callback then
            complete_callback()
        end
    end

    function NetworkMgr:turnOnWifi(complete_callback, interactive)
        koboEnableWifi(true)
        return self:reconnectOrShowNetworkMenu(complete_callback, interactive)
    end

    local net_if = os.getenv("INTERFACE") or "eth0"
    function NetworkMgr:getNetworkInterfaceName()
        return net_if
    end
    NetworkMgr:setWirelessBackend(
        "wpa_supplicant", {ctrl_interface = "/var/run/wpa_supplicant/" .. net_if})

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
    -- Usually handled in NetworkMgr:init, but we'll need it *now*
    NetworkMgr.interface = net_if

    -- Kill Wi-Fi if NetworkMgr:isWifiOn() and NOT NetworkMgr:isConnected()
    -- (i.e., if the launcher left the Wi-Fi in an inconsistent state: modules loaded, but no route to gateway).
    if NetworkMgr:isWifiOn() and not NetworkMgr:isConnected() then
        logger.info("Kobo Wi-Fi: Left in an inconsistent state by launcher!")
        NetworkMgr:turnOffWifi()
    end
end

function Kobo:setTouchEventHandler()
    if self.touch_snow_protocol then
        self.input.snow_protocol = true
        self.input.handleTouchEv = self.input.handleTouchEvSnow
    elseif self.touch_phoenix_protocol then
        self.input.handleTouchEv = self.input.handleTouchEvPhoenix
    elseif not self:hasMultitouch() then
        self.input.handleTouchEv = self.input.handleTouchEvLegacy
        if self.touch_kobo_mk3_protocol then
            self.input.touch_kobo_mk3_protocol = true
        end
    end

    -- Accelerometer
    if self:hasGSensor() then
        self.input.handleMiscEv = function(this, ev)
            -- As generated by gyroTranslation below
            if ev.code == C.MSC_GYRO then
                return this:handleGyroEv(ev)
            end
        end
    end
end

-- HAL for gyro orientation switches (NTX's EV_MSC:MSC_RAW w/ custom values to EV_MSC:MSC_GYRO w/ our own custom values)
local function gyroTranslation(ev)
    -- c.f., include/uapi/linux/input.h,
    -- implementations in drivers/hwmon/mma8x5x.c & drivers/input/touchscreen/kx122.c
    local MSC_RAW_GSENSOR_PORTRAIT_DOWN   = 0x17
    local MSC_RAW_GSENSOR_PORTRAIT_UP     = 0x18
    local MSC_RAW_GSENSOR_LANDSCAPE_RIGHT = 0x19
    local MSC_RAW_GSENSOR_LANDSCAPE_LEFT  = 0x1a
    -- Not that we care about those, but they are reported, and accurate ;).
    --[[
    local MSC_RAW_GSENSOR_BACK            = 0x1b
    local MSC_RAW_GSENSOR_FRONT           = 0x1c
    --]]

    if ev.value == MSC_RAW_GSENSOR_PORTRAIT_UP then
        -- i.e., UR
        ev.code = C.MSC_GYRO
        ev.value = C.DEVICE_ROTATED_UPRIGHT
    elseif ev.value == MSC_RAW_GSENSOR_LANDSCAPE_RIGHT then
        -- i.e., CW
        ev.code = C.MSC_GYRO
        ev.value = C.DEVICE_ROTATED_CLOCKWISE
    elseif ev.value == MSC_RAW_GSENSOR_PORTRAIT_DOWN then
        -- i.e., UD
        ev.code = C.MSC_GYRO
        ev.value = C.DEVICE_ROTATED_UPSIDE_DOWN
    elseif ev.value == MSC_RAW_GSENSOR_LANDSCAPE_LEFT then
        -- i.e., CCW
        ev.code = C.MSC_GYRO
        ev.value = C.DEVICE_ROTATED_COUNTER_CLOCKWISE
    end
end

function Kobo:initEventAdjustHooks()
    -- Build a single composite hook, to avoid duplicated branches...
    local koboInputMangling
    -- NOTE: touch_switch_xy is *always* true, but not touch_mirrored_x or touch_mirrored_y...
    if self.touch_switch_xy and self.touch_mirrored_x then
        local max_x = self.screen:getWidth() - 1
        koboInputMangling = function(this, ev)
            if ev.type == C.EV_ABS then
                this:adjustABS_SwitchAxesAndMirrorX(ev, max_x)
            elseif ev.type == C.EV_MSC and ev.code == C.MSC_RAW then
                gyroTranslation(ev)
            end
        end
    elseif self.touch_switch_xy and self.touch_mirrored_y then
        local max_y = self.screen:getHeight() - 1
        koboInputMangling = function(this, ev)
            if ev.type == C.EV_ABS then
                this:adjustABS_SwitchAxesAndMirrorY(ev, max_y)
            elseif ev.type == C.EV_MSC and ev.code == C.MSC_RAW then
                gyroTranslation(ev)
            end
        end
    elseif self.touch_switch_xy and not self.touch_mirrored_x and not self.touch_mirrored_y then
        koboInputMangling = function(this, ev)
            if ev.type == C.EV_ABS then
                this:adjustABS_SwitchXY(ev)
            elseif ev.type == C.EV_MSC and ev.code == C.MSC_RAW then
                gyroTranslation(ev)
            end
        end
    end
    if koboInputMangling then
        self.input:registerEventAdjustHook(koboInputMangling)
    end
end

local function getCodeName()
    -- Try to get it from the env first
    local codename = os.getenv("PRODUCT")
    -- If that fails, run the script ourselves
    if not codename then
        local std_out = io.popen("/bin/kobo_config.sh 2>/dev/null", "re")
        if std_out then
            codename = std_out:read("*line")
            std_out:close()
        end
    end
    return codename
end

function Kobo:getFirmwareVersion()
    local version_file = io.open("/mnt/onboard/.kobo/version", "re")
    if not version_file then
        self.firmware_rev = "none"
        return
    end
    local version_str = version_file:read("*line")
    version_file:close()

    local i = 1
    for field in version_str:gmatch("([^,]+)") do
        if i == 3 then
            self.firmware_rev = field
            break
        end
        i = i + 1
    end
end

local function getProductId()
    -- Try to get it from the env first (KSM only)
    local product_id = os.getenv("MODEL_NUMBER")
    -- If that fails, devise it ourselves
    if not product_id then
        local version_file = io.open("/mnt/onboard/.kobo/version", "re")
        if not version_file then
            return "000"
        end
        local version_str = version_file:read("*line")
        version_file:close()

        product_id = string.sub(version_str, -3, -1)
    end

    return product_id
end

-- NOTE: We overload this to make sure checkUnexpectedWakeup doesn't trip *before* the newly scheduled suspend
function Kobo:rescheduleSuspend()
    UIManager:unschedule(self.suspend)
    UIManager:unschedule(self._doSuspend)
    UIManager:unschedule(self.checkUnexpectedWakeup)
    UIManager:scheduleIn(self.suspend_wait_timeout, self.suspend, self)
end

function Kobo:scheduleUnexpectedWakeupGuard()
    self.unexpected_wakeup_count = self.unexpected_wakeup_count + 1
    logger.dbg("Kobo suspend: scheduling unexpected wakeup guard")
    UIManager:scheduleIn(15, self.checkUnexpectedWakeup, self)
end

function Kobo:checkUnexpectedWakeup()
    -- Just in case another event like SleepCoverClosed also scheduled a suspend
    UIManager:unschedule(self.suspend)

    -- The proximity window is rather large, because we're scheduled to run 15 seconds after resuming,
    -- so we're already guaranteed to be at least 15s away from the alarm ;).
    if self.wakeup_mgr:isWakeupAlarmScheduled() and self.wakeup_mgr:wakeupAction(30) then
        -- Assume we want to go back to sleep after running the scheduled action
        -- (Kobo:resume will unschedule this on an user-triggered resume).
        logger.info("Kobo suspend: scheduled wakeup; the device will go back to sleep in 30s.")
        -- We need significant leeway for the poweroff action to send out close events to all requisite widgets,
        -- since we don't actually want to suspend behind its back ;).
        UIManager:scheduleIn(30, self.suspend, self)
    else
        -- We've hit an early resume, assume this is unexpected (as we only run if Kobo:resume hasn't already).
        logger.dbg("Kobo suspend: checking unexpected wakeup number", self.unexpected_wakeup_count)
        if self.unexpected_wakeup_count > 20 then
            -- If we've failed to put the device back to sleep over 20 consecutive times, we give up.
            -- Broadcast a specific event, so that AutoSuspend can pick up the baton...
            local Event = require("ui/event")
            UIManager:broadcastEvent(Event:new("UnexpectedWakeupLimit"))
            return
        end

        logger.err("Kobo suspend: putting device back to sleep after", self.unexpected_wakeup_count, "unexpected wakeups.")
        self:suspend()
    end
end

--- The function to put the device into standby, with enabled touchscreen.
-- max_duration ... maximum time for the next standby, can wake earlier (e.g. Tap, Button ...)
function Kobo:standby(max_duration)
    -- On MTK, any suspend/standby attempt while plugged-in will hang the kernel... -_-"
    -- NOTE: isCharging is still true while isCharged!
    if self:isMTK() and self.powerd:isCharging() then
        logger.info("Kobo standby: skipping the standby request for now: device is plugged in and would otherwise crash!")

        return
    end

    -- NOTE: Switch to the performance CPU governor, in order to speed up the resume process so as to lower its latency cost...
    --       (It won't have any impact on power efficiency *during* suspend, so there's not really any drawback).
    self:performanceCPUGovernor()

    --[[
    -- On most devices, attempting to PM with a Wi-Fi module loaded will horribly crash the kernel, so, don't?
    -- NOTE: Much like suspend, our caller should ensure this never happens, hence this being commented out ;).
    if NetworkMgr:isWifiOn() then
        -- AutoSuspend relies on NetworkMgr:getWifiState to prevent this, so, if we ever trip this, it's a bug ;).
        logger.err("Kobo standby: cannot standby with Wi-Fi modules loaded! (NetworkMgr is confused: this is a bug)")
        return
    end
    --]]

    -- We don't really have anything to schedule, we just need an alarm out of WakeupMgr ;).
    local function standby_alarm()
    end

    if max_duration then
        self.wakeup_mgr:addTask(max_duration, standby_alarm)
    end

    logger.dbg("Kobo standby: asking to enter standby . . .")
    local standby_time = time.boottime_or_realtime_coarse()

    -- The odd Sunxi needs some time to settle before entering standby.
    -- This will avoid the screen puzzling effect documented in
    -- https://github.com/koreader/koreader/pull/10306#issue-1659242042 not only for
    -- WiFi toggle, but (almost) everywhere.
    ffiUtil.usleep(90000) -- sleep 0.09s (0.08s would also work)

    local ret = ffiUtil.writeToSysfs(self.standby_state, "/sys/power/state")

    self.last_standby_time = time.boottime_or_realtime_coarse() - standby_time
    self.total_standby_time = self.total_standby_time + self.last_standby_time

    if ret then
        logger.dbg("Kobo standby: zZz zZz zZz zZz... And woke up!")
        if G_reader_settings:isTrue("pm_debug_entry_failure") then
            -- NOTE: This is a debug option where we coopt the charging LED, hence us not using setupChargingLED here.
            --       (It's called on resume anyway).
            self:toggleChargingLED(false)
        end
    else
        logger.warn("Kobo standby: the kernel refused to enter standby!")
        if G_reader_settings:isTrue("pm_debug_entry_failure") then
            self:toggleChargingLED(true)
        end
    end

    if max_duration then
        -- NOTE: We don't actually care about discriminating exactly *why* we woke up,
        --       and our scheduled wakeup action is a NOP anyway,
        --       so we can just drop the task instead of doing things the right way like suspend ;).
        --       This saves us some pointless RTC shenanigans, so, everybody wins.
        --[[
        -- There's no scheduling shenanigans like in suspend, so the proximity window can be much tighter...
        if self.wakeup_mgr:isWakeupAlarmScheduled() and self.wakeup_mgr:wakeupAction(5) then
            -- We tripped the standby alarm, UIManager will be able to run whatever was actually scheduled,
            -- and AutoSuspend will handle going back to standby if necessary.
            logger.dbg("Kobo standby: tripped rtc wake alarm")
        end
        --]]
        self.wakeup_mgr:removeTasks(nil, standby_alarm)
    end

    -- And restore the standard CPU scheduler once we're done dealing with the wakeup event.
    UIManager:tickAfterNext(self.defaultCPUGovernor, self)
end

function Kobo:suspend()
    -- If there's a _doSuspend still scheduled, something is going seriously wrong
    -- (e.g., we caught multiple Suspend events without a Resume in between)...
    if UIManager:unschedule(self._doSuspend) then
        logger.warn("Kobo suspend: cancelled a pending suspend request via *suspend*. This is most likely a bug.")
    end

    -- On MTK, any suspend/standby attempt while plugged-in will hang the kernel... -_-"
    -- NOTE: isCharging is still true while isCharged!
    if self:isMTK() and self.powerd:isCharging() then
        logger.info("Kobo suspend: skipping the suspend request for now: device is plugged in and would otherwise crash!")

        -- Do the usual scheduling dance, so we get a chance to fire the UnexpectedWakeupLimit event...
        UIManager:unschedule(self.checkUnexpectedWakeup)
        self:scheduleUnexpectedWakeupGuard()
        return
    end

    -- Murder Wi-Fi (again, c.f., `Device:onPowerEvent`) if NetworkMgr is attempting to connect or currently connected...
    -- (Most likely because of a rerunWhenOnline in a Suspend handler)
    local network_mgr = require("ui/network/manager")
    if network_mgr:isWifiOn() then
        logger.info("Kobo suspend: had to kill Wi-Fi")
        network_mgr:disableWifi()
    end

    logger.info("Kobo suspend: going to sleep . . .")
    UIManager:unschedule(self.checkUnexpectedWakeup)
    -- NOTE: Sleep as little as possible here, sleeping has a tendency to make
    --       everything mysteriously hang...

    -- NOTE: Sets gSleep_Mode_Suspend to 1. Used as a flag throughout the
    --       kernel to suspend/resume various subsystems
    --       c.f., state_extended_store @ kernel/power/main.c
    local ret = ffiUtil.writeToSysfs("1", "/sys/power/state-extended")
    if ret then
        logger.dbg("Kobo suspend: successfully asked the kernel to put subsystems to sleep")
    else
        logger.err("Kobo suspend: the kernel refused to flag subsystems for suspend, aborting this attempt!")
        -- We'd be going to standby instead of suspend, so, just try again later.
        self:scheduleUnexpectedWakeupGuard()
        return
    end

    -- NOTE: As nonsensical as it looks given that the above just flips a global,
    --       I have traumatic memories of things going awry if we don't sleep between the two writes...
    logger.dbg("Kobo suspend: waiting for 2s because of reasons...")
    -- We keep polling for input in order to be able to catch power events with extremely unlucky timing (#12325)...
    UIManager:scheduleIn(2, self._doSuspend, self)
end

function Kobo:_doSuspend()
    os.execute("sync")
    logger.dbg("Kobo suspend: synced FS")

    -- Depending on device/FW version, some kernels do not support wakeup_count, account for that.
    -- NOTE: ...and of course, it appears to be broken on older devices,
    --       which probably explains why nickel doesn't use this facility there...
    --       (By broken, I mean that the system wakes up right away despite the successful write).
    --       As we can't really divine where and when it'll work properly, unconditionally disable it.
    --[[
    if self.has_wakeup_count then
        self.curr_wakeup_count = self.powerd:read_int_file("/sys/power/wakeup_count")
        logger.dbg("Kobo suspend: Current WakeUp count:", self.curr_wakeup_count)

        local ret = ffiUtil.writeToSysfs(self.curr_wakeup_count, "/sys/power/wakeup_count")
        if ret then
            logger.dbg("Kobo suspend: WakeUp count matched")
        else
            logger.err("Kobo suspend: WakeUp count mismatch, aborting this suspend attempt!")
            -- This means that there was at least one wakeup event since our read,
            -- abort this attempt (i.e., don't write to state for now) and just schedule the wakeup guard.
            self:scheduleUnexpectedWakeupGuard()
            return
        end
    end
    --]]

    logger.dbg("Kobo suspend: asking for a suspend to RAM . . .")
    local suspend_time = time.boottime_or_realtime_coarse()

    local ret = ffiUtil.writeToSysfs("mem", "/sys/power/state")

    -- NOTE: At this point, we *should* be in suspend to RAM, as such,
    --       execution should only resume on wakeup...
    self.last_suspend_time = time.boottime_or_realtime_coarse() - suspend_time
    self.total_suspend_time = self.total_suspend_time + self.last_suspend_time

    if ret then
        logger.info("Kobo suspend: ZzZ ZzZ ZzZ... And woke up!")
        if G_reader_settings:isTrue("pm_debug_entry_failure") then
            self:toggleChargingLED(false)
        end
    else
        -- Most of the potential failures ought to be -EBUSY
        -- (usually, because of the EPDC or touch panel).
        -- NOTE: On recent enough kernels, with debugfs enabled and mounted, see also
        --       /sys/kernel/debug/suspend_stats & /sys/kernel/debug/wakeup_sources
        logger.warn("Kobo suspend: the kernel refused to enter suspend!")
        -- NOTE: Despite it making little sense,
        --       we reset state-extended back to 0 to mimic Nickel's own
        --       1 -> mem -> 0 loop in case of suspend failures...
        --       c.f., nickel_suspend_strace.txt for more details.
        ffiUtil.writeToSysfs("0", "/sys/power/state-extended")
        if G_reader_settings:isTrue("pm_debug_entry_failure") then
            self:toggleChargingLED(true)
        end
    end

    -- NOTE: We unflag /sys/power/state-extended in Kobo:resume() to keep
    --       things tidy and easier to follow
    -- Kobo:resume() will also reset unexpected_wakeup_count and unschedule the check to signal a sane wakeup.
    self:scheduleUnexpectedWakeupGuard()
end

function Kobo:resume()
    logger.dbg("Kobo resume: clean up after wakeup")
    -- Reset unexpected_wakeup_count ASAP
    self.unexpected_wakeup_count = 0
    -- Unschedule the checkUnexpectedWakeup shenanigans.
    UIManager:unschedule(self.checkUnexpectedWakeup)
    UIManager:unschedule(self.suspend)
    -- Cancel any pending suspend request
    if UIManager:unschedule(self._doSuspend) then
        logger.info("Kobo resume: cancelled a pending suspend request")
    end

    -- Now that we're up, unflag subsystems for suspend...
    -- NOTE: Sets gSleep_Mode_Suspend to 0. Used as a flag throughout the
    --       kernel to suspend/resume various subsystems
    --       cf. kernel/power/main.c @ L#207
    --       Among other things, this sets up the wakeup pins (e.g., resume on input).
    local ret = ffiUtil.writeToSysfs("0", "/sys/power/state-extended")
    if ret then
        logger.dbg("Kobo resume: successfully asked the kernel to resume subsystems")
    else
        logger.warn("Kobo resume: the kernel refused to flag subsystems for resume!")
    end

    -- HACK: wait a bit (0.1 sec) for the kernel to catch up
    ffiUtil.usleep(100000)

    if self.hasIRGridSysfsKnob then
        -- cf. #1862, I can reliably break IR touch input on resume...
        -- cf. also #1943 for the rationale behind applying this workaround in every case...
        -- c.f., neo_ctl @ drivers/input/touchscreen/zforce_i2c.c,
        -- basically, a is wakeup (for activate), d is sleep (for deactivate), and we don't care about s (set res),
        -- and l (led signal level, actually a NOP on NTX kernels).
        ffiUtil.writeToSysfs("a", self.hasIRGridSysfsKnob)
    end

    -- A full suspend may have toggled the LED off.
    self:setupChargingLED()
end

function Kobo:usbPlugOut()
    -- Rewind the unexpected wakeup counter, since we're no longer charging, meaning power savings are now critical again ;).
    -- NOTE: We don't reset it to 0 because, semantically, only resume should ever be allowed to do so.
    if self.unexpected_wakeup_count > 0 then
        self.unexpected_wakeup_count = 1
    end
end

function Kobo:saveSettings()
    -- save frontlight state to G_reader_settings (and NickelConf if needed)
    self.powerd:saveSettings()
end

function Kobo:powerOff()
    -- Much like Nickel itself, disable the RTC alarm before powering down.
    self.wakeup_mgr:unsetWakeupAlarm()

    --- @todo: Check on MTK
    if self:isSunxi() or self:isMTK() then
        -- On sunxi, apparently, we *do* go through init
        os.execute("sleep 1 && poweroff &")
    else
        -- Then shut down without init's help
        os.execute("sleep 1 && poweroff -f &")
    end
end

function Kobo:reboot()
    os.execute("sleep 1 && reboot &")
end

function Kobo:_NTXChargingLEDToggle(toggle)
    -- NOTE: While most/all Kobos actually have a charging LED, and it can usually be fiddled with in a similar fashion,
    --       we've seen *extremely* weird behavior in the past when playing with it on older devices (c.f., #5479).
    --       In fact, Nickel itself doesn't provide this feature on said older devices
    --       (when it does, it's an option in the Energy saving settings),
    --       which is why we also limit ourselves to "true" on devices where this was tested.
    -- c.f., drivers/misc/ntx_misc_light.c
    local fd = C.open(self.ntx_lit_sysfs_knob, bit.bor(C.O_WRONLY, C.O_CLOEXEC)) -- procfs/sysfs, we shouldn't need O_TRUNC
    if fd == -1 then
        logger.err("Cannot open file `" .. self.ntx_lit_sysfs_knob .. "`:", ffi.string(C.strerror(ffi.errno())))
        return false
    end

    -- c.f., strace -fittTvyy -e trace=ioctl,file,signal,ipc,desc -s 256 -o /tmp/nickel.log -p $(pidof -s nickel) &
    -- This was observed on a Forma, so I'm mildly hopeful that it's safe on other Mk. 7 devices ;).
    -- NOTE: ch stands for channel, cur for current, dc for duty cycle. c.f., the driver source.
    if toggle == true then
        -- NOTE: Technically, Nickel forces a toggle off before that, too.
        --       But since we do that on startup, it shouldn't be necessary here...
        for ch = self.led_uses_channel_3 and 3 or 4, 4 do
            C.write(fd, "ch " .. tostring(ch), 4)
            C.write(fd, "cur 1", 5)
            C.write(fd, "dc 63", 5)
        end
    else
        for ch = 3, 5 do
            C.write(fd, "ch " .. tostring(ch), 4)
            C.write(fd, "cur 1", 5)
            C.write(fd, "dc 0", 4)
        end
    end

    C.close(fd)
end

function Kobo:_LinuxChargingLEDToggle(toggle)
    -- max_brightness usually says 255 for those, but 1 does the same (and matches Nickel's behavior)
    ffiUtil.writeToSysfs(toggle and "1" or "0", self.charging_led_sysfs_knob)
end

function Kobo:toggleChargingLED(toggle)
    -- We have no way of querying the current state from the HW!
    if toggle == nil then
        return
    end
    -- Don't do anything if the state is already correct
    -- NOTE: What happens to the LED when attempting/successfully entering PM is... kind of a mess.
    --       On a H2O, even *attempting* to enter PM will kill the light (and it'll stay off).
    --       On a Forma, a failed attempt will *not* affect the light, but a successful one *will* kill it,
    --       be that standby or suspend, but it'll be restored on wakeup...
    --       On sunxi, PM appears to have zero effect on the LED.
    if self.charging_led_state == toggle then
        return
    end
    self.charging_led_state = toggle
    logger.dbg("Kobo: Turning the charging LED", toggle and "on" or "off")

    return self:charging_led_imp(toggle)
end

-- Return the highest core number
function Kobo:getCPUCount()
    local fd = io.open("/sys/devices/system/cpu/possible", "re")
    if fd then
        local str = fd:read("*line")
        fd:close()

        -- Format is n-N, where n is the first core, and N the last (e.g., 0-3)
        return tonumber(str:match("%d+$")) or 1
    else
        return 1
    end
end

function Kobo:enableCPUCores(amount)
    -- CPU0 is *always* online ;).
    for n = 1, self.cpu_count do
        local path = "/sys/devices/system/cpu/cpu" .. n .. "/online"
        local up
        if n >= amount then
            up = "0"
        else
            up = "1"
        end

        ffiUtil.writeToSysfs(up, path)
    end
end

function Kobo:performanceCPUGovernor()
    ffiUtil.writeToSysfs("performance", self.cpu_governor_knob)
end

function Kobo:defaultCPUGovernor()
    ffiUtil.writeToSysfs(self.default_cpu_governor, self.cpu_governor_knob)
end

function Kobo:isStartupScriptUpToDate()
    -- Compare the hash of the *active* script (i.e., the one in /tmp) to the *potential* one (i.e., the one in KOREADER_DIR)
    local current_script = "/tmp/koreader.sh"
    local new_script = os.getenv("KOREADER_DIR") .. "/" .. "koreader.sh"

    local md5 = require("ffi/MD5")
    return md5.sumFile(current_script) == md5.sumFile(new_script)
end

function Kobo:UIManagerReady(uimgr)
    UIManager = uimgr
end

function Kobo:setEventHandlers(uimgr)
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
    -- Sleep Cover handling
    if G_reader_settings:isTrue("ignore_power_sleepcover") then
        -- NOTE: The hardware event itself will wake the kernel up if it's in suspend (:/).
        --       Let the unexpected wakeup guard handle that.
        UIManager.event_handlers.SleepCoverClosed = nil
        UIManager.event_handlers.SleepCoverOpened = nil
    elseif G_reader_settings:isTrue("ignore_open_sleepcover") then
        -- Just ignore wakeup events, and do NOT set is_cover_closed,
        -- so device/generic/device will let us use the power button to wake ;).
        UIManager.event_handlers.SleepCoverClosed = function()
            UIManager.event_handlers.Suspend()
        end
        UIManager.event_handlers.SleepCoverOpened = function()
            self.is_cover_closed = false
        end
    else
        UIManager.event_handlers.SleepCoverClosed = function()
            self.is_cover_closed = true
            UIManager.event_handlers.Suspend()
        end
        UIManager.event_handlers.SleepCoverOpened = function()
            self.is_cover_closed = false
            UIManager.event_handlers.Resume()
        end
    end
end

-------------- device probe ------------

local codename = getCodeName()
local product_id = getProductId()

if codename == "dahlia" then
    return KoboDahlia
elseif codename == "dragon" then
    return KoboDragon
elseif codename == "kraken" then
    return KoboKraken
elseif codename == "phoenix" then
    return KoboPhoenix
elseif codename == "trilogy" and product_id == "310" then
    -- This is where things get interesting...
    -- The early 'A' variant (the actual model name being N905, without any letter suffix, unlike the two other variants)
    -- does *NOT* feature an internal SD card, and is manufactured in China instead of Taiwan... because it is *NOT* an NTX board.
    -- cf. https://github.com/koreader/koreader/issues/9742
    if os.getenv("PLATFORM") == "freescale" then
        return KoboTrilogyA
    else
        return KoboTrilogyB
    end
elseif codename == "trilogy" and product_id == "320" then
    return KoboTrilogyC
elseif codename == "pixie" then
    return KoboPixie
elseif codename == "alyssum" then
    return KoboAlyssum
elseif codename == "pika" then
    return KoboPika
elseif codename == "star" and product_id == "379" then
    return KoboStarRev2
elseif codename == "star" then
    return KoboStar
elseif codename == "daylight" then
    return KoboDaylight
elseif codename == "snow" and product_id == "378" then
    return KoboSnowRev2
elseif codename == "snow" then
    return KoboSnow
elseif codename == "nova" then
    return KoboNova
elseif codename == "frost" then
    return KoboFrost
elseif codename == "storm" then
    return KoboStorm
elseif codename == "luna" then
    return KoboLuna
elseif codename == "europa" then
    return KoboEuropa
elseif codename == "cadmus" then
    return KoboCadmus
elseif codename == "io" then
    return KoboIo
elseif codename == "goldfinch" then
    return KoboGoldfinch
elseif codename == "condor" then
    return KoboCondor
elseif codename == "monza" or codename == "monzaTolino" then
    return KoboMonza
elseif codename == "spaBW" or codename == "spaTolinoBW" then
    return KoboSpaBW
elseif codename == "spaColour" or codename == "spaTolinoColour" then
    return KoboSpaColour
else
    error("unrecognized Kobo model ".. codename .. " with device id " .. product_id)
end
