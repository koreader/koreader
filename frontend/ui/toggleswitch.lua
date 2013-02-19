ToggleSwitch = InputContainer:new{}

function ToggleSwitch:init()
	self.n_pos = #self.toggle
	if self.n_pos ~= 2 and self.n_pos ~= 3 then
		-- currently only support options with two or three items.
		error("items number not supported")
	end
	self.position = nil
	
	local label_font_face = "cfont"
	local label_font_size = 16
	
	self.toggle_frame = FrameContainer:new{background = 0, color = 7, radius = 7, bordersize = 1, padding = 2,}
	self.toggle_content = HorizontalGroup:new{}
	
	self.left_label = ToggleLabel:new{
		align = "center",
		color = 0,
		text = self.toggle[self.n_pos],
		face = Font:getFace(label_font_face, label_font_size),
	}
	self.left_button = FrameContainer:new{
		background = 0,
		color = 7,
		margin = 0,
		radius = 5,
		bordersize = 1,
		padding = 2,
		self.left_label,
	}
	self.middle_label = ToggleLabel:new{
		align = "center",
		color = 0,
		text = self.n_pos > 2 and self.toggle[2] or "",
		face = Font:getFace(label_font_face, label_font_size),
	}
	self.middle_button = FrameContainer:new{
		background = 0,
		color = 7,
		margin = 0,
		radius = 5,
		bordersize = 1,
		padding = 2,
		self.middle_label,
	}
	self.right_label = ToggleLabel:new{
		align = "center",
		color = 0,
		text = self.toggle[1],
		face = Font:getFace(label_font_face, label_font_size),
	}
	self.right_button = FrameContainer:new{
		background = 0,
		color = 7,
		margin = 0,
		radius = 5,
		bordersize = 1,
		padding = 2,
		self.right_label,
	}
	
	table.insert(self.toggle_content, self.left_button)
  	table.insert(self.toggle_content, self.middle_button)
  	table.insert(self.toggle_content, self.right_button)
  	
	self.toggle_frame[1] = self.toggle_content
	self[1] = self.toggle_frame
	self.dimen = Geom:new(self.toggle_frame:getSize())
	if Device:isTouchDevice() then
		self.ges_events = {
			TapSelect = {
				GestureRange:new{
					ges = "tap",
					range = self.dimen,
				},
				doc = "Toggle switch",
			},
		}
	end
end

function ToggleSwitch:update()
	local left_pos = self.position == 1
	local right_pos = self.position == self.n_pos
	local middle_pos = not left_pos and not right_pos
	self.left_label.color = right_pos and 15 or 0
	self.left_button.color = left_pos and 7 or 0
	self.left_button.background = left_pos and 7 or 0
	self.middle_label.color = middle_pos and 15 or 0
	self.middle_button.color = middle_pos and 0 or 0
	self.middle_button.background = middle_pos and 0 or 0
	self.right_label.color = left_pos and 15 or 0
	self.right_button.color = right_pos and 7 or 0
	self.right_button.background = right_pos and 7 or 0
end

function ToggleSwitch:setPosition(position)
	self.position = position
	self:update()
end

function ToggleSwitch:togglePosition(position)
	if self.n_pos == 2 and self.alternate ~= false then
		self.position = (self.position+1)%self.n_pos
		self.position = self.position == 0 and self.n_pos or self.position
	else
		self.position = position
	end
	self:update()
end

function ToggleSwitch:onTapSelect(arg, gev)
	DEBUG("toggle position:", position)
	local position = math.ceil(
		(gev.pos.x - self.dimen.x) / self.dimen.w * self.n_pos
	)
	self:togglePosition(position)
	local option_value = nil
	local option_arg = nil
	if self.values then
		self.values = self.values or {}
		option_value = self.values[self.position]
		self.config:onConfigChoice(self.name, option_value)
	end
	if self.event then
		self.args = self.args or {}
		option_arg = self.args[self.position]
		self.config:onConfigEvent(self.event, option_arg)
	end
	if self.events then
		for i=1,#self.events do
			self.events[i].args = self.events[i].args or {}
			option_arg = self.events[i].args[self.position]
			self.config:onConfigEvent(self.events[i].event, option_arg)
		end
	end
	UIManager.repaint_all = true
end

