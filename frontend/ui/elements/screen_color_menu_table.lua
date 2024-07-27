local Device = require("device")
local Event = require("ui/event")
local Screen = Device.screen
local UIManager = require("ui/uimanager")
local CanvasContext = require("document/canvascontext")
local _ = require("gettext")

-- NOTE: Again, make sure this is enabled if for some reason color is enabled on a Grayscale screen...
return {
    text = _("Color rendering"),
    enabled = Screen:isColorEnabled() or Screen:isColorScreen(),
    checked_func = Screen.isColorEnabled,
    callback = function()
        local new_val = not Screen.isColorEnabled()
        -- Screen.isColorEnabled reads G_reader_settings :'(
        G_reader_settings:saveSetting("color_rendering", new_val)
        CanvasContext:setColorRenderingEnabled(new_val)
        UIManager:broadcastEvent(Event:new("ColorRenderingUpdate"))
        -- On color Kobos, we can use this opportunity to swap to 8bpp, so, request a restart.
        -- NOTE: Unfortunately, that doesn't help alleviate moire effect on affected patterns,
        --       so I guess that comes from some physical aspect of the screen layers...
        if Device:isKobo() and Device:hasColorScreen() then
            UIManager:askForRestart()
        end
    end
}
