require "ui/widget/base"

--[[
WidgetContainer is a container for another Widget
--]]
WidgetContainer = Widget:new()

function WidgetContainer:init()
	if not self.dimen then
		self.dimen = Geom:new{}
	end
end

function WidgetContainer:getSize()
	if self.dimen then
		-- fixed size
		return self.dimen
	elseif self[1] then
		-- return size of first child widget
		return self[1]:getSize()
	else
		return Geom:new{ w = 0, h = 0 }
	end
end

--[[
delete all child widgets
--]]
function WidgetContainer:clear()
	while table.remove(self) do end
end

function WidgetContainer:paintTo(bb, x, y)
	-- default to pass request to first child widget
	if self[1] then
		return self[1]:paintTo(bb, x, y)
	end
end

function WidgetContainer:propagateEvent(event)
	-- propagate to children
	for _, widget in ipairs(self) do
		if widget:handleEvent(event) then
			-- stop propagating when an event handler returns true
			return true
		end
	end
	return false
end

--[[
Containers will pass events to children or react on them themselves
--]]
function WidgetContainer:handleEvent(event)
	if not self:propagateEvent(event) then
		-- call our own standard event handler
		return Widget.handleEvent(self, event)
	else
		return true
	end
end

function WidgetContainer:free()
	for _, widget in ipairs(self) do
		if widget.free then widget:free() end
	end
end

--[[
BottomContainer contains its content (1 widget) at the bottom of its own
dimensions
--]]
BottomContainer = WidgetContainer:new()

function BottomContainer:paintTo(bb, x, y)
	local contentSize = self[1]:getSize()
	if contentSize.w > self.dimen.w or contentSize.h > self.dimen.h then
		-- throw error? paint to scrap buffer and blit partially?
		-- for now, we ignore this
	end
	self[1]:paintTo(bb,
		x + (self.dimen.w - contentSize.w)/2,
		y + (self.dimen.h - contentSize.h))
end

--[[
CenterContainer centers its content (1 widget) within its own dimensions
--]]
CenterContainer = WidgetContainer:new()

function CenterContainer:paintTo(bb, x, y)
	local contentSize = self[1]:getSize()
	if contentSize.w > self.dimen.w or contentSize.h > self.dimen.h then
		-- throw error? paint to scrap buffer and blit partially?
		-- for now, we ignore this
	end
	local x_pos = x
	local y_pos = y
	if self.ignore ~= "height" then
		y_pos = y + (self.dimen.h - contentSize.h)/2
	end
	if self.ignore ~= "width" then
		x_pos = x + (self.dimen.w - contentSize.w)/2
	end
	self[1]:paintTo(bb, x_pos, y_pos)
end

--[[
LeftContainer aligns its content (1 widget) at the left of its own dimensions
--]]
LeftContainer = WidgetContainer:new()

function LeftContainer:paintTo(bb, x, y)
	local contentSize = self[1]:getSize()
	if contentSize.w > self.dimen.w or contentSize.h > self.dimen.h then
		-- throw error? paint to scrap buffer and blit partially?
		-- for now, we ignore this
	end
	self[1]:paintTo(bb, x , y + (self.dimen.h - contentSize.h)/2)
end

--[[
RightContainer aligns its content (1 widget) at the right of its own dimensions
--]]
RightContainer = WidgetContainer:new()

function RightContainer:paintTo(bb, x, y)
	local contentSize = self[1]:getSize()
	if contentSize.w > self.dimen.w or contentSize.h > self.dimen.h then
		-- throw error? paint to scrap buffer and blit partially?
		-- for now, we ignore this
	end
	self[1]:paintTo(bb,
		x + (self.dimen.w - contentSize.w),
		y + (self.dimen.h - contentSize.h)/2)
end

--[[
A FrameContainer is some graphics content (1 widget) that is surrounded by a
frame
--]]
FrameContainer = WidgetContainer:new{
	background = nil,
	color = 15,
	margin = 0,
	radius = 0,
	bordersize = 2,
	padding = 5,
	width = nil,
	height = nil,
	invert = false,
}

function FrameContainer:getSize()
	local content_size = self[1]:getSize()
	return Geom:new{
		w = content_size.w + ( self.margin + self.bordersize + self.padding ) * 2,
		h = content_size.h + ( self.margin + self.bordersize + self.padding ) * 2
	}
end

