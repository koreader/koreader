require "ui/widget/container"
require "ui/widget/focusmanager"
require "ui/widget/button"

--[[
Widget that shows a message and OK/Cancel buttons
]]
ConfirmBox = FocusManager:new{
	text = "no text",
	width = nil,
	ok_text = "OK",
	cancel_text = "Cancel",
	ok_callback = function() end,
	cancel_callback = function() end,
}

function ConfirmBox:init()
	-- calculate box width on the fly if not given
	if not self.width then
		self.width = Screen:getWidth() - 200
	end
	-- build bottons
	self.key_events.Close = { {{"Home","Back"}}, doc = "cancel" }
	self.key_events.Select = { {{"Enter","Press"}}, doc = "chose selected option" }

	local ok_button = Button:new{
		text = self.ok_text,
		callback = function()
			self.ok_callback()
			UIManager:close(self)
		end,
	}
	local cancel_button = Button:new{
		text = self.cancel_text,
		preselect = true,
		callback = function()
			self.cancel_callback()
			UIManager:close(self)
		end,
	}

	self.layout = { { ok_button, cancel_button } }
	self.selected.x = 2 -- Cancel is default

	self[1] = CenterContainer:new{
		dimen = Screen:getSize(),
		FrameContainer:new{
			margin = 2,
			background = 0,
			padding = 10,
			HorizontalGroup:new{
				ImageWidget:new{
					file = "resources/info-i.png"
				},
				HorizontalSpan:new{ width = 10 },
				VerticalGroup:new{
					align = "left",
					TextBoxWidget:new{
						text = self.text,
						face = Font:getFace("cfont", 30),
						width = self.width,
					},
					VerticalSpan:new{ width = 10 },
					HorizontalGroup:new{
						ok_button,
						HorizontalSpan:new{ width = 10 },
						cancel_button,
					}
				}
			}
		}
	}
end

function ConfirmBox:onClose()
	UIManager:close(self)
	return true
end

function ConfirmBox:onSelect()
	DEBUG("selected:", self.selected.x)
	if self.selected.x == 1 then
		self:ok_callback()
	else
		self:cancel_callback()
	end
	UIManager:close(self)
	return true
end

