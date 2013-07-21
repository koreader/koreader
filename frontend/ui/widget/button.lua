require "ui/widget/container"

--[[
a button widget
--]]
Button = InputContainer:new{
	text = nil, -- mandatory
	preselect = false,
	callback = nil,
	enabled = true,
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
	self.text_widget = TextWidget:new{
		text = self.text,
		bgcolor = 0.0,
		fgcolor = self.enabled and 1.0 or 0.5,
		face = Font:getFace(self.text_font_face, self.text_font_size)
	}
	local text_size = self.text_widget:getSize()
	if self.width == nil then
		self.width = text_size.w
	end
	-- set FrameContainer content
	self[1] = FrameContainer:new{
		margin = self.margin,
		bordersize = self.bordersize,
		background = self.background,
		radius = self.radius,
		padding = self.padding,
		CenterContainer:new{
			dimen = Geom:new{
				w = self.width,
				h = text_size.h
			},
			self.text_widget,
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
				doc = _("Tap Button"),
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

function Button:enable()
	self.enabled = true
	self.text_widget.fgcolor = 1.0
end

function Button:disable()
	self.enabled = false
	self.text_widget.fgcolor = 0.5
end

function Button:onTapSelect()
	if self.enabled then
		self.callback()
	end
	return true
end
