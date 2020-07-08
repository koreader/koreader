local Generic = require("device/generic/device")
local A, android = pcall(require, "android")  -- luacheck: ignore
local Geom = require("ui/geometry")
local ffi = require("ffi")
local C = ffi.C
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local T = require("ffi/util").template

local function yes() return true end
local function no() return false end

local function canUpdateApk()
    -- disable updates on fdroid builds, since they manage their own repo.
    return (android.prop.flavor ~= "fdroid")
end

local function getCodename()
    local api = android.app.activity.sdkVersion
    local codename = ""

    if api > 29 then
        codename = "R"
    elseif api == 29 then
        codename = "Q"
    elseif api == 28 then
        codename = "Pie"
    elseif api == 27 or api == 26 then
        codename = "Oreo"
    elseif api == 25 or api == 24 then
        codename = "Nougat"
    elseif api == 23 then
        codename = "Marshmallow"
    elseif api == 22 or api == 21 then
        codename = "Lollipop"
    elseif api == 19 then
        codename = "KitKat"
    elseif api < 19 and api >= 16 then
        codename = "Jelly Bean"
    elseif api < 16 and api >= 14 then
        codename = "Ice Cream Sandwich"
    end

    return codename
end

local EXTERNAL_DICTS_AVAILABILITY_CHECKED = false
local EXTERNAL_DICTS = require("device/android/dictionaries")
local external_dict_when_back_callback = nil

local function getExternalDicts()
    if not EXTERNAL_DICTS_AVAILABILITY_CHECKED then
        EXTERNAL_DICTS_AVAILABILITY_CHECKED = true
        for i, v in ipairs(EXTERNAL_DICTS) do
            local package = v[4]
            if android.isPackageEnabled(package) then
                v[3] = true
            end
        end
    end
    return EXTERNAL_DICTS
end

local Device = Generic:new{
    isAndroid = yes,
    model = android.prop.product,
    hasKeys = yes,
    hasDPad = no,
    hasExitOptions = no,
    hasEinkScreen = function() return android.isEink() end,
    hasColorScreen = function() return not android.isEink() end,
    hasFrontlight = yes,
    hasLightLevelFallback = yes,
    canRestart = no,
    canSuspend = no,
    firmware_rev = android.app.activity.sdkVersion,
    home_dir = android.getExternalStoragePath(),
    display_dpi = android.lib.AConfiguration_getDensity(android.app.config),
    isHapticFeedbackEnabled = yes,
    hasClipboard = yes,
    hasOTAUpdates = canUpdateApk,
    canOpenLink = yes,
    openLink = function(self, link)
        if not link or type(link) ~= "string" then return end
        return android.openLink(link) == 0
    end,
    canImportFiles = function() return android.app.activity.sdkVersion >= 19 end,
    importFile = function(path) android.importFile(path) end,
    isValidPath = function(path) return android.isPathInsideSandbox(path) end,
    canShareText = yes,
    doShareText = function(text) android.sendText(text) end,

    canExternalDictLookup = yes,
    getExternalDictLookupList = getExternalDicts,
    doExternalDictLookup = function (self, text, method, callback)
        external_dict_when_back_callback = callback
        local package, action = nil
        for i, v in ipairs(getExternalDicts()) do
            if v[1] == method then
                package = v[4]
                action = v[5]
                break
            end
        end
        android.dictLookup(text, package, action)
    end,


    --[[
    Disable jit on some modules on android to make koreader on Android more stable.

    The strategy here is that we only use precious mcode memory (jitting)
    on deep loops like the several blitting methods in blitbuffer.lua and
    the pixel-copying methods in mupdf.lua. So that a small amount of mcode
    memory (64KB) allocated when koreader is launched in the android.lua
    is enough for the program and it won't need to jit other parts of lua
    code and thus won't allocate mcode memory any more which by our
    observation will be harder and harder as we run koreader.
    ]]--
    should_restrict_JIT = true,
}

