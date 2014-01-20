local InputContainer = require("ui/widget/container/inputcontainer")
local RightContainer = require("ui/widget/container/rightcontainer")
local ImageWidget = require("ui/widget/imagewidget")
local GestureRange = require("ui/gesturerange")
local UIManager = require("ui/uimanager")
local Device = require("ui/device")
local Geom = require("ui/geometry")
local Screen = require("ui/screen")
local Event = require("ui/event")

local ReaderDogear = InputContainer:new{}

function ReaderDogear:init()
	local widget = ImageWidget:new{
		file = "resources/icons/dogear.png",
	}
	self[1] = RightContainer:new{
		dimen = Geom:new{w = Screen:getWidth(), h = widget:getSize().h},
		widget,
	}
	if Device:isTouchDevice() then
		self.ges_events = {
			Tap = {
				GestureRange:new{
					ges = "tap",
					range = Geom:new{
						x = Screen:getWidth()*DTAP_ZONE_BOOKMARK.x,
						y = Screen:getHeight()*DTAP_ZONE_BOOKMARK.y,
						w = Screen:getWidth()*DTAP_ZONE_BOOKMARK.w,
						h = Screen:getHeight()*DTAP_ZONE_BOOKMARK.h
					}
				}
			},
			Hold = {
				GestureRange:new{
					ges = "hold",
					range = Geom:new{
						x = Screen:getWidth()*DTAP_ZONE_BOOKMARK.x,
						y = Screen:getHeight()*DTAP_ZONE_BOOKMARK.y,
						w = Screen:getWidth()*DTAP_ZONE_BOOKMARK.w,
						h = Screen:getHeight()*DTAP_ZONE_BOOKMARK.h
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

function ReaderDogear:onHold()
	self.ui:handleEvent(Event:new("ToggleBookmarkFlipping"))
	return true
end

function ReaderDogear:onSetDogearVisibility(visible)
	self.view.dogear_visible = visible
	return true
end

return ReaderDogear
