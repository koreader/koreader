require "ui/widget"

--[[
a button widget
]]
Button = InputContainer:new{
	text = nil, -- mandatory
	preselect = false,
	callback = nil,
	margin = 0,
	bordersize = 3,
	background = 0,
	radius = 15,
	padding = 2,
	width = nil,
	text_font_face = "cfont",
	text_font_size = 20,
}

function Button:init()
	local text_widget = TextWidget:new{
		text = self.text,
		face = Font:getFace(self.text_font_face, self.text_font_size)
	}
	local text_size = text_widget:getSize()
	-- set FrameContainer content
	self[1] = FrameContainer:new{
		margin = self.margin,
		bordersize = self.bordersize,
		background = self.background,
		radius = self.radius,
		padding = self.padding,
		HorizontalGroup:new{
			HorizontalSpan:new{ width = (self.width - text_size.w)/2 },
			text_widget,
			HorizontalSpan:new{ width = (self.width - text_size.w)/2 },
		}
	}
	if self.preselect then
		self[1].color = 15
	else
		self[1].color = 5
	end
	self.dimen = self[1]:getSize()
	if Device:isTouchDevice() then
		self.ges_events = {
			TapSelect = {
				GestureRange:new{
					ges = "tap",
					range = self.dimen,
				},
				doc = "Tap Button",
			},
		}
	end
end

function Button:onFocus()
	self[1].color = 15
	return true
end

function Button:onUnfocus()
	self[1].color = 5
	return true
end

function Button:onTapSelect()
	self.callback()
	return true
end
