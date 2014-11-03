local Generic = require("device/generic/device")
local util = require("ffi/util")

local function yes() return true end

local Device = Generic:new{
    model = "Emulator",
    isEmulator = yes,
    hasKeyboard = yes,
    hasKeys = yes,
    hasFrontlight = yes,
    isTouchDevice = yes,
}

function Device:init()
    self.screen = require("device/screen"):new{device = self}
    self.input = require("device/input"):new{
        device = self,
        event_map = util.haveSDL2()
            and require("device/emulator/event_map_sdl2")
            or require("device/emulator/event_map_sdl"),
    }

    Generic.init(self)
end

return Device
