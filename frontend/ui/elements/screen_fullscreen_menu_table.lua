local isAndroid, android = pcall(require, "android")
local Device = require("device")
local Geom = require("ui/geometry")
local logger = require("logger")
local _ = require("gettext")
local Input = Device.input
local Screen = Device.screen

if not isAndroid then return end

return {
    text = _("Fullscreen"),
    checked_func = function()
        return G_reader_settings:isFalse("disabled_fullscreen")
    end,
    callback = function()
        local disabled_fullscreen = G_reader_settings:isTrue("disabled_fullscreen")

        logger.dbg("screen_fullscreen_menu_table.lua:  Fullscreen swiching to: ", disabled_fullscreen)
        android.setFullscreen(disabled_fullscreen)

        local status_bar_height = android.getStatusBarHeight()
        logger.dbg("screen_fullscreen_menu_table.lua: Status bar height: ", status_bar_height)
        local screen_width = android.getScreenWidth()
        logger.dbg("screen_fullscreen_menu_table.lua: Screen width: ", screen_width)
        local screen_height = android.getScreenHeight()
        logger.dbg("screen_fullscreen_menu_table.lua: Screen height: ", screen_height)

        local new_height = screen_height - status_bar_height
        local viewport = Geom:new{x=0, y=status_bar_height, w=screen_width, h=new_height}

        if not disabled_fullscreen and Screen.viewport then
            -- reset touchTranslate to normal
            Input:registerEventAdjustHook(
                Input.adjustTouchTranslate,
                {x = 0 + Screen.viewport.x, y = 0 + Screen.viewport.y})
        end
        Screen:setViewport(viewport)
        if disabled_fullscreen then
            Input:registerEventAdjustHook(
                Input.adjustTouchTranslate,
                {x = 0 - Screen.viewport.x, y = 0 - Screen.viewport.y})
        end

        G_reader_settings:saveSetting("disabled_fullscreen", not disabled_fullscreen)
    end,
}
