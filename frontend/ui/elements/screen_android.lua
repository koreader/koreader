local isAndroid, android = pcall(require, "android")
local Device = require("device")
local Geom = require("ui/geometry")
local logger = require("logger")
local _ = require("gettext")
local Input = Device.input
local Screen = Device.screen
local T = require("ffi/util").template

if not isAndroid then return end

-- custom timeouts (in milliseconds)
local timeout_custom1 = 30 * 1000
local timeout_custom2 = 60 * 1000
local timeout_custom3 = 2 * 60 * 1000
local timeout_custom4 = 5 * 60 * 1000
local timeout_custom5 = 10 * 60 * 1000
local timeout_custom6 = 15 * 60 * 1000
local timeout_custom7 = 30 * 60 * 1000

local timeout_system = 0    -- same as system (do nothing!)
local timeout_disabled = -1 -- disable timeout using wakelocks

local can_modify_timeout = not android.needsWakelocks()

local function humanReadableTimeout(timeout)
    local sec = timeout / 1000
    if sec >= 120 then
        return T(_("%1 minutes"), sec / 60)
    else
        return T(_("%1 seconds"), sec)
    end
end

local function timeoutEquals(timeout)
    return timeout == android.getScreenOffTimeout()
end

local function saveAndApplyTimeout(timeout)
    G_reader_settings:saveSetting("android_screen_timeout", timeout)
    android.setScreenOffTimeout(timeout)
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
    return {
        text = _("Screen Timeout"),
        sub_item_table = {
            {
                text = _("Use system settings"),
                enabled_func = function() return can_modify_timeout end,
                checked_func = function() return timeoutEquals(timeout_system) end,
                callback = function() saveAndApplyTimeout(timeout_system) end
            },
            {
                text = humanReadableTimeout(timeout_custom1),
                enabled_func = function() return can_modify_timeout end,
                checked_func = function() return timeoutEquals(timeout_custom1) end,
                callback = function() saveAndApplyTimeout(timeout_custom1) end
            },
            {
                text = humanReadableTimeout(timeout_custom2),
                enabled_func = function() return can_modify_timeout end,
                checked_func = function() return timeoutEquals(timeout_custom2) end,
                callback = function() saveAndApplyTimeout(timeout_custom2) end
            },
            {
                text = humanReadableTimeout(timeout_custom3),
                enabled_func = function() return can_modify_timeout end,
                checked_func = function() return timeoutEquals(timeout_custom3) end,
                callback = function() saveAndApplyTimeout(timeout_custom3) end
            },
            {
                text = humanReadableTimeout(timeout_custom4),
                enabled_func = function() return can_modify_timeout end,
                checked_func = function() return timeoutEquals(timeout_custom4) end,
                callback = function() saveAndApplyTimeout(timeout_custom4) end
            },
            {
                text = humanReadableTimeout(timeout_custom5),
                enabled_func = function() return can_modify_timeout end,
                checked_func = function() return timeoutEquals(timeout_custom5) end,
                callback = function() saveAndApplyTimeout(timeout_custom5) end
            },
            {
                text = humanReadableTimeout(timeout_custom6),
                enabled_func = function() return can_modify_timeout end,
                checked_func = function() return timeoutEquals(timeout_custom6) end,
                callback = function() saveAndApplyTimeout(timeout_custom6) end
            },
            {
                text = humanReadableTimeout(timeout_custom7),
                enabled_func = function() return can_modify_timeout end,
                checked_func = function() return timeoutEquals(timeout_custom7) end,
                callback = function() saveAndApplyTimeout(timeout_custom7) end
            },
            {
                text = _("Keep screen on"),
                enabled_func = function() return can_modify_timeout end,
                checked_func = function() return timeoutEquals(timeout_disabled) end,
                callback = function() saveAndApplyTimeout(timeout_disabled) end
            },
        }
    }
end


return ScreenHelper
