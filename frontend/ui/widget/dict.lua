require "ui/widget/container"

--[[
Display quick lookup word definition
]]
DictQuickLookup = InputContainer:new{
	dict = nil,
	definition = nil,
	id = nil,
	lang = nil,
	
	title_face = Font:getFace("tfont", 20),
	content_face = Font:getFace("cfont", 18),
	width = Screen:getWidth() - 100
}

function DictQuickLookup:init()
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
			VerticalGroup:new{
				align = "center",
				-- title bar
				TextBoxWidget:new{
					text = self.dict,
					face = self.title_face,
					width = self.width,
				},
				VerticalSpan:new{ width = 20 },
				TextBoxWidget:new{
					text = self.definition,
					face = self.content_face,
					width = self.width,
				}
			}
		}
	}
end

function DictQuickLookup:onAnyKeyPressed()
	-- triggered by our defined key events
	UIManager:close(self)
	return true
end

function DictQuickLookup:onTapClose()
	UIManager:close(self)
	return true
end
