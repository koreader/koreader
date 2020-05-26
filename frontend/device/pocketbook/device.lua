local Generic = require("device/generic/device") -- <= look at this file!
local logger = require("logger")
local ffi = require("ffi")
local inkview = ffi.load("inkview")

-- luacheck: push
-- luacheck: ignore
local EVT_INIT = 21
local EVT_EXIT = 22
local EVT_SHOW = 23
local EVT_REPAINT = 23
local EVT_HIDE = 24
local EVT_KEYDOWN = 25
local EVT_KEYPRESS = 25
local EVT_KEYUP = 26
local EVT_KEYRELEASE = 26
local EVT_KEYREPEAT = 28
local EVT_FOREGROUND = 151
local EVT_BACKGROUND = 152

local KEY_POWER  = 0x01
local KEY_DELETE = 0x08
local KEY_OK     = 0x0a
local KEY_UP     = 0x11
local KEY_DOWN   = 0x12
local KEY_LEFT   = 0x13
local KEY_RIGHT  = 0x14
local KEY_MINUS  = 0x15
local KEY_PLUS   = 0x16
local KEY_MENU   = 0x17
local KEY_PREV   = 0x18
local KEY_NEXT   = 0x19
local KEY_HOME   = 0x1a
local KEY_BACK   = 0x1b
local KEY_PREV2  = 0x1c
local KEY_NEXT2  = 0x1d
local KEY_COVEROPEN = 0x02
local KEY_COVERCLOSE = 0x03

local CONNECTING = 1
local CONNECTED = 2
local NET_OK = 0
-- luacheck: pop

ffi.cdef[[
char *GetSoftwareVersion(void);
char *GetDeviceModel(void);
int GetNetState(void);
int NetConnect(const char *name);
int NetDisconnect();
]]

local function yes() return true end
local function no() return false end


local PocketBook = Generic:new{
    model = "PocketBook",
    isPocketBook = yes,
    isInBackGround = false,
    hasOTAUpdates = yes,
    hasWifiToggle = yes,
    isTouchDevice = yes,
    hasKeys = yes,
    hasFrontlight = yes,
    emu_events_dev = "/dev/shm/emu_events",
}

-- Make sure the C BB cannot be used on devices with a 24bpp fb
function PocketBook:blacklistCBB()
    local dummy = require("ffi/posix_h")
    local C = ffi.C

    -- As well as on those than can't do HW inversion, as otherwise NightMode would be ineffective.
    --- @fixme Either relax the HWInvert check, or actually enable HWInvert on PB if it's safe and it works,
    --        as, currently, no PB device is marked as canHWInvert, so, the C BB is essentially *always* blacklisted.
    if not self:canUseCBB() or not self:canHWInvert() then
        logger.info("Blacklisting the C BB on this device")
        if ffi.os == "Windows" then
            C._putenv("KO_NO_CBB=true")
        else
            C.setenv("KO_NO_CBB", "true", 1)
        end
        -- Enforce the global setting, too, so the Dev menu is accurate...
        G_reader_settings:saveSetting("dev_no_c_blitter", true)
    end
end

function PocketBook:init()
    -- Blacklist the C BB before the first BB require...
    self:blacklistCBB()

    self.screen = require("ffi/framebuffer_mxcfb"):new{device = self, debug = logger.dbg}
    self.powerd = require("device/pocketbook/powerd"):new{device = self}
    self.input = require("device/input"):new{
        device = self,
        event_map = {
            [KEY_MENU] = "Menu",
            [KEY_PREV] = "LPgBack",
            [KEY_NEXT] = "LPgFwd",
            [KEY_UP] = "Up",
            [KEY_DOWN] = "Down",
            [KEY_LEFT] = "Left",
            [KEY_RIGHT] = "Right",
            [KEY_OK] = "Press",
        },
        handleMiscEv = function(this, ev)
            if ev.code == EVT_BACKGROUND then
                self.isInBackGround = true
                return "Suspend"
            elseif ev.code == EVT_FOREGROUND then
                if self.isInBackGround then
                    self.isInBackGround = false
                    return "Resume"
                end
            end
        end,
    }

    -- in contrast to kobo/kindle, pocketbook-devices do not use linux/input
    -- events directly. To be able to use input.lua nevertheless, we make
    -- inkview-events look like linux/input events or handle them directly
    -- here.
    -- Unhandled events will leave Input:waitEvent() as "GenericInput"
    self.input:registerEventAdjustHook(function(_input, ev)
        if ev.type == EVT_KEYDOWN or ev.type == EVT_KEYUP then
            ev.value = ev.type == EVT_KEYDOWN and 1 or 0
            ev.type = 1 -- linux/input.h Key-Event
        end

        -- handle EVT_BACKGROUND and EVT_FOREGROUND as MiscEvent as this makes
        -- it easy to return a string directly which can be used in
        -- uimanager.lua as event_handler index.
        if ev.type == EVT_BACKGROUND or ev.type == EVT_FOREGROUND then
            ev.code = ev.type
            ev.type = 4 -- handle as MiscEvent, see above
        end

        -- auto shutdown event from inkview framework, gracefully close
        -- everything and let the framework shutdown the device
        if ev.type == EVT_EXIT then
            require("ui/uimanager"):broadcastEvent(
                require("ui/event"):new("Close"))
        end
    end)

    -- fix rotation for Color Lux device
    if PocketBook:getDeviceModel() == "PocketBook Color Lux" then
        self.screen.blitbuffer_rotation_mode = 0
        self.screen.native_rotation_mode = 0
    end

    os.remove(self.emu_events_dev)
    os.execute("mkfifo " .. self.emu_events_dev)
    self.input.open(self.emu_events_dev, 1)
    Generic.init(self)
