local isAndroid, android = pcall(require, "android")
local Device = require("device")
local Geom = require("ui/geometry")
local ffi = require("ffi")
local logger = require("logger")
local _ = require("gettext")
local Input = Device.input
local N_ = _.ngettext
local Screen = Device.screen
local T = require("ffi/util").template

if not isAndroid then return end

local system = ffi.C.AKEEP_SCREEN_ON_DISABLED
local screenOn = ffi.C.AKEEP_SCREEN_ON_ENABLED
local needs_wakelocks = android.needsWakelocks()

-- custom timeouts (in milliseconds)
local timeout_custom1 = 2 * 60 * 1000
local timeout_custom2 = 5 * 60 * 1000
local timeout_custom3 = 10 * 60 * 1000
local timeout_custom4 = 15 * 60 * 1000
local timeout_custom5 = 20 * 60 * 1000
local timeout_custom6 = 25 * 60 * 1000
local timeout_custom7 = 30 * 60 * 1000

local function humanReadableTimeout(timeout)
    local sec = timeout / 1000
    if sec >= 60 then
        return T(N_("1 minute", "%1 minutes", sec), sec / 60)
    else
        return T(N_("1 second", "%1 seconds", sec), sec)
    end
end

local function canModifyTimeout(timeout)
    if needs_wakelocks then return false end
    if timeout == system or timeout == screenOn then
        return true
    else
        return android.settings.hasPermission("settings")
    end
end

local function timeoutEquals(timeout)
    return timeout == android.timeout.get()
end

local function saveAndApplyTimeout(timeout)
    G_reader_settings:saveSetting("android_screen_timeout", timeout)
    android.timeout.set(timeout)
end

local function requestWriteSettings()
    local text = _([[
Allow KOReader to modify system settings?

You will be prompted with a permission management screen. You'll need to give KOReader permission and then restart the program.]])

    android.settings.requestPermission("settings", text, _("Allow"), _("Cancel"))
end

local ScreenHelper = {}

function ScreenHelper:toggleFullscreen()
    local api = Device.firmware_rev

    if api < 19 and api >= 17 then
        Device:toggleFullscreen()
        local UIManager = require("ui/uimanager")
        local InfoMessage = require("ui/widget/infomessage")
        UIManager:show(InfoMessage:new{
            text = _("This will take effect on next restart.")
        })
    elseif api < 17 then
        self:toggleFullscreenLegacy()
    end
end

-- toggle android status bar visibility -- Legacy function for Apis 14 - 16
function ScreenHelper:toggleFullscreenLegacy()
    -- toggle android status bar visibility
    local is_fullscreen = android.isFullscreen()
    android.setFullscreen(not is_fullscreen)
    logger.dbg(string.format("requesting fullscreen: %s", not is_fullscreen))

    local screen_width = android.getScreenWidth()
    local screen_height = android.getScreenHeight()
    local status_bar_height = android.getStatusBarHeight()
    local new_height = screen_height - status_bar_height

    if not is_fullscreen and Screen.viewport then
        status_bar_height = 0
        -- reset touchTranslate to normal
        Input:registerEventAdjustHook(
            Input.adjustTouchTranslate,
            {x = 0 + Screen.viewport.x, y = 0 + Screen.viewport.y})
    end

    local viewport = Geom:new{x=0, y=status_bar_height, w=screen_width, h=new_height}
    logger.info(string.format("Switching viewport to new geometry [x=%d,y=%d,w=%d,h=%d]",
        0, status_bar_height, screen_width, new_height))

    Screen:setViewport(viewport)

    if is_fullscreen and Screen.viewport then
        Input:registerEventAdjustHook(
            Input.adjustTouchTranslate,
            {x = 0 - Screen.viewport.x, y = 0 - Screen.viewport.y})
    end
end

-- timeout menu table
function ScreenHelper:getTimeoutMenuTable()
    local t = {
            {
                text = _("Use system settings"),
                enabled_func = function() return canModifyTimeout(system) end,
                checked_func = function() return timeoutEquals(system) end,
                callback = function() saveAndApplyTimeout(system) end
            },
            {
                text = humanReadableTimeout(timeout_custom1),
                enabled_func = function() return canModifyTimeout(timeout_custom1) end,
                checked_func = function() return timeoutEquals(timeout_custom1) end,
                callback = function() saveAndApplyTimeout(timeout_custom1) end
            },
            {
                text = humanReadableTimeout(timeout_custom2),
                enabled_func = function() return canModifyTimeout(timeout_custom2) end,
                checked_func = function() return timeoutEquals(timeout_custom2) end,
                callback = function() saveAndApplyTimeout(timeout_custom2) end
            },
            {
                text = humanReadableTimeout(timeout_custom3),
                enabled_func = function() return canModifyTimeout(timeout_custom3) end,
                checked_func = function() return timeoutEquals(timeout_custom3) end,
                callback = function() saveAndApplyTimeout(timeout_custom3) end
            },
            {
                text = humanReadableTimeout(timeout_custom4),
                enabled_func = function() return canModifyTimeout(timeout_custom4) end,
                checked_func = function() return timeoutEquals(timeout_custom4) end,
                callback = function() saveAndApplyTimeout(timeout_custom4) end
            },
            {
                text = humanReadableTimeout(timeout_custom5),
                enabled_func = function() return canModifyTimeout(timeout_custom5) end,
                checked_func = function() return timeoutEquals(timeout_custom5) end,
                callback = function() saveAndApplyTimeout(timeout_custom5) end
            },
            {
                text = humanReadableTimeout(timeout_custom6),
                enabled_func = function() return canModifyTimeout(timeout_custom6) end,
                checked_func = function() return timeoutEquals(timeout_custom6) end,
                callback = function() saveAndApplyTimeout(timeout_custom6) end
            },
            {
                text = humanReadableTimeout(timeout_custom7),
                enabled_func = function() return canModifyTimeout(timeout_custom7) end,
                checked_func = function() return timeoutEquals(timeout_custom7) end,
                callback = function() saveAndApplyTimeout(timeout_custom7) end
            },
            {
                text = _("Keep screen on"),
                enabled_func = function() return canModifyTimeout(screenOn) end,
                checked_func = function() return timeoutEquals(screenOn) end,
                callback = function() saveAndApplyTimeout(screenOn) end
            },
        }

    if not android.settings.hasPermission("settings") then
        table.insert(t, 1, {
            text = _("Allow system settings override"),
            enabled_func = function() return not android.settings.hasPermission("settings") end,
            checked_func = function() return android.settings.hasPermission("settings") end,
            callback = function() requestWriteSettings() end,
            separator = true,
        })
    end

    return {
        text = _("Screen Timeout"),
        sub_item_table = t
    }
end

return ScreenHelper