function Device:init()
    self.screen = require("ffi/framebuffer_android"):new{device = self, debug = logger.dbg}
    self.powerd = require("device/android/powerd"):new{device = self}
    self.input = require("device/input"):new{
        device = self,
        event_map = require("device/android/event_map"),
        handleMiscEv = function(this, ev)
            local UIManager = require("ui/uimanager")
            logger.dbg("Android application event", ev.code)
            if ev.code == C.APP_CMD_SAVE_STATE then
                return "SaveState"
            elseif ev.code == C.APP_CMD_GAINED_FOCUS
                or ev.code == C.APP_CMD_INIT_WINDOW
                or ev.code == C.APP_CMD_WINDOW_REDRAW_NEEDED then
                this.device.screen:_updateWindow()
            elseif ev.code == C.APP_CMD_CONFIG_CHANGED then
                -- orientation and size changes
                if android.screen.width ~= android.getScreenWidth()
                or android.screen.height ~= android.getScreenHeight() then
                    this.device.screen:resize()
                    local new_size = this.device.screen:getSize()
                    logger.info("Resizing screen to", new_size)
                    local Event = require("ui/event")
                    UIManager:broadcastEvent(Event:new("SetDimensions", new_size))
                    UIManager:broadcastEvent(Event:new("ScreenResize", new_size))
                    UIManager:broadcastEvent(Event:new("RedrawCurrentPage"))
                end
                -- to-do: keyboard connected, disconnected
            elseif ev.code == C.APP_CMD_RESUME then
                EXTERNAL_DICTS_AVAILABILITY_CHECKED = false
                if external_dict_when_back_callback then
                    external_dict_when_back_callback()
                    external_dict_when_back_callback = nil
                end
                local new_file = android.getIntent()
                if new_file ~= nil and lfs.attributes(new_file, "mode") == "file" then
                    -- we cannot blit to a window here since we have no focus yet.
                    local InfoMessage = require("ui/widget/infomessage")
                    local BD = require("ui/bidi")
                    UIManager:scheduleIn(0.1, function()
                        UIManager:show(InfoMessage:new{
                            text = T(_("Opening file '%1'."), BD.filepath(new_file)),
                            timeout = 0.0,
                        })
                    end)
                    UIManager:scheduleIn(0.2, function()
                        require("apps/reader/readerui"):doShowReader(new_file)
                    end)
                else
                    -- check if we're resuming from importing content.
                    local content_path = android.getLastImportedPath()
                    if content_path ~= nil then
                        local FileManager = require("apps/filemanager/filemanager")
                        UIManager:scheduleIn(0.5, function()
                            if FileManager.instance then
                                FileManager.instance:onRefresh()
                            else
                                FileManager:showFiles(content_path)
                            end
                        end)
                    end
                end
            end
        end,
        hasClipboardText = function()
            return android.hasClipboardText()
        end,
        getClipboardText = function()
            return android.getClipboardText()
        end,
        setClipboardText = function(text)
            return android.setClipboardText(text)
        end,
    }

    -- check if we have a keyboard
    if android.lib.AConfiguration_getKeyboard(android.app.config)
       == C.ACONFIGURATION_KEYBOARD_QWERTY
    then
        self.hasKeyboard = yes
    end
    -- check if we have a touchscreen
    if android.lib.AConfiguration_getTouchscreen(android.app.config)
       ~= C.ACONFIGURATION_TOUCHSCREEN_NOTOUCH
    then
        self.isTouchDevice = yes
    end

    -- check if we use custom timeouts
    if android.needsWakelocks() then
        android.timeout.set(C.AKEEP_SCREEN_ON_ENABLED)
    else
        local timeout = G_reader_settings:readSetting("android_screen_timeout")
        if timeout then
            if timeout == C.AKEEP_SCREEN_ON_ENABLED
            or (timeout > C.AKEEP_SCREEN_ON_DISABLED
                and android.settings.canWrite()) then
                android.timeout.set(timeout)
            end
        end
    end

    -- check if we disable fullscreen support
    if G_reader_settings:isTrue("disable_android_fullscreen") then
        self:toggleFullscreen()
    end

    -- check if we allow haptic feedback in spite of system settings
    if G_reader_settings:isTrue("haptic_feedback_override") then
        android.setHapticOverride(true)
    end

    -- check if we ignore volume keys and then they're forwarded to system services.
    if G_reader_settings:isTrue("android_ignore_volume_keys") then
        android.setVolumeKeysIgnored(true)
    end

    -- check if we ignore the back button completely
    if G_reader_settings:isTrue("android_ignore_back_button") then
        android.setBackButtonIgnored(true)
    end

    -- check if we enable a custom light level for this activity
    local last_value = G_reader_settings:readSetting("fl_last_level")
    if type(last_value) == "number" and last_value >= 0 then
        Device:setScreenBrightness(last_value)
    end

    Generic.init(self)
