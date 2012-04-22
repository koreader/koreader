require "rendertext"
require "graphics"
require "image"
require "event"
require "inputevent"
require "font"

--[[
This is a generic Widget interface

widgets can be queried about their size and can be paint.
that's it for now. Probably we need something more elaborate
later.

if the table that was given to us as parameter has an "init"
method, it will be called. use this to set _instance_ variables
rather than class variables.
]]
Widget = {}

function Widget:new(o)
	local o = o or {}
	setmetatable(o, self)
	self.__index = self
	if o.init then o:init() end
	return o
end

function Widget:getSize()
	return self.dimen
end

function Widget:paintTo(bb, x, y)
end

--[[
Widgets have a rudimentary event handler/dispatcher that
will call a method "onEventName" for an event with name
"EventName"

These methods
]]
function Widget:handleEvent(event)
	if self[event.handler] then
		return self[event.handler](self, unpack(event.args))
	end
end

--[[
WidgetContainer is a container for another Widget
]]
WidgetContainer = Widget:new()

function WidgetContainer:getSize()
	if self.dimen then
		-- fixed size
		return self.dimen
	elseif self[1] then
		-- return size of first child widget
		return self[1]:getSize()
	else
		return { w = 0, h = 0 }
	end
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
]]
function WidgetContainer:handleEvent(event)
	-- call our own standard event handler
	if not self:propagateEvent(event) then
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
CenterContainer centers its content (1 widget) within its own dimensions
]]
CenterContainer = WidgetContainer:new()

function CenterContainer:paintTo(bb, x, y)
	local contentSize = self[1]:getSize()
	if contentSize.w > self.dimen.w or contentSize.h > self.dimen.h then
		-- throw error? paint to scrap buffer and blit partially?
		-- for now, we ignore this
	end
	self[1]:paintTo(bb,
		x + (self.dimen.w - contentSize.w)/2,
		y + (self.dimen.h - contentSize.h)/2)
end

--[[
A FrameContainer is some graphics content (1 widget) that is surrounded by a frame
]]
FrameContainer = WidgetContainer:new{
	background = nil,
	color = 15,
	margin = 0,
	bordersize = 2,
	padding = 5,
}

function FrameContainer:getSize()
	local content_size = WidgetContainer.getSize(self)
	return {
		w = content_size.w + ( self.margin + self.bordersize + self.padding ) * 2,
		h = content_size.h + ( self.margin + self.bordersize + self.padding ) * 2
	}
end

function FrameContainer:paintTo(bb, x, y)
	local my_size = self:getSize()

	if self.background then
		bb:paintRect(x, y, my_size.w, my_size.h, self.background)
	end
	if self.bordersize > 0 then
		bb:paintBorder(x + self.margin, y + self.margin,
			my_size.w - self.margin * 2, my_size.h - self.margin * 2,
			self.bordersize, self.color)
	end
	if self[1] then
		self[1]:paintTo(bb,
			x + self.margin + self.bordersize + self.padding,
			y + self.margin + self.bordersize + self.padding)
	end
end

--[[
A TextWidget puts a string on a single line
]]
TextWidget = Widget:new{
	text = nil,
	face = nil,
	color = 15,
	_bb = nil,
	_length = 0,
	_maxlength = 1200,
}

function TextWidget:_render()
	local h = self.face.size * 1.5
	self._bb = Blitbuffer.new(self._maxlength, h)
	self._length = renderUtf8Text(self._bb, 0, h*.7, self.face, self.text, self.color)
end

function TextWidget:getSize()
	if not self._bb then
		self:_render()
	end
	return { w = self._length, h = self._bb:getHeight() }
end

function TextWidget:paintTo(bb, x, y)
	if not self._bb then
		self:_render()
	end
	bb:blitFrom(self._bb, x, y, 0, 0, self._length, self._bb:getHeight())
end

function TextWidget:free()
	if self._bb then
		self._bb:free()
		self._bb = nil
	end
end

--[[
ImageWidget shows an image from a file
]]
ImageWidget = Widget:new{
	file = nil,
	_bb = nil
}

function ImageWidget:_render()
	local itype = string.lower(string.match(self.file, ".+%.([^.]+)") or "")
	if itype == "jpeg" or itype == "jpg" then
		self._bb = Image.fromJPEG(self.file)
	elseif itype == "png" then
		self._bb = Image.fromPNG(self.file)
	end
