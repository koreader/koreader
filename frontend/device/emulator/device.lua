local Generic = require("device/generic/device")
local util = require("ffi/util")
local DEBUG = require("dbg")

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
    -- allows to set a viewport via environment variable
    -- syntax is Lua table syntax, e.g. EMULATE_READER_VIEWPORT="{x=10,w=550,y=5,h=790}"
    local viewport = os.getenv("EMULATE_READER_VIEWPORT")
    if viewport then
        self.viewport = require("ui/geometry"):new(loadstring("return " .. viewport)())
    end
    local portrait = os.getenv("EMULATE_READER_FORCE_PORTRAIT")
    if portrait then
        self.isAlwaysPortrait = yes
    end

    if util.haveSDL2() then
        self.screen = require("ffi/framebuffer_SDL2_0"):new{device = self, debug = DEBUG}
        self.input = require("device/input"):new{
            device = self,
            event_map = require("device/emulator/event_map_sdl2"),
        }
    else
        self.screen = require("ffi/framebuffer_SDL1_2"):new{device = self, debug = DEBUG}
        self.input = require("device/input"):new{
            device = self,
            event_map = require("device/emulator/event_map_sdl"),
        }
    end

    if portrait then
        self.input:registerEventAdjustHook(self.input.adjustTouchSwitchXY)
        self.input:registerEventAdjustHook(
            self.input.adjustTouchMirrorX,
            self.screen:getScreenWidth()
        )
    end

    Generic.init(self)
end

return Device
