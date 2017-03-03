local Device = require("device")

if not ((Device:isKindle() or Device:isKobo()) and Device:hasFrontlight()) then
    return { disabled = true, }
end

local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Screen = Device.screen
local UIManager = require("ui/uimanager")
local Notification = require("ui/widget/notification")
local T = require("ffi/util").template
local _ = require("gettext")

local tap_touch_zone_ratio = { x = 0, y = 15/16, w = 1/10, h = 1/16, }
local swipe_touch_zone_ratio = { x = 0, y = 1/8, w = 1/10, h = 7/8, }


local KoboLight = WidgetContainer:new{
    name = 'kobolight',
    steps = { 0.1, 0.1, 0.2, 0.4, 0.7, 1.1, 1.6, 2.2, 2.9, 3.7, 4.6, 5.6, 6.7, 7.9, 9.2, 10.6, },
    gestureScale = nil,  -- initialized in self:resetLayout()
}

function KoboLight:init()
    local powerd = Device:getPowerDevice()
    local scale = (powerd.fl_max - powerd.fl_min) / 2 / 10.6
    for i = 1, #self.steps, 1
    do
        self.steps[i] = math.ceil(self.steps[i] * scale)
    end
end

function KoboLight:onReaderReady()
    self:setupTouchZones()
    self:resetLayout()
end

function KoboLight:setupTouchZones()
    if not Device:isTouchDevice() then return end
    local swipe_zone = {
        ratio_x = swipe_touch_zone_ratio.x, ratio_y = swipe_touch_zone_ratio.y,
        ratio_w = swipe_touch_zone_ratio.w, ratio_h = swipe_touch_zone_ratio.h,
    }
    self.ui:registerTouchZones({
        {
            id = "plugin_kobolight_tap",
            ges = "tap",
            screen_zone = {
                ratio_x = tap_touch_zone_ratio.x, ratio_y = tap_touch_zone_ratio.y,
                ratio_w = tap_touch_zone_ratio.w, ratio_h = tap_touch_zone_ratio.h,
            },
            handler = function() return self:onTap() end,
            overrides = { 'readerfooter_tap' },
        },
        {
            id = "plugin_kobolight_swipe",
            ges = "swipe",
            screen_zone = swipe_zone,
            handler = function(ges) return self:onSwipe(nil, ges) end,
            overrides = { 'paging_swipe', 'rolling_swipe', },
        },
        {
            -- dummy zone to disable reader panning
            id = "plugin_kobolight_pan",
            ges = "pan",
            screen_zone = swipe_zone,
            handler = function(ges) return true end,
            overrides = { 'paging_pan', 'rolling_pan', },
        },
        {
            -- dummy zone to disable reader panning
            id = "plugin_kobolight_pan_release",
            ges = "pan_release",
            screen_zone = swipe_zone,
            handler = function(ges) return true end,
            overrides = { 'paging_pan_release', },
        },
    })
end

function KoboLight:resetLayout()
    local new_screen_height = Screen:getHeight()
    self.gestureScale = new_screen_height * swipe_touch_zone_ratio.h * 0.8
end

function KoboLight:onShowIntensity()
    local powerd = Device:getPowerDevice()
    if powerd.fl_intensity ~= nil then
        UIManager:show(Notification:new{
            text = T(_("Frontlight intensity is set to %1."), powerd.fl_intensity),
            timeout = 1.0,
        })
    end
    return true
end

function KoboLight:onShowOnOff()
    local powerd = Device:getPowerDevice()
    local new_text
    if powerd.is_fl_on then
        new_text = _("Frontlight is on.")
    else
        new_text = _("Frontlight is off.")
    end
    UIManager:show(Notification:new{
        text = new_text,
        timeout = 1.0,
    })
    return true
end

function KoboLight:onTap()
    Device:getPowerDevice():toggleFrontlight()
    self:onShowOnOff()
    if self.view.footer_visible and self.view.footer.settings.frontlight then
        self.view.footer:updateFooter()
    end
    return true
end

function KoboLight:onSwipe(_, ges)
    local powerd = Device:getPowerDevice()
    if powerd.fl_intensity == nil then return true end

    local step = math.ceil(#self.steps * ges.distance / self.gestureScale)
    local delta_int = self.steps[step] or self.steps[#self.steps]
    local new_intensity
    if ges.direction == "north" then
        new_intensity = powerd.fl_intensity + delta_int
    elseif ges.direction == "south" then
        new_intensity = powerd.fl_intensity - delta_int
    end
    if new_intensity ~= nil then
        -- when new_intensity <=0, toggle light off
        if new_intensity <=0 then
            if powerd.is_fl_on then
                powerd:toggleFrontlight()
            end
            self:onShowOnOff()
        else -- general case
            powerd:setIntensity(new_intensity)
            self:onShowIntensity()
        end
        if self.view.footer_visible and self.view.footer.settings.frontlight then
            self.view.footer:updateFooter()
        end
    end
    return true
end

return KoboLight
