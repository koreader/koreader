local Event = require("ui/event")
local Generic = require("device/generic/device")
local util = require("ffi/util")
local logger = require("logger")

local function yes() return true end
local function no() return false end

local Device = Generic:new{
    model = "SDL",
    isSDL = yes,
    hasKeyboard = yes,
    hasKeys = yes,
    hasDPad = yes,
    hasFrontlight = yes,
    isTouchDevice = yes,
    needsScreenRefreshAfterResume = no,
    hasColorScreen = yes,
}

if os.getenv("DISABLE_TOUCH") == "1" then
    Device.isTouchDevice = no
end

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
        self.hasClipboard = yes
        self.screen = require("ffi/framebuffer_SDL2_0"):new{device = self, debug = logger.dbg}

        local input = require("ffi/input")
        self.input = require("device/input"):new{
            device = self,
            event_map = require("device/sdl/event_map_sdl2"),
            handleMiscEv = function(device_input, ev)
                -- bit of a hack for passing SDL events
                local SDL_DROPFILE = 4096
                local SDL_WINDOWEVENT_RESIZED = 5
                local w = 0
                local h = 1

                if ev.code == SDL_DROPFILE then
                    local dropped_file_path = input.getDroppedFilePath()
                    if dropped_file_path and dropped_file_path ~= "" then
                        local ReaderUI = require("apps/reader/readerui")
                        ReaderUI:doShowReader(dropped_file_path)
                    end
                elseif ev.code == w then
                    device_input.new_w = ev.value
                elseif ev.code == h then
                    device_input.new_h = ev.value
                elseif ev.code == SDL_WINDOWEVENT_RESIZED then
                    device_input.device.screen.screen_size.w = device_input.new_w
                    device_input.device.screen.screen_size.h = device_input.new_h
                    device_input.device.screen.resize(device_input.device.screen, device_input.new_w, device_input.new_h)

                    local new_size = device_input.device.screen:getSize()
                    logger.dbg("Resizing screen to", new_size)

                    -- try to catch as many flies as we can
                    -- this means we can't just return one ScreenResize or SetDimensons event
                    local UIManager = require("ui/uimanager")
                    UIManager:broadcastEvent(Event:new("SetDimensions", new_size))
                    UIManager:broadcastEvent(Event:new("ScreenResize", new_size))
                    -- @TODO toggle this elsewhere based on ScreenResize?
                    -- this triggers paged media like PDF and DjVu to redraw
                    -- CreDocument doesn't need it
                    UIManager:broadcastEvent(Event:new("RedrawCurrentPage"))
                end
            end,
            hasClipboardText = function()
                return input.hasClipboardText()
            end,
            getClipboardText = function()
                return input.getClipboardText()
            end,
            setClipboardText = function(text)
                return input.setClipboardText(text)
            end,
        }
    else
        self.screen = require("ffi/framebuffer_SDL1_2"):new{device = self, debug = logger.dbg}
        self.input = require("device/input"):new{
            device = self,
            event_map = require("device/sdl/event_map_sdl"),
        }
    end

    self.keyboard_layout = require("device/sdl/keyboard_layout")

    if portrait then
        self.input:registerEventAdjustHook(self.input.adjustTouchSwitchXY)
        self.input:registerEventAdjustHook(
            self.input.adjustTouchMirrorX,
            self.screen:getScreenWidth()
        )
    end

    Generic.init(self)
end

function Device:setDateTime(year, month, day, hour, min, sec)
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

function Device:simulateSuspend()
    local InfoMessage = require("ui/widget/infomessage")
    local UIManager = require("ui/uimanager")
    local _ = require("gettext")
    UIManager:show(InfoMessage:new{
        text = _("Suspend")
    })
end

function Device:simulateResume()
    local InfoMessage = require("ui/widget/infomessage")
    local UIManager = require("ui/uimanager")
    local _ = require("gettext")
    UIManager:show(InfoMessage:new{
        text = _("Resume")
    })
end

return Device
