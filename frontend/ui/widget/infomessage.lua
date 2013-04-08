require "ui/widget/container"

--[[
Widget that displays an informational message

it vanishes on key press or after a given timeout
]]
InfoMessage = InputContainer:new{
	face = Font:getFace("infofont", 25),
	text = "",
	timeout = nil, -- in seconds
}

function InfoMessage:init()
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
	-- we construct the actual content here because self.text is only available now
	self[1] = CenterContainer:new{
		dimen = Screen:getSize(),
		FrameContainer:new{
			margin = 2,
			background = 0,
			HorizontalGroup:new{
				align = "center",
				ImageWidget:new{
					file = "resources/info-i.png"
				},
				HorizontalSpan:new{ width = 10 },
				TextBoxWidget:new{
					text = self.text,
					face = Font:getFace("cfont", 30)
				}
			}
		}
	}
end

function InfoMessage:onShow()
	-- triggered by the UIManager after we got successfully shown (not yet painted)
	if self.timeout then
		UIManager:scheduleIn(self.timeout, function() UIManager:close(self) end)
	end
	return true
end

function InfoMessage:onAnyKeyPressed()
	-- triggered by our defined key events
	UIManager:close(self)
	return true
end

function InfoMessage:onTapClose()
	UIManager:close(self)
	return true
end
