require "ui/widget/container"

--[[
Widget that displays a tiny notification on top of screen
--]]
Notification = InputContainer:new{
	face = Font:getFace("infofont", 20),
	text = "Null Message",
	timeout = nil,
}

function Notification:init()
	if Device:hasKeyboard() then
		key_events = {
			AnyKeyPressed = { { Input.group.Any }, seqtext = "any key", doc = "close dialog" }
		}
	end
	-- we construct the actual content here because self.text is only available now
	self[1] = CenterContainer:new{
		dimen = Geom:new{
			w = Screen:getWidth(),
			h = Screen:getHeight()/10,
		},
		ignore = "height",
		FrameContainer:new{
			background = 0,
			radius = 0,
			HorizontalGroup:new{
				align = "center",
				TextBoxWidget:new{
					text = self.text,
					face = self.face,
				}
			}
		}
	}
end

function Notification:onShow()
	-- triggered by the UIManager after we got successfully shown (not yet painted)
	if self.timeout then
		UIManager:scheduleIn(self.timeout, function() UIManager:close(self) end)
	end
	return true
end

function Notification:onAnyKeyPressed()
	-- triggered by our defined key events
	UIManager:close(self)
	return true
end

