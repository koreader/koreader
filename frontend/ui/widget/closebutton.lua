local InputContainer = require("ui/widget/container/inputcontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local TextWidget = require("ui/widget/textwidget")
local GestureRange = require("ui/gesturerange")
local UIManager = require("ui/uimanager")
local Geom = require("ui/geometry")
local Font = require("ui/font")

--[[
a button widget that shows an "×" and handles closing window when tapped
--]]
local CloseButton = InputContainer:new{
	align = "right",
	window = nil,
}

function CloseButton:init()
	local text_widget = TextWidget:new{
		text = "×",
		face = Font:getFace("cfont", 32),
	}
	self[1] = FrameContainer:new{
		bordersize = 0,
		padding = 0,
		text_widget
	}
	
	self.dimen = text_widget:getSize():copy()

	self.ges_events.Close = {
		GestureRange:new{
			ges = "tap",
			range = self.dimen,
		},
		doc = "Tap on close button",
	}
end

function CloseButton:onClose()
	self.window:onClose()
	return true
end

return CloseButton
