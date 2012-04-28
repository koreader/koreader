require "widget"
require "font"
require "commands"

--[[
Wrapper Widget that manages focus for a whole dialog

supports a 2D model of active elements

e.g.:
	layout = {
		{ textinput, textinput },
		{ okbutton,  cancelbutton }
	}

this is a dialog with 2 rows. in the top row, there is the
single (!) widget <textinput>. when the focus is in this
group, left/right movement seems (!) to be doing nothing.

in the second row, there are two widgets and you can move
left/right. also, you can go up from both to reach <textinput>,
and from that go down and (depending on internat coordinates)
reach either <okbutton> or <cancelbutton>.

but notice that this does _not_ do the layout for you,
it rather defines an abstract layout.
]]
FocusManager = InputContainer:new{
	selected = nil, -- defaults to x=1, y=1
	layout = nil, -- mandatory
	movement_allowed = { x = true, y = true }
}

function FocusManager:init()
	self.selected = { x = 1, y = 1 }
	self.key_events = {
		-- these will all generate the same event, just with different arguments
		FocusUp =    { {"Up"},    doc = "move focus up",    event = "FocusMove", args = {0, -1} },
		FocusDown =  { {"Down"},  doc = "move focus down",  event = "FocusMove", args = {0,  1} },
		FocusLeft =  { {"Left"},  doc = "move focus left",  event = "FocusMove", args = {-1, 0} },
		FocusRight = { {"Right"}, doc = "move focus right", event = "FocusMove", args = {1,  0} },
	}
end

function FocusManager:onFocusMove(args)
	local dx, dy = unpack(args)

	if (dx ~= 0 and not self.movement_allowed.x)
		or (dy ~= 0 and not self.movement_allowed.y) then
		return true
	end

	local current_item = self.layout[self.selected.y][self.selected.x]
	while true do
		if self.selected.y + dy > #self.layout
		or self.selected.y + dy < 1
		or self.selected.x + dx > #self.layout[self.selected.y]
		or self.selected.x + dx < 1 then
			break -- abort when we run into borders
		end

		self.selected.x = self.selected.x + dx
		self.selected.y = self.selected.y + dy

		if self.layout[self.selected.y][self.selected.x] ~= current_item
		and not self.layout[self.selected.y][self.selected.x].is_inactive then
			-- we found a different object to focus
			current_item:handleEvent(Event:new("Unfocus"))
			self.layout[self.selected.y][self.selected.x]:handleEvent(Event:new("Focus"))
			-- trigger a repaint (we need to be the registered widget!)
			UIManager:setDirty(self)
			break
		end
	end

	return true
end


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
		bordersize = 4,
		background = 0,

		HorizontalGroup:new{
			Widget:new{ dimen = { w = 10, h = 0 } },
			TextWidget:new{
				text = self.text,
				face = Font:getFace("cfont", 20)
			},
			Widget:new{ dimen = { w = 10, h = 0 } }
		}
	}
	if self.preselect then
		self[1].color = 15
	else
		self[1].color = 0
	end
end

function Button:onFocus()
	self[1].color = 15
	return true
end

function Button:onUnfocus()
	self[1].color = 0
	return true
end


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
		self.width = G_width - 200
	end
	-- build bottons
	self.key_events.Close = { {{"Home","Back"}}, doc = "cancel" }
	self.key_events.Select = { {{"Enter","Press"}}, doc = "chose selected option" }

	local ok_button = Button:new{
		text = self.ok_text,
	}
	local cancel_button = Button:new{
		text = self.cancel_text,
		preselect = true
	}

	self.layout = { { ok_button, cancel_button } }
	self.selected.x = 2 -- Cancel is default 

	self[1] = CenterContainer:new{
		dimen = { w = G_width, h = G_height },
		FrameContainer:new{
			margin = 2,
			background = 0,
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
	self:cancel_callback()
	UIManager:close(self)
	return true
end

function ConfirmBox:onSelect()
	debug("selected:", self.selected.x)
	if self.selected.x == 1 then
		self:ok_callback()
	else
		self:cancel_callback()
	end
	UIManager:close(self)
	return true
end
	

--[[
Widget that displays an informational message

it vanishes on key press or after a given timeout
]]
InfoMessage = InputContainer:new{
	face = Font:getFace("infofont", 25),
	text = "",
	timeout = nil,

	key_events = {
		AnyKeyPressed = { { Input.group.Any }, seqtext = "any key", doc = "close dialog" }
	}
}

function InfoMessage:init()
	-- we construct the actual content here because self.text is only available now
	self[1] = CenterContainer:new{
		dimen = { w = G_width, h = G_height },
		FrameContainer:new{
			margin = 2,
			background = 0,
			HorizontalGroup:new{
				align = "center",
				ImageWidget:new{
					file = "resources/info-i.png"
				},
				HorizontalSpan:new{ width = 10 },
				TextWidget:new{
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
