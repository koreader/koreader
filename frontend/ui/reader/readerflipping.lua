local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local ImageWidget = require("ui/widget/imagewidget")
local GestureRange = require("ui/gesturerange")
local Device = require("ui/device")
local Geom = require("ui/geometry")
local Screen = require("ui/screen")
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
	if Device:isTouchDevice() then
		self.ges_events = {
			Tap = {
				GestureRange:new{
					ges = "tap",
					range = Geom:new{
						x = Screen:getWidth()*DTAP_ZONE_FLIPPING.x,
						y = Screen:getHeight()*DTAP_ZONE_FLIPPING.y,
						w = Screen:getWidth()*DTAP_ZONE_FLIPPING.w,
						h = Screen:getHeight()*DTAP_ZONE_FLIPPING.h
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
