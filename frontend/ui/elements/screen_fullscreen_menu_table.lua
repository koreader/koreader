local _ = require("gettext")
local android = require("device/android/device")
local logger = require("logger")
local Geom = require("ui/geometry")


return {
    text = _("Fullscreen"),
    checked_func = function()
        local disabled_fullscreen = G_reader_settings:readSetting("disabled_fullscreen") ~= false
        logger.dbg("screen_fullscreen_menu_table.lua: Is fullscreen disabled", disabled_fullscreen)
        return disabled_fullscreen
    end,
    callback = function()
        local disabled_fullscreen = G_reader_settings:readSetting("disabled_fullscreen") ~= false
        local enabled_fullscreen = not disabled_fullscreen
        logger.dbg("screen_fullscreen_menu_table.lua:  setting fullscreen to enabled ", enabled_fullscreen)
        android.setFullscreen(android, enabled_fullscreen)
        
        local status_bar_height = android.getStatusBarHeight()
        logger.dbg("Status bar height: ", status_bar_height)
        local screen_width = android.getscreen_height()
        logger.dbg("Screen width: ", screen_width)
        local screen_height = android.getScreenHeight()
        logger.dbg("Screen height: ", screen_height)
        local viewport = Geom:new{x=status_bar_height, y=0, w=screen_width, h=screen_height}
        
        android.screen:setViewport(viewport)
        android.input:registerEventAdjustHook(
            android.input.adjustTouchTranslate,
            {x = 0 - viewport.x, y = 0 - viewport.y})
        
        G_reader_settings:saveSetting("disabled_fullscreen", enabled_fullscreen)
    end,
}
