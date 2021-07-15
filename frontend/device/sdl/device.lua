local Event = require("ui/event")
local Generic = require("device/generic/device")
local SDL = require("ffi/SDL2_0")
local logger = require("logger")

local function yes() return true end
local function no() return false end
local function notOSX() return jit.os ~= "OSX" end

local function isUrl(s)
    return type(s) == "string" and s:match("*?://")
end

local function isCommand(s)
    return os.execute("which "..s.." >/dev/null 2>&1") == 0
end

local function runCommand(command)
    local env = jit.os ~= "OSX" and 'env -u LD_LIBRARY_PATH ' or ""
    return os.execute(env..command) == 0
end

local function getDesktopDicts()
    local t = {
        { "Goldendict", "Goldendict", false, "goldendict" },
    }
    -- apple dict is always present in osx
    if jit.os == "OSX" then
        table.insert(t, 1, { "Apple", "AppleDict", false, "dict://" })
    end
    return t
end

local function getLinkOpener()
    if jit.os == "Linux" and isCommand("xdg-open") then
        return true, "xdg-open"
    elseif jit.os == "OSX" and isCommand("open") then
        return true, "open"
    end
    return false
end

-- thirdparty app support
local external = require("device/thirdparty"):new{
    dicts = getDesktopDicts(),
    check = function(self, app)
        if (isUrl(app) and getLinkOpener()) or isCommand(app) then
            return true
        end
        return false
    end,
}

local Device = Generic:new{
    model = "SDL",
    isSDL = yes,
    home_dir = os.getenv("XDG_DOCUMENTS_DIR") or os.getenv("HOME"),
    hasBattery = SDL.getPowerInfo(),
    hasKeyboard = yes,
    hasKeys = yes,
    hasDPad = yes,
    hasWifiToggle = no,
    isTouchDevice = yes,
    needsScreenRefreshAfterResume = no,
    hasColorScreen = yes,
    hasEinkScreen = no,
    hasSystemFonts = yes,
    canSuspend = no,
    startTextInput = SDL.startTextInput,
    stopTextInput = SDL.stopTextInput,
    canOpenLink = getLinkOpener,
    openLink = function(self, link)
        local enabled, tool = getLinkOpener()
        if not enabled or not tool or not link or type(link) ~= "string" then return end
        return runCommand(tool .. " '" .. link .. "'")
    end,
    canExternalDictLookup = yes,
    getExternalDictLookupList = function() return external.dicts end,
    doExternalDictLookup = function(self, text, method, callback)
        external.when_back_callback = callback
        local ok, app = external:checkMethod("dict", method)
        if app then
            if isUrl(app) and getLinkOpener() then
                ok = self:openLink(app..text)
            elseif isCommand(app) then
                ok = runCommand(app .. " " .. text .. " &")
            end
        end
        if ok and external.when_back_callback then
            external.when_back_callback()
            external.when_back_callback = nil
        end
    end,
    window = G_reader_settings:readSetting("sdl_window", {}),
}

local AppImage = Device:new{
    model = "AppImage",
    hasMultitouch = no,
    hasOTAUpdates = yes,
    isDesktop = yes,
}

local Desktop = Device:new{
    model = SDL.getPlatform(),
    isDesktop = yes,
    canRestart = notOSX,
    hasExitOptions = notOSX,
}

local Emulator = Device:new{
    model = "Emulator",
    isEmulator = yes,
    hasBattery = yes,
    hasEinkScreen = yes,
    hasFrontlight = yes,
    hasNaturalLight = yes,
    hasNaturalLightApi = yes,
    hasWifiToggle = yes,
    hasWifiManager = yes,
    canPowerOff = yes,
    canReboot = yes,
    canSuspend = yes,
}

local UbuntuTouch = Device:new{
    model = "UbuntuTouch",
    hasFrontlight = yes,
}

