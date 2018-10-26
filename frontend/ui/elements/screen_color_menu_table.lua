local Event = require("ui/event")
local Screen = require("device").screen
local UIManager = require("ui/uimanager")
local Runtimectl = require("runtimectl")
local _ = require("gettext")

return {
    text = _("Color rendering"),
    enabled_func = Screen.isColorScreen,
    checked_func = function() return Runtimectl.is_color_rendering_enabled end,
    callback = function()
        Runtimectl:setColorRenderingEnabled(not Runtimectl.is_color_rendering_enabled)
        G_reader_settings:saveSetting(
            "color_rendering", Runtimectl.is_color_rendering_enabled)
        UIManager:broadcastEvent(Event:new("ColorRenderingUpdate"))
    end
}
