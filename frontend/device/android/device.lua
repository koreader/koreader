local Generic = require("device/generic/device")
local _, android = pcall(require, "android")
local ffi = require("ffi")
local C = ffi.C
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")

local function yes() return true end
local function no() return false end

local Device = Generic:new{
    model = android.getProduct(),
    hasKeys = yes,
    hasDPad = no,
    isAndroid = yes,
    hasEinkScreen = function() return android.isEink() end,
    hasFrontlight = yes,
    firmware_rev = android.app.activity.sdkVersion,
    display_dpi = android.lib.AConfiguration_getDensity(android.app.config),
    hasClipboard = yes,
    hasColorScreen = yes,
    hasOTAUpdates = yes,
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
                this.device.screen:refreshFull()
            elseif ev.code == C.APP_CMD_RESUME then
                local new_file = android.getIntent()
                if new_file ~= nil and lfs.attributes(new_file, "mode") == "file" then
                    logger.warn("Loading new file from intent: " .. new_file)
                    local ReaderUI = require("apps/reader/readerui")
                    ReaderUI:doShowReader(new_file)
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
    if G_reader_settings:isTrue("enable_android_wakelock") then
        android.setWakeLock(true)
    end

    Generic.init(self)
end

function Device:initNetworkManager(NetworkMgr)
    NetworkMgr.turnOnWifi = function()
        android.setWifiEnabled(true)
    end

    NetworkMgr.turnOffWifi = function()
        android.setWifiEnabled(false)
    end
    NetworkMgr.isWifiOn = function()
        return android.isWifiEnabled()
    end
end

function Device:exit()
    android.log_name = 'luajit-launcher'
    android.LOGI("Finishing luajit launcher main activity");
    android.lib.ANativeActivity_finish(android.app.activity)
end

local function getCodename()
    local api = Device.firmware_rev
    local codename = nil

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

    return codename or ""
end

android.LOGI(string.format("Android %s - %s (API %d)",
    android.getVersion(), getCodename(), Device.firmware_rev))

return Device
