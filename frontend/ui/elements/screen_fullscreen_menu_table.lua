local isAndroid, android = pcall(require, "android")
local Geom = require("ui/geometry")
local logger = require("logger")
local _ = require("gettext")

if not isAndroid then return end

return {
    text = _("Fullscreen"),
    checked_func = function()
        local disabled_fullscreen = G_reader_settings:isTrue("disabled_fullscreen")
        logger.dbg("screen_fullscreen_menu_table.lua: Is fullscreen disabled", disabled_fullscreen)
        return disabled_fullscreen
    end,
    callback = function()
        local enabled_fullscreen = G_reader_settings:isFalse("disabled_fullscreen")

        logger.dbg("screen_fullscreen_menu_table.lua:  Fullscreen swiching to: ", enabled_fullscreen)
        android.setFullscreen(enabled_fullscreen)

        local status_bar_height = android.getStatusBarHeight()
        logger.dbg("screen_fullscreen_menu_table.lua: Status bar height: ", status_bar_height)
        local screen_width = android.getScreenWidth()
        logger.dbg("screen_fullscreen_menu_table.lua: Screen width: ", screen_width)
        local screen_height = android.getScreenHeight()
        logger.dbg("screen_fullscreen_menu_table.lua: Screen height: ", screen_height)

        local new_height = screen_height - status_bar_height
        logger.dbg("screen_fullscreen_menu_table.lua: Setting viewport to {x= 0, y=" .. status_bar_height ..", w=" .. screen_width .. ", h=" .. new_height .. "}")
        local viewport = Geom:new{x=0, y= status_bar_height, w=screen_width, h= new_height}
        android.screen:setViewport(viewport)

        G_reader_settings:saveSetting("disabled_fullscreen", enabled_fullscreen)
    end,
}
