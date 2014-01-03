local TextWidget = require("ui/widget/textwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local RenderText = require("ui/rendertext")
local UIManager = require("ui/uimanager")
local Screen = require("ui/screen")
local Device = require("ui/device")
local GestureRange = require("ui/gesturerange")
local DEBUG = require("dbg")
local _ = require("gettext")

local ToggleLabel = TextWidget:new{
	bgcolor = 0,
	fgcolor = 1,
}

function ToggleLabel:paintTo(bb, x, y)
	RenderText:renderUtf8Text(bb, x, y+self._height*0.75, self.face, self.text, true, self.bgcolor, self.fgcolor)
end

local ToggleSwitch = InputContainer:new{
	width = Screen:scaleByDPI(216),
	height = Screen:scaleByDPI(30),
	bgcolor = 0, -- unfoused item color
	fgcolor = 7, -- focused item color
}

function ToggleSwitch:init()
	self.n_pos = #self.toggle
	self.position = nil

	local label_font_face = "cfont"
	local label_font_size = 16

	self.toggle_frame = FrameContainer:new{background = 0, color = 7, radius = 7, bordersize = 1, padding = 2,}
	self.toggle_content = HorizontalGroup:new{}

	for i=1,#self.toggle do
		local label = ToggleLabel:new{
			align = "center",
			text = self.toggle[i],
			face = Font:getFace(label_font_face, label_font_size),
		}
		local content = CenterContainer:new{
			dimen = Geom:new{w = self.width/self.n_pos, h = self.height},
			label,
		}
		local button = FrameContainer:new{
			background = 0,
			color = 7,
			margin = 0,
			radius = 5,
			bordersize = 1,
			padding = 0,
			content,
		}
		table.insert(self.toggle_content, button)
	end

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
				doc = _("Toggle switch"),
			},
		}
	end
end

function ToggleSwitch:update()
	local pos = self.position
	for i=1,#self.toggle_content do
		if pos == i then
			self.toggle_content[i].color = self.fgcolor
			self.toggle_content[i].background = self.fgcolor
			self.toggle_content[i][1][1].bgcolor = self.fgcolor/15
			self.toggle_content[i][1][1].fgcolor = 0.0
		else
			self.toggle_content[i].color = self.bgcolor
			self.toggle_content[i].background = self.bgcolor
			self.toggle_content[i][1][1].bgcolor = 0.0
			self.toggle_content[i][1][1].fgcolor = 1.0
		end
	end
end

function ToggleSwitch:setPosition(position)
	self.position = position
	self:update()
end

function ToggleSwitch:togglePosition(position)
	if self.n_pos == 2 and self.alternate ~= false then
		self.position = (self.position+1)%self.n_pos
		self.position = self.position == 0 and self.n_pos or self.position
	elseif self.n_pos == 1 then
		self.position = self.position == 1 and 0 or 1
	else
		self.position = position
	end
	self:update()
end

function ToggleSwitch:onTapSelect(arg, gev)
	local position = math.ceil(
		(gev.pos.x - self.dimen.x) / self.dimen.w * self.n_pos
	)
	--DEBUG("toggle position:", position)
	self:togglePosition(position)
	--[[
	if self.values then
		self.values = self.values or {}
		self.config:onConfigChoice(self.name, self.values[self.position])
	end
	if self.event then
		self.args = self.args or {}
		self.config:onConfigEvent(self.event, self.args[self.position])
	end
	if self.events then
		self.config:onConfigEvents(self.events, self.position)
	end
	--]]
	self.config:onConfigChoose(self.values, self.name, self.event, self.args, self.events, self.position)
	UIManager:setDirty(self.config, "partial")
	return true
end

return ToggleSwitch
