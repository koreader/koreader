local Device = require("device")
local Event = require("ui/event")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local RightContainer = require("ui/widget/container/rightcontainer")
local Screen = require("device").screen

local ReaderDogear = InputContainer:new{}

function ReaderDogear:init()
    local widget = ImageWidget:new{
        file = "resources/icons/dogear.png",
        alpha = true,
    }
    self[1] = RightContainer:new{
        dimen = Geom:new{w = Screen:getWidth(), h = widget:getSize().h},
        widget,
    }
    self:resetLayout()
end

function ReaderDogear:resetLayout()
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
                        x = new_screen_width*DTAP_ZONE_BOOKMARK.x,
                        y = new_screen_height*DTAP_ZONE_BOOKMARK.y,
                        w = new_screen_width*DTAP_ZONE_BOOKMARK.w,
                        h = new_screen_height*DTAP_ZONE_BOOKMARK.h
                    }
                }
            }
        }
    end
end

function ReaderDogear:onTap()
    self.ui:handleEvent(Event:new("ToggleBookmark"))
    return true
end

function ReaderDogear:onSetDogearVisibility(visible)
    self.view.dogear_visible = visible
    return true
end

return ReaderDogear
