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
    hasWifiToggle = no,
    isTouchDevice = yes,
    needsScreenRefreshAfterResume = no,
    hasColorScreen = yes,
    hasEinkScreen = no,
    canOpenLink = yes,
    openLink = function(self, link)
        if not link or type(link) ~= "string" then return end
        return os.execute("xdg-open '"..link.."'") == 0
    end,
}

local AppImage = Device:new{
    model = "AppImage",
    hasMultitouch = no,
    hasOTAUpdates = yes,
}

local Emulator = Device:new{
    model = "Emulator",
    isEmulator = yes,
    hasEinkScreen = yes,
    hasFrontlight = yes,
    hasWifiToggle = yes,
    hasWifiManager = yes,
}

local Linux = Device:new{
    model = "Linux",
}

local UbuntuTouch = Device:new{
    model = "UbuntuTouch",
    hasFrontlight = yes,
}

function Device:init()
    local emulator = self.isEmulator
    -- allows to set a viewport via environment variable
    -- syntax is Lua table syntax, e.g. EMULATE_READER_VIEWPORT="{x=10,w=550,y=5,h=790}"
    local viewport = os.getenv("EMULATE_READER_VIEWPORT")
    if emulator and viewport then
        self.viewport = require("ui/geometry"):new(loadstring("return " .. viewport)())
    end

    local touchless = os.getenv("DISABLE_TOUCH") == "1"
    if emulator and touchless then
        self.isTouchDevice = no
    end

    local portrait = os.getenv("EMULATE_READER_FORCE_PORTRAIT")
    if emulator and portrait then
        self.isAlwaysPortrait = yes
    end

    if util.haveSDL2() then
        self.hasClipboard = yes
        self.screen = require("ffi/framebuffer_SDL2_0"):new{device = self, debug = logger.dbg}

        local ok, re = pcall(self.screen.setWindowIcon, self.screen, "resources/koreader.png")
        if not ok then logger.warn(re) end

        local input = require("ffi/input")
        self.input = require("device/input"):new{
            device = self,
            event_map = require("device/sdl/event_map_sdl2"),
            handleSdlEv = function(device_input, ev)
                local Geom = require("ui/geometry")
                local TimeVal = require("ui/timeval")
                local UIManager = require("ui/uimanager")

                -- SDL events can remain cdata but are almost completely transparent
                local SDL_MOUSEWHEEL = 1027
                local SDL_MULTIGESTURE = 2050
                local SDL_DROPFILE = 4096
                local SDL_WINDOWEVENT_RESIZED = 5

                if ev.code == SDL_MOUSEWHEEL then
                    local scrolled_x = ev.value.x
                    local scrolled_y = ev.value.y

                    local up = 1
                    local down = -1

                    local pos = Geom:new{
                        x = 0,
                        y = 0,
                        w = 0, h = 0,
                    }

                    local timev = TimeVal:new(ev.time)

                    local fake_ges = {
                        ges = "pan",
                        distance = 200,
                        distance_delayed = 200,
                        relative = {
                            x = 50*scrolled_x,
                            y = 100*scrolled_y,
                        },
                        relative_delayed = {
                            x = 50*scrolled_x,
                            y = 100*scrolled_y,
                        },
                        pos = pos,
                        time = timev,
                    }
                    local fake_ges_release = {
                        ges = "pan_release",
                        distance = fake_ges.distance,
                        distance_delayed = fake_ges.distance_delayed,
                        relative = fake_ges.relative,
                        relative_delayed = fake_ges.relative_delayed,
                        pos = pos,
                        time = timev,
                    }
                    local fake_pan_ev = Event:new("Pan", nil, fake_ges)
                    local fake_release_ev = Event:new("Gesture", fake_ges_release)

                    if scrolled_y == down then
                        fake_ges.direction = "north"
                        UIManager:broadcastEvent(fake_pan_ev)
                        UIManager:broadcastEvent(fake_release_ev)
                    elseif scrolled_y == up then
                        fake_ges.direction = "south"
                        UIManager:broadcastEvent(fake_pan_ev)
                        UIManager:broadcastEvent(fake_release_ev)
                    end
                elseif ev.code == SDL_MULTIGESTURE then
                    -- no-op for now
                    do end -- luacheck: ignore 541
                elseif ev.code == SDL_DROPFILE then
                    local dropped_file_path = ev.value
                    if dropped_file_path and dropped_file_path ~= "" then
                        local ReaderUI = require("apps/reader/readerui")
                        ReaderUI:doShowReader(dropped_file_path)
                    end
                elseif ev.code == SDL_WINDOWEVENT_RESIZED then
                    device_input.device.screen.screen_size.w = ev.value.data1
                    device_input.device.screen.screen_size.h = ev.value.data2
                    device_input.device.screen.resize(device_input.device.screen, ev.value.data1, ev.value.data2)

                    local new_size = device_input.device.screen:getSize()
                    logger.dbg("Resizing screen to", new_size)

                    -- try to catch as many flies as we can
                    -- this means we can't just return one ScreenResize or SetDimensons event
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
            file_chooser = input.file_chooser,
        }
    else
        self.screen = require("ffi/framebuffer_SDL1_2"):new{device = self, debug = logger.dbg}
        self.input = require("device/input"):new{
            device = self,
            event_map = require("device/sdl/event_map_sdl"),
        }
    end

    self.keyboard_layout = require("device/sdl/keyboard_layout")

    if emulator and portrait then
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

-------------- device probe ------------
if os.getenv("APPIMAGE") then
    return AppImage
elseif os.getenv("KO_MULTIUSER") then
    return Linux
elseif os.getenv("UBUNTU_APPLICATION_ISOLATION") then
    return UbuntuTouch
else
    return Emulator
end
