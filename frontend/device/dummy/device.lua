local Generic = require("device/generic/device")
local logger = require("logger")

local function yes() return true end
local function no() return false end

local Device = Generic:extend{
    model = "dummy",
    hasKeyboard = no,
    hasKeys = no,
    isTouchDevice = no,
    needsScreenRefreshAfterResume = no,
    hasColorScreen = yes,
    hasEinkScreen = no,
}

function Device:init()
    self.screen = require("ffi/framebuffer_SDL2_0"):new{
        dummy = true,
        device = self,
        debug = logger.dbg,
    }
    Generic.init(self)
end

return Device
