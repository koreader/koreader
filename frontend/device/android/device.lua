local FFIUtil = require("ffi/util")
local Generic = require("device/generic/device")
local A, android = pcall(require, "android")  -- luacheck: ignore
local Geom = require("ui/geometry")
local ffi = require("ffi")
local C = ffi.C
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local T = FFIUtil.template

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

-- thirdparty app support
local external = require("device/thirdparty"):new{
    dicts = {
        { "Aard2", "Aard2", false, "itkach.aard2", "aard2" },
        { "Alpus", "Alpus", false, "com.ngcomputing.fora.android", "search" },
        { "ColorDict", "ColorDict", false, "com.socialnmobile.colordict", "colordict" },
        { "Eudic", "Eudic", false, "com.eusoft.eudic", "send" },
        { "EudicPlay", "Eudic (Google Play)", false, "com.qianyan.eudic", "send" },
        { "Fora", "Fora Dict", false, "com.ngc.fora", "search" },
        { "ForaPro", "Fora Dict Pro", false, "com.ngc.fora.android", "search" },
        { "GoldenFree", "GoldenDict Free", false, "mobi.goldendict.android.free", "send" },
        { "GoldenPro", "GoldenDict Pro", false, "mobi.goldendict.android", "send" },
        { "Kiwix", "Kiwix", false, "org.kiwix.kiwixmobile", "text" },
        { "LookUp", "Look Up", false, "gaurav.lookup", "send" },
        { "LookUpPro", "Look Up Pro", false, "gaurav.lookuppro", "send" },
        { "Mdict", "Mdict", false, "cn.mdict", "send" },
        { "QuickDic", "QuickDic", false, "de.reimardoeffinger.quickdic", "quickdic" },
    },
    check = function(self, app)
        return android.isPackageEnabled(app)
    end,
}

