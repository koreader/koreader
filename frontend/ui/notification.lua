require "ui/ui"
require "ui/widget"

--[[
Widget that displays a tiny notification on top of screen
--]]
Notification = InputContainer:new{
	face = Font:getFace("infofont", 20),
	text = "Null Message",
	timeout = nil,

	key_events = {
		AnyKeyPressed = { { Input.group.Any }, seqtext = "any key", doc = "close dialog" }
	}
}

function Notification:init()
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