function FrameContainer:paintTo(bb, x, y)
	local my_size = self:getSize()
	self.dimen = Geom:new{
		x = x, y = y,
		w = my_size.w,
		h = my_size.h 
	}
	local container_width = self.width or my_size.w
	local container_height = self.height or my_size.h

	--@TODO get rid of margin here?  13.03 2013 (houqp)
	if self.background then
		bb:paintRoundedRect(x, y, container_width, container_height,
						self.background, self.radius)
	end
	if self.bordersize > 0 then
		bb:paintBorder(x + self.margin, y + self.margin,
			container_width - self.margin * 2,
			container_height - self.margin * 2,
			self.bordersize, self.color, self.radius)
	end
	if self[1] then
		self[1]:paintTo(bb,
			x + self.margin + self.bordersize + self.padding,
			y + self.margin + self.bordersize + self.padding)
	end
	if self.invert then
		bb:invertRect(x, y, container_width, container_height)
	end
end


--[[
an UnderlineContainer is a WidgetContainer that is able to paint
a line under its child node
--]]

UnderlineContainer = WidgetContainer:new{
	linesize = 2,
	padding = 1,
	color = 0,
	vertical_align = "top",
}

function UnderlineContainer:getSize()
	return self:getContentSize()
end

function UnderlineContainer:getContentSize()
	local contentSize = self[1]:getSize()
	return Geom:new{
		w = contentSize.w,
		h = contentSize.h + self.linesize + self.padding
	}
end

function UnderlineContainer:paintTo(bb, x, y)
	local container_size = self:getSize()
	local content_size = self:getContentSize()
	local p_y = y
	if self.vertical_align == "center" then
		p_y = (container_size.h - content_size.h) / 2 + y
	elseif self.vertical_align == "bottom" then
		p_y = (container_size.h - content_size.h) + y
	end
	self[1]:paintTo(bb, x, p_y)
	bb:paintRect(x, y + container_size.h - self.linesize,
		container_size.w, self.linesize, self.color)
end



--[[
an InputContainer is an WidgetContainer that handles input events

an example for a key_event is this:

	PanBy20 = {
		{ "Shift", Input.group.Cursor },
		seqtext = "Shift+Cursor",
		doc = "pan by 20px",
		event = "Pan", args = 20, is_inactive = true,
	},
	PanNormal = {
		{ Input.group.Cursor },
		seqtext = "Cursor",
		doc = "pan by 10 px", event = "Pan", args = 10,
	},
	Quit = { {"Home"} },

it is suggested to reference configurable sequences from another table
and store that table as configuration setting
--]]
InputContainer = WidgetContainer:new{
	vertical_align = "top",
}

function InputContainer:_init()
	-- we need to do deep copy here
	local new_key_events = {}
	if self.key_events then
		for k,v in pairs(self.key_events) do
			new_key_events[k] = v
		end
	end
	self.key_events = new_key_events

	local new_ges_events = {}
	if self.ges_events then
		for k,v in pairs(self.ges_events) do
			new_ges_events[k] = v
		end
	end
	self.ges_events = new_ges_events

	if not self.dimen then
		self.dimen = Geom:new{}
	end
end

function InputContainer:paintTo(bb, x, y)
	self.dimen.x = x
	self.dimen.y = y
	if self[1] then
		if self.vertical_align == "center" then
			local content_size = self[1]:getSize()
			self[1]:paintTo(bb, x, y + (self.dimen.h - content_size.h)/2)
		else
			self[1]:paintTo(bb, x, y)
		end
	end
end

--[[
the following handler handles keypresses and checks if they lead to a command.
if this is the case, we retransmit another event within ourselves
--]]
function InputContainer:onKeyPress(key)
	for name, seq in pairs(self.key_events) do
		if not seq.is_inactive then
			for _, oneseq in ipairs(seq) do
				if key:match(oneseq) then
					local eventname = seq.event or name
					return self:handleEvent(Event:new(eventname, seq.args, key))
				end
			end
		end
	end
end

function InputContainer:onGesture(ev)
	for name, gsseq in pairs(self.ges_events) do
		for _, gs_range in ipairs(gsseq) do
			--DEBUG("gs_range", gs_range)
			if gs_range:match(ev) then
				local eventname = gsseq.event or name
				return self:handleEvent(Event:new(eventname, gsseq.args, ev))
			end
		end
	end
end


