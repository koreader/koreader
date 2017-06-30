local _ = require("gettext")
local android = require("device/android/device")
local logger = require("logger")


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
        G_reader_settings:saveSetting("disabled_fullscreen", enabled_fullscreen)
    end,
}