end

function PocketBook:supportsScreensaver() return true end

function PocketBook:setDateTime(year, month, day, hour, min, sec)
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

function PocketBook:initNetworkManager(NetworkMgr)
    function NetworkMgr:turnOnWifi(complete_callback)
        if inkview.NetConnect(nil) ~= NET_OK then
            logger.info('NetConnect failed')
        end
        if complete_callback then
            complete_callback()
        end
    end

    function NetworkMgr:turnOffWifi(complete_callback)
        inkview.NetDisconnect()
        if complete_callback then
            complete_callback()
        end
    end

    function NetworkMgr:isWifiOn()
        return inkview.GetNetState() == CONNECTED
    end
end

function PocketBook:getSoftwareVersion()
    return ffi.string(inkview.GetSoftwareVersion())
end

function PocketBook:getDeviceModel()
    return ffi.string(inkview.GetDeviceModel())
end

-- PocketBook InkPad
local PocketBook840 = PocketBook:new{
    model = "PBInkPad",
    display_dpi = 250,
}

-- PocketBook 515
local PocketBook515 = PocketBook:new{
    model = "PB515",
    display_dpi = 200,
    isTouchDevice = no,
    hasWifiToggle = no,
    hasDPad = yes,
    hasFewKeys = yes,
}

-- PocketBoot 613 Basic
local PocketBook613 = PocketBook:new{
    model = "PB613B",
    display_dpi = 167,
    isTouchDevice = no,
    hasWifiToggle = no,
    hasDPad = yes,
    hasFewKeys = yes,
}

-- PocketBook Basic Lux 2
local PocketBook616 = PocketBook:new{
    model = "PBBLux2",
    display_dpi = 212,
    isTouchDevice = no,
    hasWifiToggle = no,
    hasDPad = yes,
    hasFewKeys = yes,
}

-- PocketBook Lux 4
local PocketBook627 = PocketBook:new{
    model = "PBLux4",
    display_dpi = 212,
}

-- PocketBook Touch HD
local PocketBook631 = PocketBook:new{
    model = "PBTouchHD",
    display_dpi = 300,
}

-- PocketBook Touch HD Plus
local PocketBook632 = PocketBook:new{
    model = "PBTouchHDPlus",
    display_dpi = 300,
    isAlwaysPortrait = yes,
}

-- PocketBook Lux 3
local PocketBook626 = PocketBook:new{
    model = "PBLux3",
    display_dpi = 212,
}

-- PocketBook Basic Touch
local PocketBook624 = PocketBook:new{
    model = "PBBasicTouch",
    hasFrontlight = no,
    display_dpi = 166,
}

-- PocketBook Basic Touch 2
local PocketBook625 = PocketBook:new{
    model = "PBBasicTouch2",
    hasFrontlight = no,
    display_dpi = 166,
}

-- PocketBook Touch
local PocketBook622 = PocketBook:new{
    model = "PBTouch",
    hasFrontlight = no,
    display_dpi = 166,
}

-- PocketBook Touch Lux
local PocketBook623 = PocketBook:new{
    model = "PBTouchLux",
    display_dpi = 212,
}

-- PocketBook InkPad 3
local PocketBook740 = PocketBook:new{
    model = "PBInkPad3",
    isAlwaysPortrait = yes,
    display_dpi = 300,
}

-- PocketBook InkPad 3 Pro
local PocketBook740_2 = PocketBook:new{
    model = "PBInkPad3Pro",
    isAlwaysPortrait = yes,
    display_dpi = 300,
}

-- PocketBook InkPad X
local PocketBook1040 = PocketBook:new{
    model = "PB1040",
    isAlwaysPortrait = yes,
    display_dpi = 227,
}

-- PocketBook Sense
local PocketBook630 = PocketBook:new{
    model = "PBSense",
    display_dpi = 212,
}

-- PocketBook Aqua 2
local PocketBook641 = PocketBook:new{
    model = "PBAqua2",
    display_dpi = 212,
}

-- PocketBook Color Lux
local PocketBookColorLux = PocketBook:new{
    model = "PBColorLux",
    hasColorScreen = yes,
    has3BytesWideFrameBuffer = yes,
    canUseCBB = no, -- 24bpp
}

logger.info('SoftwareVersion: ', PocketBook:getSoftwareVersion())

local codename = PocketBook:getDeviceModel()

if codename == "PocketBook 515" then
    return PocketBook515
elseif codename == "PocketBook 613" then
    return PocketBook613
elseif codename == "PB616W" or
    codename == "PocketBook 616" then
    return PocketBook616
elseif codename == "PocketBook 622" then
    return PocketBook622
elseif codename == "PocketBook 623" then
    return PocketBook623
elseif codename == "PocketBook 624" then
    return PocketBook624
elseif codename == "PB625" then
    return PocketBook625
elseif codename == "PB626" or codename == "PB626(2)-TL3" or
    codename == "PocketBook 626" then
    return PocketBook626
elseif codename == "PB627" then
    return PocketBook627
elseif codename == "PocketBook 630" then
    return PocketBook630
elseif codename == "PB631" then
    return PocketBook631
elseif codename == "PB632" then
    return PocketBook632
elseif codename == "PB641" then
    return PocketBook641
elseif codename == "PB740" then
    return PocketBook740
elseif codename == "PB740-2" then
    return PocketBook740_2
elseif codename == "PB1040" then
    return PocketBook1040
elseif codename == "PocketBook 840" then
    return PocketBook840
elseif codename == "PocketBook Color Lux" then
    return PocketBookColorLux
else
    error("unrecognized PocketBook model " .. codename)
end
