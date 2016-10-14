local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local GestureRange = require("ui/gesturerange")
local Device = require("device")
local Geom = require("ui/geometry")
local Screen = Device.screen
local DEBUG = require("dbg")
local UIManager = require("ui/uimanager")
local Notification = require("ui/widget/notification")
local T = require("ffi/util").template
local _ = require("gettext")

local DTAP_ZONE_KOBOLIGHTTOGGLE = {x = 0, y = 0.9375, w = 0.1, h = 0.0625 }
local DTAP_ZONE_KOBOLIGHTSWIPE = {x = 0, y = 0.125, w = 0.1, h = 0.875 }

local ReaderKoboLight = InputContainer:new{
    steps = {0,1,1,1,1,2,2,2,3,4,5,6,7,8,9,10},
    gestureScale = Screen:getHeight() * DTAP_ZONE_KOBOLIGHTSWIPE.h * 0.8,
}

function ReaderKoboLight:init()
    self[1] = LeftContainer:new{
        dimen = Geom:new{w = Screen:getWidth(), h = Screen:getHeight()},
    }
    self:resetLayout()
end

function ReaderKoboLight:resetLayout()
    local new_screen_width = Screen:getWidth()
    if new_screen_width == self[1].dimen.w then return end
    local new_screen_height = Screen:getHeight()
    self[1].dimen.w = new_screen_width
    self[1].dimen.h = new_screen_height
    self.gestureScale = new_screen_height * DTAP_ZONE_KOBOLIGHTSWIPE.h * 0.8

    if Device:isTouchDevice() then
        self.ges_events = {
            Tap = {
                GestureRange:new{
                    ges = "tap",
                    range = Geom:new{
                        x = new_screen_width*DTAP_ZONE_KOBOLIGHTTOGGLE.x,
                        y = new_screen_height*DTAP_ZONE_KOBOLIGHTTOGGLE.y,
                        w = new_screen_width*DTAP_ZONE_KOBOLIGHTTOGGLE.w,
                        h = new_screen_height*DTAP_ZONE_KOBOLIGHTTOGGLE.h
                    }
                }
            },
            Swipe = {
                GestureRange:new{
                    ges = "swipe",
                    range = Geom:new{
                        x = new_screen_width*DTAP_ZONE_KOBOLIGHTSWIPE.x,
                        y = new_screen_height*DTAP_ZONE_KOBOLIGHTSWIPE.y,
                        w = new_screen_width*DTAP_ZONE_KOBOLIGHTSWIPE.w,
                        h = new_screen_height*DTAP_ZONE_KOBOLIGHTSWIPE.h
                    }
                }
            }
        }
    end
end

function ReaderKoboLight:onShowIntensity()
    local powerd = Device:getPowerDevice()
    if powerd.fl_intensity ~= nil then
        UIManager:show(Notification:new{
            text = T(_("Frontlight intensity is set to %1."), powerd.fl_intensity),
            timeout = 1.0,
        })
    end
    return true
end

function ReaderKoboLight:onShowOnOff()
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

function ReaderKoboLight:onTap()
    Device:getPowerDevice():toggleFrontlight()
    self:onShowOnOff()
    return true
end

function ReaderKoboLight:onSwipe(arg, ges)
    local powerd = Device:getPowerDevice()
    if powerd.fl_intensity == nil then return true end

    DEBUG("frontlight intensity", powerd.fl_intensity)
    local step = math.ceil(#self.steps * ges.distance / self.gestureScale)
    DEBUG("step = ", step)
    local delta_int = self.steps[step] or self.steps[#self.steps]
    DEBUG("delta_int = ", delta_int)
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
        else    -- general case
            powerd:setIntensity(new_intensity)
            self:onShowIntensity()
        end
    end
    return true
end

return ReaderKoboLight
