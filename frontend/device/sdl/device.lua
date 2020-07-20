local Event = require("ui/event")
local Generic = require("device/generic/device")
local SDL = require("ffi/SDL2_0")
local logger = require("logger")

local function yes() return true end
local function no() return false end

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

local function getLinkOpener()
    if jit.os == "Linux" and isCommand("xdg-open") then
        return true, "xdg-open"
    elseif jit.os == "OSX" and isCommand("open") then
        return true, "open"
    end
    return false
end

local EXTERNAL_DICTS_AVAILABILITY_CHECKED = false
local EXTERNAL_DICTS = require("device/sdl/dictionaries")
local external_dict_when_back_callback = nil

local function getExternalDicts()
    if not EXTERNAL_DICTS_AVAILABILITY_CHECKED then
        EXTERNAL_DICTS_AVAILABILITY_CHECKED = true
        for i, v in ipairs(EXTERNAL_DICTS) do
            local tool = v[4]
            if tool then
                if (isUrl(tool) and getLinkOpener()) or isCommand(tool) then
                    v[3] = true
                end
            end
        end
    end
    return EXTERNAL_DICTS
end


local Device = Generic:new{
    model = "SDL",
    isSDL = yes,
    home_dir = os.getenv("HOME"),
    hasBattery = SDL.getPowerInfo(),
    hasKeyboard = yes,
    hasKeys = yes,
    hasDPad = yes,
    hasWifiToggle = no,
    isTouchDevice = yes,
    needsScreenRefreshAfterResume = no,
    hasColorScreen = yes,
    hasEinkScreen = no,
    canSuspend = no,
    canOpenLink = getLinkOpener,
    openLink = function(self, link)
        local enabled, tool = getLinkOpener()
        if not enabled or not tool or not link or type(link) ~= "string" then return end
        return runCommand(tool .. " '" .. link .. "'")
    end,
    canExternalDictLookup = yes,
    getExternalDictLookupList = getExternalDicts,
    doExternalDictLookup = function(self, text, method, callback)
        external_dict_when_back_callback = callback
        local tool, ok = nil
        for i, v in ipairs(getExternalDicts()) do
            if v[1] == method then
                tool = v[4]
                break
            end
        end
        if isUrl(tool) and getLinkOpener() then
            ok = self:openLink(tool..text)
        elseif isCommand(tool) then
            ok = runCommand(tool .. " " .. text .. " &")
        end
        if ok and external_dict_when_back_callback then
            external_dict_when_back_callback()
            external_dict_when_back_callback = nil
        end
    end,
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
}

local Emulator = Device:new{
    model = "Emulator",
    isEmulator = yes,
    hasBattery = yes,
    hasEinkScreen = yes,
    hasFrontlight = yes,
    hasWifiToggle = yes,
    hasWifiManager = yes,
    canPowerOff = yes,
    canReboot = yes,
    canSuspend = yes,
}

local UbuntuTouch = Device:new{
    model = "UbuntuTouch",
    hasFrontlight = yes,
    home_dir = nil,
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
    self.screen = require("ffi/framebuffer_SDL2_0"):new{device = self, debug = logger.dbg}
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
                    mousewheel_direction = scrolled_y,
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
                --- @todo Toggle this elsewhere based on ScreenResize?

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
