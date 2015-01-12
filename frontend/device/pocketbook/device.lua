local Generic = require("device/generic/device") -- <= look at this file!
local DEBUG = require("dbg")

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

    self.input = require("device/input"):new{device = self, debug = DEBUG}
    -- we inject an input hook for debugging purposes. You probably don't want
    -- it after everything is implemented.
    self.input:registerEventAdjustHook(function(event)
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
