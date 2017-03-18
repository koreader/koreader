local WidgetContainer = require("ui/widget/container/widgetcontainer")
local UIManager = require("ui/uimanager")
local Device = require("device")

local Refresh = WidgetContainer:new{
    name = 'refresh',
}

local tap_touch_zone_ratio = { x = 9/10, y = 15/16, w = 1/10, h = 1/16, }

function Refresh:init()
end

function Refresh:onReaderReady()
    self:setupTouchZones()
end

function Refresh:setupTouchZones()
    if not Device:isTouchDevice() then return end
    self.ui:registerTouchZones({
        {
            id = "plugin_refresh_tap",
            ges = "tap",
            screen_zone = {
                ratio_x = tap_touch_zone_ratio.x, ratio_y = tap_touch_zone_ratio.y,
                ratio_w = tap_touch_zone_ratio.w, ratio_h = tap_touch_zone_ratio.h,
            },
            handler = function() return self:onTap() end,
            overrides = { 'readerfooter_tap' },
        },
    })
end

function Refresh:onTap()
    UIManager:setDirty(nil, "full")
    return true
end

return Refresh
