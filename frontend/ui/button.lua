require "ui/widget"

--[[
a button widget
]]
Button = WidgetContainer:new{
	text = nil, -- mandatory
	preselect = false
}

function Button:init()
	-- set FrameContainer content
	self[1] = FrameContainer:new{
		margin = 0,
		bordersize = 3,
		background = 0,
		radius = 15,
		padding = 2,

		HorizontalGroup:new{
			HorizontalSpan:new{ width = 8 },
			TextWidget:new{
				text = self.text,
				face = Font:getFace("cfont", 20)
			},
			HorizontalSpan:new{ width = 8 },
		}
	}
	if self.preselect then
		self[1].color = 15
	else
		self[1].color = 5
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