function Device:init()
    -- allows to set a viewport via environment variable
    -- syntax is Lua table syntax, e.g. EMULATE_READER_VIEWPORT="{x=10,w=550,y=5,h=790}"
    local viewport = os.getenv("EMULATE_READER_VIEWPORT")
    if viewport then
        self.viewport = require("ui/geometry"):new(loadstring("return " .. viewport)())
    end

    local touchless = os.getenv("DISABLE_TOUCH") == "1"
    if touchless then
        self.isTouchDevice = no
    end

    local portrait = os.getenv("EMULATE_READER_FORCE_PORTRAIT")
    if portrait then
        self.isAlwaysPortrait = yes
    end

    self.hasClipboard = yes
    self.screen = require("ffi/framebuffer_SDL2_0"):new{
        device = self,
        debug = logger.dbg,
        w = self.window.width,
        h = self.window.height,
        x = self.window.left,
        y = self.window.top,
        is_always_portrait = self.isAlwaysPortrait(),
    }
    self.powerd = require("device/sdl/powerd"):new{device = self}

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
            local SDL_TEXTINPUT = 771
            local SDL_MOUSEWHEEL = 1027
            local SDL_MULTIGESTURE = 2050
            local SDL_DROPFILE = 4096
            local SDL_WINDOWEVENT_MOVED = 4
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

                setmetatable(ev.time, TimeVal)

                local fake_ges = {
                    ges = "pan",
                    distance = 200,
                    relative = {
                        x = 50*scrolled_x,
                        y = 100*scrolled_y,
                    },
                    pos = pos,
                    time = ev.time,
                    mousewheel_direction = scrolled_y,
                }
                local fake_ges_release = {
                    ges = "pan_release",
                    distance = fake_ges.distance,
                    relative = fake_ges.relative,
                    pos = pos,
                    time = ev.time,
                    from_mousewheel = true,
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
                self.window.width = ev.value.data1
                self.window.height = ev.value.data2

                local new_size = device_input.device.screen:getSize()
                logger.dbg("Resizing screen to", new_size)

                -- try to catch as many flies as we can
                -- this means we can't just return one ScreenResize or SetDimensons event
                UIManager:broadcastEvent(Event:new("SetDimensions", new_size))
                UIManager:broadcastEvent(Event:new("ScreenResize", new_size))
                --- @todo Toggle this elsewhere based on ScreenResize?

                -- this triggers paged media like PDF and DjVu to redraw
                -- CreDocument doesn't need it
                UIManager:broadcastEvent(Event:new("RedrawCurrentPage"))

                local FileManager = require("apps/filemanager/filemanager")
                if FileManager.instance then
                    FileManager.instance:reinit(FileManager.instance.path,
                        FileManager.instance.focused_file)
                    UIManager:setDirty(FileManager.instance.banner, function()
                        return "ui", FileManager.instance.banner.dimen
                    end)
                end
            elseif ev.code == SDL_WINDOWEVENT_MOVED then
                self.window.left = ev.value.data1
                self.window.top = ev.value.data2
            elseif ev.code == SDL_TEXTINPUT then
                UIManager:sendEvent(Event:new("TextInput", ev.value))
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
        gameControllerRumble = function(left_intensity, right_intensity, duration)
            return input.gameControllerRumble(left_intensity, right_intensity, duration)
        end,
        file_chooser = input.file_chooser,
    }

    self.keyboard_layout = require("device/sdl/keyboard_layout")

    if self.input.gameControllerRumble(0, 0, 0) then
        self.isHapticFeedbackEnabled = yes
        self.performHapticFeedback = function(type)
            self.input.gameControllerRumble()
        end
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

function Emulator:simulateSuspend()
    local InfoMessage = require("ui/widget/infomessage")
    local UIManager = require("ui/uimanager")
    local _ = require("gettext")
    UIManager:show(InfoMessage:new{
        text = _("Suspend")
    })
end

function Emulator:simulateResume()
    local InfoMessage = require("ui/widget/infomessage")
    local UIManager = require("ui/uimanager")
    local _ = require("gettext")
    UIManager:show(InfoMessage:new{
        text = _("Resume")
    })
end

-- fake network manager for the emulator
function Emulator:initNetworkManager(NetworkMgr)
    local UIManager = require("ui/uimanager")
    local connectionChangedEvent = function()
        if G_reader_settings:nilOrTrue("emulator_fake_wifi_connected") then
            UIManager:broadcastEvent(Event:new("NetworkConnected"))
        else
            UIManager:broadcastEvent(Event:new("NetworkDisconnected"))
        end
    end
    function NetworkMgr:turnOffWifi(complete_callback)
        G_reader_settings:flipNilOrTrue("emulator_fake_wifi_connected")
        UIManager:scheduleIn(2, connectionChangedEvent)
    end
    function NetworkMgr:turnOnWifi(complete_callback)
        G_reader_settings:flipNilOrTrue("emulator_fake_wifi_connected")
        UIManager:scheduleIn(2, connectionChangedEvent)
    end
    function NetworkMgr:isWifiOn()
        return G_reader_settings:nilOrTrue("emulator_fake_wifi_connected")
    end
end

io.write("Starting SDL in " .. SDL.getBasePath() .. "\n")

-------------- device probe ------------
if os.getenv("APPIMAGE") then
    return AppImage
elseif os.getenv("KO_MULTIUSER") then
    return Desktop
elseif os.getenv("UBUNTU_APPLICATION_ISOLATION") then
    return UbuntuTouch
else
    return Emulator
end
