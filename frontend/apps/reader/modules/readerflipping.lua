local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local ImageWidget = require("ui/widget/imagewidget")
local GestureRange = require("ui/gesturerange")
local Device = require("device")
local Geom = require("ui/geometry")
local Screen = require("device").screen
local Event = require("ui/event")

local ReaderFlipping = InputContainer:new{
    orig_reflow_mode = 0,
}

function ReaderFlipping:init()
    local widget = ImageWidget:new{
        file = "resources/icons/appbar.book.open.png",
    }
    self[1] = LeftContainer:new{
        dimen = Geom:new{w = Screen:getWidth(), h = widget:getSize().h},
        widget,
    }
    self:resetLayout()
end

function ReaderFlipping:resetLayout()
    local new_screen_width = Screen:getWidth()
    if new_screen_width == self._last_screen_width then return end
    local new_screen_height = Screen:getHeight()
    self._last_screen_width = new_screen_width

    self[1].dimen.w = new_screen_width
    if Device:isTouchDevice() then
        self.ges_events = {
            Tap = {
                GestureRange:new{
                    ges = "tap",
                    range = Geom:new{
                        x = new_screen_width*DTAP_ZONE_FLIPPING.x,
                        y = new_screen_height*DTAP_ZONE_FLIPPING.y,
                        w = new_screen_width*DTAP_ZONE_FLIPPING.w,
                        h = new_screen_height*DTAP_ZONE_FLIPPING.h
                    }
                }
            }
        }
    end
end

function ReaderFlipping:onTap()
    self.ui:handleEvent(Event:new("TogglePageFlipping"))
    return true
end

return ReaderFlipping
