local Device = require("device")

local with_frontlight = (Device:isKindle() or Device:isKobo()) and Device:hasFrontlight()
if not (with_frontlight or Device:isSDL()) then
    return { disabled = true, }
end

local ConfirmBox = require("ui/widget/confirmbox")
local ImageWidget = require("ui/widget/imagewidget")
local InfoMessage = require("ui/widget/infomessage")
local Notification = require("ui/widget/notification")
local Screen = require("device").screen
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local T = require("ffi/util").template
local _ = require("gettext")

local tap_touch_zone_ratio = { x = 0, y = 15/16, w = 1/10, h = 1/16, }
local swipe_touch_zone_ratio = { x = 0, y = 1/8, w = 1/10, h = 7/8, }

local KoboLight = WidgetContainer:new{
    name = 'kobolight',
    gestureScale = nil,  -- initialized in self:resetLayout()
}

function KoboLight:init()
    local powerd = Device:getPowerDevice()
    local scale = (powerd.fl_max - powerd.fl_min) / 2 / 10.6
    self.steps = { 0.1, 0.1, 0.2, 0.4, 0.7, 1.1, 1.6, 2.2, 2.9, 3.7, 4.6, 5.6, 6.7, 7.9, 9.2, 10.6, }
    for i = 1, #self.steps, 1
    do
        self.steps[i] = math.ceil(self.steps[i] * scale)
    end

    self.ui.menu:registerToMainMenu(self)
end

function KoboLight:onReaderReady()
    self:setupTouchZones()
    self:resetLayout()
end

function KoboLight:disabled()
    return G_reader_settings:isTrue("disable_kobolight")
end

function KoboLight:setupTouchZones()
    if not Device:isTouchDevice() then return end
    if self:disabled() then return end
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
    return true
end

function KoboLight:onSwipe(_, ges)
    local powerd = Device:getPowerDevice()
    if powerd.fl_intensity == nil then return false end

    local step = math.ceil(#self.steps * ges.distance / self.gestureScale)
    local delta_int = self.steps[step] or self.steps[#self.steps]
    local new_intensity
    if ges.direction == "north" then
        new_intensity = powerd.fl_intensity + delta_int
    elseif ges.direction == "south" then
        new_intensity = powerd.fl_intensity - delta_int
    else
        return false  -- don't consume swipe event if it's not matched
    end

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
    return true
end

function KoboLight:addToMainMenu(menu_items)
    menu_items.frontlight_gesture_controller = {
        text = _("Frontlight gesture controller"),
        callback = function()
            local image = ImageWidget:new{
                file = self.path .. "/demo.png",
                height = Screen:getHeight(),
                width = Screen:getWidth(),
                scale_factor = 0,
            }
            UIManager:show(image)
            UIManager:show(ConfirmBox:new{
                text = T(_("Frontlight gesture controller can:\n- Turn on or off frontlight by tapping bottom left of the screen.\n- Change frontlight intensity by swiping up or down on the left of the screen.\n\nDo you want to %1 it?"),
                         self:disabled() and _("enable") or _("disable")),
                ok_text = self:disabled() and _("Enable") or _("Disable"),
                ok_callback = function()
                    UIManager:close(image)
                    UIManager:setDirty("all", "full")
                    UIManager:show(InfoMessage:new{
                        text = T(_("You have %1 the frontlight gesture controller. It will take effect on next restart."),
                                 self:disabled() and _("enabled") or _("disabled"))
                    })
                    G_reader_settings:flipTrue("disable_kobolight")
                end,
                cancel_text = _("Close"),
                cancel_callback = function()
                    UIManager:close(image)
                    UIManager:setDirty("all", "full")
                end,
            })
            UIManager:setDirty("all", "full")
        end,
    }
end

return KoboLight
