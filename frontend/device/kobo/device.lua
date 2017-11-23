local Generic = require("device/generic/device")
local TimeVal = require("ui/timeval")
local Geom = require("ui/geometry")
local util = require("ffi/util")
local _ = require("gettext")
local logger = require("logger")

local function yes() return true end

local function koboEnableWifi(toggle)
    if toggle == 1 then
        os.execute("./enable-wifi.sh")
    else
        os.execute("./disable-wifi.sh")
    end
end


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

-- Kobo Aura One:
local KoboDaylight = Kobo:new{
    model = "Kobo_daylight",
    hasFrontlight = yes,
    touch_probe_ev_epoch_time = true,
    touch_phoenix_protocol = true,
    display_dpi = 300,
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

-- Kobo Aura H2O2:
local KoboSnow = Kobo:new{
    model = "Kobo_snow",
    hasFrontlight = yes,
    touch_alyssum_protocol = true,
    touch_probe_ev_epoch_time = true,
    display_dpi = 265,
    -- the bezel covers the top 11 pixels:
    viewport = Geom:new{x=0, y=11, w=1080, h=1429},
}

-- Kobo Aura second edition:
local KoboStar = Kobo:new{
    model = "Kobo_star",
    hasFrontlight = yes,
    touch_probe_ev_epoch_time = true,
    touch_phoenix_protocol = true,
    display_dpi = 212,
    -- the bezel covers 1-2 pixels on each side:
    viewport = Geom:new{x=1, y=0, w=756, h=1024},
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
    self.screen = require("ffi/framebuffer_mxcfb"):new{device = self, debug = logger.dbg}
    self.powerd = require("device/kobo/powerd"):new{device = self}
    self.input = require("device/input"):new{
        device = self,
        event_map = {
            [59] = "SleepCover",
            [90] = "LightButton",
            [102] = "Home",
            [116] = "Power",
        },
        event_map_adapter = {
            SleepCover = function(ev)
                if self.input:isEvKeyPress(ev) then
                    return "SleepCoverClosed"
                else
                    return "SleepCoverOpened"
                end
            end,
            LightButton = function(ev)
                if self.input:isEvKeyRelease(ev) then
                    return "Light"
                end
            end,
        }
    }

    Generic.init(self)

    -- event2 is for MMA7660 sensor (3-Axis Orientation/Motion Detection)
    self.input.open("/dev/input/event0") -- Light button and sleep slider
    self.input.open("/dev/input/event1")
    -- fake_events is only used for usb plug event so far
    -- NOTE: usb hotplug event is also available in /tmp/nickel-hardware-status
    self.input.open("fake_events")

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
                    local TouchProbe = require("tools/kobo_touch_probe")
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

function Kobo:setDateTime(year, month, day, hour, min, sec)
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

function Kobo:initNetworkManager(NetworkMgr)
    function NetworkMgr:turnOffWifi(complete_callback)
        koboEnableWifi(0)
        if complete_callback then
            complete_callback()
        end
    end

    function NetworkMgr:turnOnWifi(complete_callback)
        koboEnableWifi(1)
        self:showNetworkMenu(complete_callback)
    end

    NetworkMgr:setWirelessBackend(
        "wpa_supplicant", {ctrl_interface = "/var/run/wpa_supplicant/eth0"})

    function NetworkMgr:obtainIP()
        os.execute("./obtain-ip.sh")
    end

    function NetworkMgr:releaseIP()
        os.execute("./release-ip.sh")
    end

    function NetworkMgr:restoreWifiAsync()
        os.execute("./restore-wifi-async.sh")
    end
end

function Kobo:supportsScreensaver() return true end

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

local unexpected_wakeup_count = 0
local function check_unexpected_wakeup()
    logger.dbg("Kobo suspend: checking unexpected wakeup:",
               unexpected_wakeup_count)
    if unexpected_wakeup_count == 0 or unexpected_wakeup_count > 20 then
        -- Don't put device back to sleep under the following two cases:
        --   1. a resume event triggered Kobo:resume() function
        --   2. trying to put device back to sleep more than 20 times after unexpected wakeup
        return
    end

    logger.err("Kobo suspend: putting device back to sleep, unexpected wakeups:",
               unexpected_wakeup_count)
    -- just in case other events like SleepCoverClosed also scheduled a suspend
    require("ui/uimanager"):unschedule(Kobo.suspend)
    Kobo.suspend()
end

function Kobo:getUnexpectedWakeup() return unexpected_wakeup_count end

function Kobo:suspend()
    logger.info("Kobo suspend: going to sleep . . .")
    local UIManager = require("ui/uimanager")
    UIManager:unschedule(check_unexpected_wakeup)
    local f, re, err_msg, err_code
    -- NOTE: Sleep as little as possible here, sleeping has a tendency to make
    -- everything mysteriously hang...

    -- Depending on device/FW version, some kernels do not support
    -- wakeup_count, account for that
    --
    -- NOTE: ... and of course, it appears to be broken, which probably
    -- explains why nickel doesn't use this facility...
    -- (By broken, I mean that the system wakes up right away).
    -- So, unless that changes, unconditionally disable it.

    --[[

    local has_wakeup_count = false
    f = io.open("/sys/power/wakeup_count", "r")
    if f ~= nil then
        io.close(f)
        has_wakeup_count = true
    end

    -- Clear the kernel ring buffer... (we're missing a proper -C flag...)
    --dmesg -c >/dev/null

    -- Go to sleep
    local curr_wakeup_count
    if has_wakeup_count then
        curr_wakeup_count = "$(cat /sys/power/wakeup_count)"
        logger.info("Kobo suspend: Current WakeUp count:", curr_wakeup_count)
    end

    -]]

    -- NOTE: Sets gSleep_Mode_Suspend to 1. Used as a flag throughout the
    -- kernel to suspend/resume various subsystems
    -- cf. kernel/power/main.c @ L#207
    f = io.open("/sys/power/state-extended", "w")
    if not f then
        logger.err("Cannot open /sys/power/state-extended for writing!")
        return false
    end
    re, err_msg, err_code = f:write("1\n")
    io.close(f)
    logger.info("Kobo suspend: asked the kernel to put subsystems to sleep, ret:", re)
    if not re then
        logger.err('write error: ', err_msg, err_code)
    end

    util.sleep(2)
    logger.info("Kobo suspend: waited for 2s because of reasons...")

    os.execute("sync")
    logger.info("Kobo suspend: synced FS")

    --[[

    if has_wakeup_count then
        f = io.open("/sys/power/wakeup_count", "w")
        if not f then
            logger.err("cannot open /sys/power/wakeup_count")
            return false
        end
        re, err_msg, err_code = f:write(tostring(curr_wakeup_count), "\n")
        logger.info("Kobo suspend: wrote WakeUp count:", curr_wakeup_count)
        if not re then
            logger.err("Kobo suspend: failed to write WakeUp count:",
                       err_msg,
                       err_code)
        end
        io.close(f)
    end

    --]]

    logger.info("Kobo suspend: asking for a suspend to RAM . . .")
    f = io.open("/sys/power/state", "w")
    if not f then
        -- reset state-extend back to 0 since we are giving up
        local ext_fd = io.open("/sys/power/state-extended", "w")
        if not ext_fd then
            logger.err("cannot open /sys/power/state-extended for writing!")
        else
            ext_fd:write("0\n")
            io.close(ext_fd)
        end
        return false
    end
    re, err_msg, err_code = f:write("mem\n")
    -- NOTE: At this point, we *should* be in suspend to RAM, as such,
    -- execution should only resume on wakeup...

    logger.info("Kobo suspend: ZzZ ZzZ ZzZ? Write syscall returned: ", re)
    if not re then
        logger.err('write error: ', err_msg, err_code)
    end
    io.close(f)
    -- NOTE: Ideally, we'd need a way to warn the user that suspending
    -- gloriously failed at this point...
    -- We can safely assume that just from a non-zero return code, without
    -- looking at the detailed stderr message
    -- (most of the failures we'll see are -EBUSY anyway)
    -- For reference, when that happens to nickel, it appears to keep retrying
    -- to wakeup & sleep ad nauseam,
    -- which is where the non-sensical 1 -> mem -> 0 loop idea comes from...
    -- cf. nickel_suspend_strace.txt for more details.

    logger.info("Kobo suspend: woke up!")

    --[[

    if has_wakeup_count then
        logger.info("wakeup count: $(cat /sys/power/wakeup_count)")
    end

    -- Print tke kernel log since our attempt to sleep...
    --dmesg -c

    --]]

    -- NOTE: We unflag /sys/power/state-extended in Kobo:resume() to keep
    -- things tidy and easier to follow

    -- Kobo:resume() will reset unexpected_wakeup_count = 0 to signal an
    -- expected wakeup, which gets checked in check_unexpected_wakeup().
    unexpected_wakeup_count = unexpected_wakeup_count + 1
    -- assuming Kobo:resume() will be called in 15 seconds
    logger.dbg("Kobo suspend: scheduing unexpected wakeup guard")
    UIManager:scheduleIn(15, check_unexpected_wakeup)
end

function Kobo:resume()
    logger.info("Kobo resume: clean up after wakeup")
    -- reset unexpected_wakeup_count ASAP
    unexpected_wakeup_count = 0
    require("ui/uimanager"):unschedule(check_unexpected_wakeup)

    -- Now that we're up, unflag subsystems for suspend...
    -- NOTE: Sets gSleep_Mode_Suspend to 0. Used as a flag throughout the
    -- kernel to suspend/resume various subsystems
    -- cf. kernel/power/main.c @ L#207
    local f = io.open("/sys/power/state-extended", "w")
    if not f then
        logger.err("cannot open /sys/power/state-extended for writing!")
        return false
    end
    local re, err_msg, err_code = f:write("0\n")
    io.close(f)
    logger.info("Kobo resume: unflagged kernel subsystems for resume, ret:", re)
    if not re then
        logger.err('write error: ', err_msg, err_code)
    end

    -- HACK: wait a bit (0.1 sec) for the kernel to catch up
    util.usleep(100000)
    -- cf. #1862, I can reliably break IR touch input on resume...
    -- cf. also #1943 for the rationale behind applying this workaorund in every case...
    f = io.open("/sys/devices/virtual/input/input1/neocmd", "r")
    if f ~= nil then
        f:write("a\n")
        io.close(f)
    end
end

function Kobo:saveSettings()
    -- save frontlight state to G_reader_settings (and NickelConf if needed)
    self.powerd:saveSettings()
end

function Kobo:powerOff()
    os.execute("poweroff")
end

function Kobo:reboot()
    os.execute("reboot")
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
elseif codename == "star" then
    return KoboStar
elseif codename == "daylight" then
    return KoboDaylight
elseif codename == "snow" then
    return KoboSnow
else
    error("unrecognized Kobo model "..codename)
end
