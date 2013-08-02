require "ui/widget/image"
require "ui/widget/container"

--[[
a button widget that shows text or a icon and handles callback when tapped
--]]
Button = InputContainer:new{
	text = nil, -- mandatory
	icon = nil,
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
	if self.text then
		self.label_widget = TextWidget:new{
			text = self.text,
			bgcolor = 0.0,
			fgcolor = self.enabled and 1.0 or 0.5,
			face = Font:getFace(self.text_font_face, self.text_font_size)
		}
	else
		self.label_widget = ImageWidget:new{
			file = self.icon,
			dim = self.enabled,
		}
	end
	local widget_size = self.label_widget:getSize()
	if self.width == nil then
		self.width = widget_size.w
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
				h = widget_size.h
			},
			self.label_widget,
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
	if self.text then
		self.label_widget.fgcolor = self.enabled and 1.0 or 0.5
	else
		self.label_widget.dim = not self.enabled
	end
end

function Button:disable()
	self.enabled = false
	if self.text then
		self.label_widget.fgcolor = self.enabled and 1.0 or 0.5
	else
		self.label_widget.dim = not self.enabled
	end
end

function Button:enableDisable(enable)
	if enable then
		self:enable()
	else
		self:disable()
	end
end

function Button:hide()
	if self.icon then
		self.label_widget.hide = true
	end
end

function Button:show()
	if self.icon then
		self.label_widget.hide = false
	end
end

function Button:showHide(show)
	if show then
		self:show()
	else
		self:hide()
	end
end

function Button:onTapSelect()
	if self.enabled then
		self.callback()
	end
	return true
end
