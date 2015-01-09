local Generic = require("device/generic/device") -- <= look at this file!
local DEBUG = require("dbg")

local function yes() return true end

local PocketBook = Generic:new{
    -- both the following are just for testing similar behaviour
    -- see ffi/framebuffer_mxcfb.lua
    model = "KindlePaperWhite",
    isKindle = yes,

    isTouchDevice = yes,
    display_dpi = 212,
    touch_dev = "/dev/input/event0",
}

function PocketBook:init()
    -- this example uses the mxcfb framebuffer driver:
    self.screen = require("ffi/framebuffer_mxcfb"):new{device = self, debug = DEBUG}

    -- we inject an input hook for debugging purposes. You probably don't want
    -- it after everything is implemented.
    self.input:registerEventAdjustHook(function(event)
        DEBUG("got event:", event)
    end)

    -- no backlight management yet

    self.input.open("/dev/input/event0")
    self.input.open("/dev/input/event1")
    self.input.open("/dev/input/event2")
    self.input.open("/dev/input/event3")
    Generic.init(self)
end

-- maybe additional implementations are needed for other models,
-- testing on PocketBook Lux 2 for now.

return PocketBook
