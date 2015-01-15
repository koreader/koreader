local Generic = require("device/generic/device") -- <= look at this file!
local DEBUG = require("dbg")

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

local function yes() return true end

local PocketBook = Generic:new{
    -- both the following are just for testing similar behaviour
    -- see ffi/framebuffer_mxcfb.lua
    model = "PocketBook",
    isPocketBook = yes,

    isTouchDevice = yes,
    display_dpi = 212,
    touch_dev = "/dev/input/event1", -- probably useless
    emu_events_dev = "/var/dev/shm/emu_events",
}

function PocketBook:init()
    -- this example uses the mxcfb framebuffer driver:
    self.screen = require("ffi/framebuffer_mxcfb"):new{device = self, debug = DEBUG}

    self.input = require("device/input"):new{
        device = self,
        debug = DEBUG,
        event_map = {
            [25] = "LPgBack",
            [24] = "LPgFwd",
            [1002] = "Power",
        }
    }
    -- we inject an input hook for debugging purposes. You probably don't want
    -- it after everything is implemented.
    self.input:registerEventAdjustHook(function(_input, ev)
        DEBUG("ev", ev)
        if ev.type == EVT_KEYDOWN or ev.type == EVT_KEYUP then
            ev.code = ev.code
            ev.value = ev.type == EVT_KEYDOWN and 1 or 0
            ev.type = 1 -- EV_KEY
        end
    end)

    -- no backlight management yet

    os.remove(self.emu_events_dev)
	os.execute("mkfifo " .. self.emu_events_dev)
    self.input.open(self.emu_events_dev, 1)
    Generic.init(self)
end

-- maybe additional implementations are needed for other models,
-- testing on PocketBook Lux 2 for now.

return PocketBook
