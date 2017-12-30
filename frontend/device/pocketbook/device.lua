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
local KEY_COVEROPEN	= 0x02
local KEY_COVERCLOSE	= 0x03
-- luacheck: pop

ffi.cdef[[
char *GetSoftwareVersion(void);
char *GetDeviceModel(void);
]]

local function yes() return true end
local function no() return false end

local function pocketbookEnableWifi(toggle)
    os.execute("/ebrmain/bin/netagent " .. (toggle == 1 and "connect" or "disconnect"))
end

local PocketBook = Generic:new{
    model = "PocketBook",
    isPocketBook = yes,
    isInBackGround = false,
}

function PocketBook:init()
    self.screen = require("ffi/framebuffer_mxcfb"):new{device = self, debug = logger.dbg}
    self.powerd = require("device/pocketbook/powerd"):new{device = self}
    self.input = require("device/input"):new{
        device = self,
        event_map = {
            [KEY_MENU] = "Menu",
            [KEY_PREV] = "LPgBack",
            [KEY_NEXT] = "LPgFwd",
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
    NetworkMgr.turnOnWifi = function()
        pocketbookEnableWifi(1)
    end

    NetworkMgr.turnOffWifi = function()
        pocketbookEnableWifi(0)
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
    isTouchDevice = yes,
    hasKeys = yes,
    hasFrontlight = yes,
    display_dpi = 250,
    emu_events_dev = "/var/dev/shm/emu_events",
}

-- PocketBook HD Touch
local PocketBook631 = PocketBook:new{
    isTouchDevice = yes,
    hasKeys = yes,
    hasFrontlight = yes,
    display_dpi = 300,
    emu_events_dev = "/dev/shm/emu_events",
}

-- PocketBook Lux 3
local PocketBook626 = PocketBook:new{
    isTouchDevice = yes,
    hasKeys = yes,
    hasFrontlight = yes,
    display_dpi = 212,
    emu_events_dev = "/var/dev/shm/emu_events",
}

-- PocketBook Basic Touch
local PocketBook624 = PocketBook:new{
    isTouchDevice = yes,
    hasKeys = yes,
    hasFrontlight = no,
    display_dpi = 166,
    emu_events_dev = "/var/dev/shm/emu_events",
}

-- PocketBook Touch Lux
local PocketBook623 = PocketBook:new{
    isTouchDevice = yes,
    hasKeys = yes,
    hasFrontlight = yes,
    display_dpi = 212,
    emu_events_dev = "/var/dev/shm/emu_events",
}

logger.info('SoftwareVersion: ', PocketBook:getSoftwareVersion())

local codename = PocketBook:getDeviceModel()

if codename == "PocketBook 840" then
    return PocketBook840
elseif codename == "PB631" then
    return PocketBook631
elseif codename == "PocketBook 626" then
    return PocketBook626
elseif codename == "PocketBook 624" then
    return PocketBook624
elseif codename == "PocketBook 623" then
    return PocketBook623
else
    error("unrecognized PocketBook model " .. codename)
end