end

function ImageWidget:getSize()
	if not self._bb then
		self:_render()
	end
	return { w = self._bb:getWidth(), h = self._bb:getHeight() }
end

function ImageWidget:paintTo(bb, x, y)
	local size = self:getSize()
	bb:blitFrom(self._bb, x, y, 0, 0, size.w, size.h)
end

function ImageWidget:free()
	if self._bb then
		self._bb:free()
		self._bb = nil
	end
end

--[[
A Layout widget that puts objects besides each others
]]
HorizontalGroup = WidgetContainer:new{
	align = "center",
	_size = nil,
}

function HorizontalGroup:getSize()
	if not self._size then
		self._size = { w = 0, h = 0 }
		self._offsets = { }
		for i, widget in ipairs(self) do
			local w_size = widget:getSize()
			self._offsets[i] = {
				x = self._size.w,
				y = w_size.h
			}
			self._size.w = self._size.w + w_size.w
			if w_size.h > self._size.h then
				self._size.h = w_size.h
			end
		end
	end
	return self._size
end

function HorizontalGroup:paintTo(bb, x, y)
	local size = self:getSize()
	
	for i, widget in ipairs(self) do
		if self.align == "center" then
			widget:paintTo(bb, x + self._offsets[i].x, y + (size.h - self._offsets[i].y) / 2)
		elseif self.align == "top" then
			widget:paintTo(bb, x + self._offsets[i].x, y)
		elseif self.align == "bottom" then
			widget:paintTo(bb, x + self._offsets[i].x, y + size.h - self._offsets[i].y)
		end
	end
end

function HorizontalGroup:free()
	self._size = nil
	self._offsets = {}
	WidgetContainer.free(self)
end

--[[
A Layout widget that puts objects under each other
]]
VerticalGroup = WidgetContainer:new{
	align = "center",
	_size = nil,
	_offsets = {}
}

function VerticalGroup:getSize()
	if not self._size then
		self._size = { w = 0, h = 0 }
		self._offsets = { }
		for i, widget in ipairs(self) do
			local w_size = widget:getSize()
			self._offsets[i] = {
				x = w_size.w,
				y = self._size.h,
			}
			self._size.h = self._size.h + w_size.h
			if w_size.w > self._size.w then
				self._size.w = w_size.w
			end
		end
	end
	return self._size
end

function VerticalGroup:paintTo(bb, x, y)
	local size = self:getSize()
	
	for i, widget in ipairs(self) do
		if self.align == "center" then
			widget:paintTo(bb, x + (size.w - self._offsets[i].x) / 2, y + self._offsets[i].y)
		elseif self.align == "left" then
			widget:paintTo(bb, x, y + self._offsets[i].y)
		elseif self.align == "right" then
			widget:paintTo(bb, x + size.w - self._offsets[i].x, y + self._offsets[i].y)
		end
	end
end

function VerticalGroup:free()
	self._size = nil
	self._offsets = {}
	WidgetContainer.free(self)
end

--[[
an UnderlineContainer is a WidgetContainer that is able to paint
a line under its child node
]]

UnderlineContainer = WidgetContainer:new{
	linesize = 2,
	padding = 1,
	color = 0,
}

function UnderlineContainer:getSize()
	local contentSize = self[1]:getSize()
	return { w = contentSize.w, h = contentSize.h + self.linesize + self.padding }
end

function UnderlineContainer:paintTo(bb, x, y)
	local contentSize = self[1]:getSize()
	self[1]:paintTo(bb, x, y)
	bb:paintRect(x, y + contentSize.h + self.padding,
		contentSize.w, self.linesize, self.color)
end


--[[
an InputContainer is an WidgetContainer that handles input events

an example for a key_event is this:

  PanBy20 = { { "Shift", Input.group.Cursor }, seqtext = "Shift+Cursor", doc = "pan by 20px", event = "Pan", args = 20, is_inactive = true },
  PanNormal = { { Input.group.Cursor }, seqtext = "Cursor", doc = "pan by 10 px", event = "Pan", args = 10 },
  Quit = { {"Home"} },

it is suggested to reference configurable sequences from another table
and store that table as configuration setting
]]
InputContainer = WidgetContainer:new{
	key_events = {}
}

-- the following handler handles keypresses and checks
-- if they lead to a command.
-- if this is the case, we retransmit another event within
-- ourselves
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

