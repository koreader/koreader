local isAndroid, android = pcall(require, "android")
local Device = require("device")
local Geom = require("ui/geometry")
local logger = require("logger")
local Input = Device.input
local Screen = Device.screen

if not isAndroid then return end

local ScreenHelper = {}

-- toggle android status bar visibility
function ScreenHelper:toggleFullscreen()
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

-- toggle android wakelock support
function ScreenHelper:toggleWakelock()
    local is_wakelock = G_reader_settings:isTrue("enable_android_wakelock")
    android.setWakeLock(not is_wakelock)
    G_reader_settings:saveSetting("enable_android_wakelock", not is_wakelock)
end

return ScreenHelper