end

function Device:initNetworkManager(NetworkMgr)
    function NetworkMgr:turnOnWifi(complete_callback)
        android.openWifiSettings()
    end
    function NetworkMgr:turnOffWifi(complete_callback)
        android.openWifiSettings()
    end

    function NetworkMgr:openSettings()
        android.openWifiSettings()
    end

    function NetworkMgr:isWifiOn()
        local ok = android.getNetworkInfo()
        ok = tonumber(ok)
        if not ok then return false end
        return ok == 1
    end
end

function Device:performHapticFeedback(type)
    android.hapticFeedback(C["AHAPTIC_"..type])
end

function Device:setIgnoreInput(enable)
    android.setIgnoreInput(enable)
end

function Device:retrieveNetworkInfo()
    local ok, type = android.getNetworkInfo()
    ok, type = tonumber(ok), tonumber(type)
    if not ok or not type or type == C.ANETWORK_NONE then
        return _("Not connected")
    else
        if type == C.ANETWORK_WIFI then
            return _("Connected to Wi-Fi")
        elseif type == C.ANETWORK_MOBILE then
            return _("Connected to mobile data network")
        elseif type == C.ANETWORK_ETHERNET then
            return _("Connected to Ethernet")
        elseif type == C.ANETWORK_BLUETOOTH then
            return _("Connected to Bluetooth")
        elseif type == C.ANETWORK_VPN then
            return _("Connected to VPN")
        end
        return _("Unknown connection")
    end
end

function Device:setViewport(x,y,w,h)
    logger.info(string.format("Switching viewport to new geometry [x=%d,y=%d,w=%d,h=%d]",x, y, w, h))
    local viewport = Geom:new{x=x, y=y, w=w, h=h}
    self.screen:setViewport(viewport)
end

function Device:setScreenBrightness(level)
    android.setScreenBrightness(level)
end

function Device:toggleFullscreen()
    local api = android.app.activity.sdkVersion
    if api >= 19 then
        logger.dbg("ignoring fullscreen toggle, reason: always in immersive mode")
    elseif api < 19 and api >= 17 then
        local width = android.getScreenWidth()
        local height = android.getScreenHeight()
        local available_height = android.getScreenAvailableHeight()
        local is_fullscreen = android.isFullscreen()
        android.setFullscreen(not is_fullscreen)
        G_reader_settings:saveSetting("disable_android_fullscreen", is_fullscreen)
        is_fullscreen = android.isFullscreen()
        if is_fullscreen then
            self:setViewport(0, 0, width, height)
        else
            self:setViewport(0, 0, width, available_height)
        end
    else
        logger.dbg("ignoring fullscreen toggle, reason: legacy api " .. api)
    end
end

function Device:info()
    local is_eink, eink_platform = android.isEink()
    local product_type = android.getPlatformName()

    local common_text = T(_("%1\n\nOS: Android %2, api %3\nBuild flavor: %4\n"),
        android.prop.product, getCodename(), Device.firmware_rev, android.prop.flavor)

    local platform_text = ""
    if product_type ~= "android" then
        platform_text = "\n" .. T(_("Device type: %1"), product_type) .. "\n"
    end

    local eink_text = ""
    if is_eink then
        eink_text = "\n" .. T(_("E-ink display supported.\nPlatform: %1"), eink_platform) .. "\n"
    end

    local wakelocks_text = ""
    if android.needsWakelocks() then
        wakelocks_text = "\n" .. _("This device needs CPU, screen and touchscreen always on.\nScreen timeout will be ignored while the app is in the foreground!") .. "\n"
    end

    return common_text..platform_text..eink_text..wakelocks_text
end

function Device:epdTest()
    android.einkTest()
end

function Device:exit()
    android.LOGI(string.format("Stopping %s main activity", android.prop.name));
    android.lib.ANativeActivity_finish(android.app.activity)
end

function Device:canExecuteScript(file)
    local file_ext = string.lower(util.getFileNameSuffix(file))
    if android.prop.flavor ~= "fdroid" and file_ext == "sh"  then
        return true
    end
end

android.LOGI(string.format("Android %s - %s (API %d) - flavor: %s",
    android.prop.version, getCodename(), Device.firmware_rev, android.prop.flavor))

return Device