local Device = Generic:new{
    isAndroid = yes,
    model = android.prop.product,
    hasKeys = yes,
    hasDPad = no,
    hasExitOptions = no,
    hasEinkScreen = function() return android.isEink() end,
    hasColorScreen = function() return not android.isEink() end,
    hasFrontlight = yes,
    hasNaturalLight = android.isWarmthDevice,
    canRestart = no,
    canSuspend = no,
    firmware_rev = android.app.activity.sdkVersion,
    home_dir = android.getExternalStoragePath(),
    display_dpi = android.lib.AConfiguration_getDensity(android.app.config),
    isHapticFeedbackEnabled = yes,
    hasClipboard = yes,
    hasOTAUpdates = canUpdateApk,
    hasFastWifiStatusQuery = yes,
    canOpenLink = yes,
    openLink = function(self, link)
        if not link or type(link) ~= "string" then return end
        return android.openLink(link) == 0
    end,
    canImportFiles = function() return android.app.activity.sdkVersion >= 19 end,
    hasExternalSD = function() return android.getExternalSdPath() end,
    importFile = function(path) android.importFile(path) end,
    canShareText = yes,
    doShareText = function(text) android.sendText(text) end,

    canExternalDictLookup = yes,
    getExternalDictLookupList = function() return external.dicts end,
    doExternalDictLookup = function (self, text, method, callback)
        external.when_back_callback = callback
        local _, app, action = external:checkMethod("dict", method)
        if action then
            android.dictLookup(text, app, action)
        end
    end,

    -- Android is very finicky, and the LuaJIT allocator has a tremendously hard time getting the system
    -- to allocate memory for it in the very specific memory range it requires to store generated code (mcode).
    -- Failure to do so at runtime (mcode_alloc) will *tank* performance
    -- (much worse than if the JIT were simply disabled).
    -- The first line of defense is left to android-luajit-launcher,
    -- which will try to grab the full mcode region in one go right at startup.
    -- The second line of defense is *this* flag, which disables the JIT in a few code-hungry modules,
    -- but not necessarily performance critical ones, to hopefully limit the amount of mcode memory
    -- required for those modules where it *really* matters (e.g., ffi/blitbuffer.lua).
    -- This is also why we try to actually avoid entering actual loops in the Lua blitter on Android,
    -- and instead attempt to do most of everything via the C implementation.
    -- NOTE: Since https://github.com/koreader/android-luajit-launcher/pull/283, we've patched LuaJIT
    --       to ensure that the initial mcode alloc works, and sticks around, which is why this is no longer enabled.
    should_restrict_JIT = false,
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
            elseif ev.code == C.APP_CMD_DESTROY then
                UIManager:quit()
            elseif ev.code == C.APP_CMD_GAINED_FOCUS
                or ev.code == C.APP_CMD_INIT_WINDOW
                or ev.code == C.APP_CMD_WINDOW_REDRAW_NEEDED then
                this.device.screen:_updateWindow()
            elseif ev.code == C.APP_CMD_TERM_WINDOW then
                this.device.input:resetState()
            elseif ev.code == C.APP_CMD_CONFIG_CHANGED then
                -- orientation and size changes
                if android.screen.width ~= android.getScreenWidth()
                or android.screen.height ~= android.getScreenHeight() then
                    this.device.screen:resize()
                    local new_size = this.device.screen:getSize()
                    logger.info("Resizing screen to", new_size)
                    local Event = require("ui/event")
                    local FileManager = require("apps/filemanager/filemanager")
                    UIManager:broadcastEvent(Event:new("SetDimensions", new_size))
                    UIManager:broadcastEvent(Event:new("ScreenResize", new_size))
                    UIManager:broadcastEvent(Event:new("RedrawCurrentPage"))
                    if FileManager.instance then
                        FileManager.instance:reinit(FileManager.instance.path,
                            FileManager.instance.focused_file)
                        UIManager:setDirty(FileManager.instance.banner, function()
                            return "ui", FileManager.instance.banner.dimen
                        end)
                    end
                end
                -- to-do: keyboard connected, disconnected
            elseif ev.code == C.APP_CMD_RESUME then
                if external.when_back_callback then
                    external.when_back_callback()
                    external.when_back_callback = nil
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
            elseif ev.code == C.AEVENT_POWER_CONNECTED then
                local Event = require("ui/event")
                UIManager:broadcastEvent(Event:new("Charging"))
            elseif ev.code == C.AEVENT_POWER_DISCONNECTED then
                local Event = require("ui/event")
                UIManager:broadcastEvent(Event:new("NotCharging"))
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
                or timeout > C.AKEEP_SCREEN_ON_DISABLED
                and android.settings.hasPermission("settings")
            then
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

function Device:toggleFullscreen()
    local api = android.app.activity.sdkVersion
    if api >= 19 then
        logger.dbg("ignoring fullscreen toggle, reason: always in immersive mode")
    elseif api < 19 and api >= 17 then
        local width = android.getScreenWidth()
        local height = android.getScreenHeight()
        -- NOTE: Since we don't do HW rotation here, this should always match width
        local available_width = android.getScreenAvailableWidth()
        local available_height = android.getScreenAvailableHeight()
        local is_fullscreen = android.isFullscreen()
        android.setFullscreen(not is_fullscreen)
        G_reader_settings:saveSetting("disable_android_fullscreen", is_fullscreen)
        is_fullscreen = android.isFullscreen()
        if is_fullscreen then
            self:setViewport(0, 0, width, height)
        else
            self:setViewport(0, 0, available_width, available_height)
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

function Device:isValidPath(path)
    return android.isPathInsideSandbox(path)
end

--swallow all events
local function processEvents()
    local events = ffi.new("int[1]")
    local source = ffi.new("struct android_poll_source*[1]")
    local poll_state = android.lib.ALooper_pollAll(-1, nil, events, ffi.cast("void**", source))
    if poll_state >= 0 then
        if source[0] ~= nil then
            if source[0].id == C.LOOPER_ID_MAIN then
                local cmd = android.glue.android_app_read_cmd(android.app)
                android.glue.android_app_pre_exec_cmd(android.app, cmd)
                android.glue.android_app_post_exec_cmd(android.app, cmd)
            elseif source[0].id == C.LOOPER_ID_INPUT then
                local event = ffi.new("AInputEvent*[1]")
                while android.lib.AInputQueue_getEvent(android.app.inputQueue, event) >= 0 do
                    if android.lib.AInputQueue_preDispatchEvent(android.app.inputQueue, event[0]) == 0 then
                        android.lib.AInputQueue_finishEvent(android.app.inputQueue, event[0], 1)
                    end
                end
            end
        end
    end
end

function Device:showLightDialog()
    local title = android.isEink() and _("Frontlight settings") or _("Light settings")
    android.lights.showDialog(title, _("Brightness"), _("Warmth"), _("OK"), _("Cancel"))
    repeat
        processEvents() -- swallow all events, including the last one
        FFIUtil.usleep(25000) -- sleep 25ms before next check if dialog was quit
    until (android.lights.dialogState() ~= C.ALIGHTS_DIALOG_OPENED)

    local GestureDetector = require("device/gesturedetector")
    GestureDetector:clearStates()

    local action = android.lights.dialogState()
    if action == C.ALIGHTS_DIALOG_OK then
        self.powerd.fl_intensity = self.powerd:frontlightIntensityHW()
        logger.dbg("Dialog OK, brightness: " .. self.powerd.fl_intensity)
        if android.isWarmthDevice() then
            self.powerd.fl_warmth = self.powerd:getWarmth()
            logger.dbg("Dialog OK, warmth: " .. self.powerd.fl_warmth)
        end
        local Event = require("ui/event")
        local UIManager = require("ui/uimanager")
        UIManager:broadcastEvent(Event:new("FrontlightStateChanged"))
    elseif action == C.ALIGHTS_DIALOG_CANCEL then
        logger.dbg("Dialog Cancel, brightness: " .. self.powerd.fl_intensity)
        self.powerd:setIntensityHW(self.powerd.fl_intensity)
        if android.isWarmthDevice() then
            logger.dbg("Dialog Cancel, warmth: " .. self.powerd.fl_warmth)
            self.powerd:setWarmth(self.powerd.fl_warmth)
        end
    end
end

function Device:untar(archive, extract_to)
    return android.untar(archive, extract_to)
end

android.LOGI(string.format("Android %s - %s (API %d) - flavor: %s",
    android.prop.version, getCodename(), Device.firmware_rev, android.prop.flavor))

return Device
