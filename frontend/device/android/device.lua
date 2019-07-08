local Generic = require("device/generic/device")
local A, android = pcall(require, "android")  -- luacheck: ignore
local Geom = require("ui/geometry")
local ffi = require("ffi")
local C = ffi.C
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
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

    if api > 27 then
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
    hasEinkScreen = function() return android.isEink() end,
    hasColorScreen = function() return not android.isEink() end,
    hasFrontlight = yes,
    firmware_rev = android.app.activity.sdkVersion,
    display_dpi = android.lib.AConfiguration_getDensity(android.app.config),
    hasClipboard = yes,
    hasOTAUpdates = canUpdateApk,
    canOpenLink = yes,
    openLink = function(self, link)
        if not link or type(link) ~= "string" then return end
        return android.openLink(link) == 0
    end,
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
            logger.dbg("Android application event", ev.code)
            if ev.code == C.APP_CMD_SAVE_STATE then
                return "SaveState"
            elseif ev.code == C.APP_CMD_GAINED_FOCUS
                or ev.code == C.APP_CMD_INIT_WINDOW
                or ev.code == C.APP_CMD_WINDOW_REDRAW_NEEDED then
                this.device.screen:_updateWindow()
            elseif ev.code == C.APP_CMD_RESUME then
                EXTERNAL_DICTS_AVAILABILITY_CHECKED = false
                if external_dict_when_back_callback then
                    external_dict_when_back_callback()
                    external_dict_when_back_callback = nil
                end

                local new_file = android.getIntent()
                if new_file ~= nil and lfs.attributes(new_file, "mode") == "file" then
                    -- we cannot blit to a window here since we have no focus yet.
                    local UIManager = require("ui/uimanager")
                    local InfoMessage = require("ui/widget/infomessage")
                    UIManager:scheduleIn(0.1, function()
                        UIManager:show(InfoMessage:new{
                            text = T(_("Opening file '%1'."), new_file),
                            timeout = 0.0,
                        })
                    end)
                    UIManager:scheduleIn(0.2, function()
                        require("apps/reader/readerui"):doShowReader(new_file)
                    end)
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

    -- check if we enabled support for wakelocks
    if G_reader_settings:isTrue("enable_android_wakelock") or android.needsWakelocks() then
        android.setWakeLock(true)
    end

    -- check if we disable fullscreen support
    if G_reader_settings:isTrue("disable_android_fullscreen") then
        self:toggleFullscreen()
    end

    Generic.init(self)
end

function Device:initNetworkManager(NetworkMgr)
    function NetworkMgr:turnOnWifi(complete_callback)
        android.setWifiEnabled(true)
        if complete_callback then
            local UIManager = require("ui/uimanager")
            UIManager:scheduleIn(1, complete_callback)
        end
    end

    function NetworkMgr:turnOffWifi(complete_callback)
        android.setWifiEnabled(false)
        if complete_callback then
            local UIManager = require("ui/uimanager")
            UIManager:scheduleIn(1, complete_callback)
        end
    end
    NetworkMgr.isWifiOn = function()
        return android.isWifiEnabled()
    end
end

function Device:retrieveNetworkInfo()
    local ssid, ip, gw = android.getNetworkInfo()
    if ip == "0" or gw == "0" then
        return _("Not connected")
    else
        return T(_("Connected to %1\n IP address: %2\n gateway: %3"), ssid, ip, gw)
    end
end

function Device:setViewport(x,y,w,h)
    logger.info(string.format("Switching viewport to new geometry [x=%d,y=%d,w=%d,h=%d]",x, y, w, h))
    local viewport = Geom:new{x=x, y=y, w=w, h=h}
    self.screen:setViewport(viewport)
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

    local common_text = T(_("%1\n\nOS: Android %2, api %3\nBuild flavor: %4\n"),
        android.prop.product, getCodename(), Device.firmware_rev, android.prop.flavor)

    local eink_text = ""
    if is_eink then
        eink_text = T(_("\nE-ink display supported.\nPlatform: %1\n"), eink_platform)
    end

    local wakelocks_text = ""
    if android.needsWakelocks() then
        wakelocks_text = _("\nThis device needs CPU, screen and touchscreen always on.\nScreen timeout will be ignored while the app is in the foreground!\n")
    end

    return common_text..eink_text..wakelocks_text
end

function Device:exit()
    android.LOGI(string.format("Stopping %s main activity", android.prop.name));
    android.lib.ANativeActivity_finish(android.app.activity)
end

android.LOGI(string.format("Android %s - %s (API %d) - flavor: %s",
    android.prop.version, getCodename(), Device.firmware_rev, android.prop.flavor))

return Device
