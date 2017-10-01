local Event = require("ui/event")
local Screen = require("device").screen
local UIManager = require("ui/uimanager")
local _ = require("gettext")

return {
    text = _("Color rendering"),
    enabled_func = Screen.isColorScreen,
    checked_func = Screen.isColorEnabled,
    callback = function()
        G_reader_settings:flipNilOrTrue("color_rendering")
        UIManager:broadcastEvent(Event:new("ColorRenderingUpdate"))
    end
}
