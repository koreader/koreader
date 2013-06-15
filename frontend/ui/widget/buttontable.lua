require "ui/widget/base"
require "ui/widget/line"

ButtonTable = InputContainer:new{
	buttons = {
		{
			{text="OK", callback=nil},
			{text="Cancel", callback=nil},
		},
	},
	tap_close_callback = nil,
}

function ButtonTable:init()
	if Device:hasKeyboard() then
		key_events = {
			AnyKeyPressed = { { Input.group.Any },
				seqtext = "any key", doc = _("close dialog") }
		}
	else
		self.ges_events.TapClose = {
			GestureRange:new{
				ges = "tap",
				range = Geom:new{
					x = 0, y = 0,
					w = Screen:getWidth(),
					h = Screen:getHeight(),
				}
			}
		}
	end
	local vertical_group = VerticalGroup:new{}
	local horizontal_sep = LineWidget:new{
		background = 8,
		dimen = Geom:new{
			w = Screen:getWidth()*0.9,
			h = 1,
		}
	}
	for i = 1, #self.buttons do
		local horizontal_group = HorizontalGroup:new{}
		local line = self.buttons[i]
		for j = 1, #line do
			local button = Button:new{
				text = line[j].text,
				callback = line[j].callback,
				width = Screen:getWidth()*0.9/#line,
				bordersize = 0,
				text_font_face = "cfont",
				text_font_size = scaleByDPI(18),
			}
			local button_dim = button:getSize()
			local vertical_sep = LineWidget:new{
				background = 8,
				dimen = Geom:new{
					w = scaleByDPI(1),
					h = button_dim.h,
				}
			}
			table.insert(horizontal_group, button)
			if j < #line then
				table.insert(horizontal_group, vertical_sep)
			end
		end -- end for each button
		table.insert(vertical_group, horizontal_group)
		if i < #self.buttons then
			table.insert(vertical_group, VerticalSpan:new{ width = scaleByDPI(2) })
			table.insert(vertical_group, horizontal_sep)
			table.insert(vertical_group, VerticalSpan:new{ width = scaleByDPI(2) })
		end
	end -- end for each button line
	self[1] = CenterContainer:new{
		dimen = Screen:getSize(),
		FrameContainer:new{
			vertical_group,
			background = 0,
			bordersize = 2,
			radius = 7,
			padding = 2,
		},
	}
end

function ButtonTable:onTapClose()
	UIManager:close(self)
	if self.tap_close_callback then
		self.tap_close_callback()
	end
	return true
end
