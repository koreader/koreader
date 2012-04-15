require "rendertext"
require "graphics"
require "image"

--[[
This is a (useless) generic Widget interface

widgets can be queried about their size and can be paint.
that's it for now. Probably we need something more elaborate
later.
]]
Widget = {
	dimen = { w = 0, h = 0},
}

function Widget:new(o)
	o = o or {}
	setmetatable(o, self)
	self.__index = self
	return o
end

function Widget:getSize()
	return self.dimen
end

function Widget:paintTo(bb, x, y)
end

function Widget:free()
end

--[[
WidgetContainer is a container for another Widget
]]
WidgetContainer = Widget:new()

function WidgetContainer:free()
	for _, widget in ipairs(self) do
		widget:free()
	end
end

--[[
CenterContainer centers its content (1 widget) within its own dimensions
]]
CenterContainer = WidgetContainer:new()

function CenterContainer:paintTo(bb, x, y)
	local contentSize = self[1]:getSize()
	if contentSize.w > self.dimen.w or contentSize.h > self.dimen.h then
		-- throw error?
		return
	end
	self[1]:paintTo(bb,
		x + (self.dimen.w - contentSize.w)/2,
		y + (self.dimen.h - contentSize.h)/2)
end

--[[
A FrameContainer is some graphics content (1 widget) that is surrounded by a frame
]]
FrameContainer = WidgetContainer:new({
	background = nil,
	color = 15,
	margin = 0,
	bordersize = 2,
	padding = 5,
})

function FrameContainer:getSize()
	local content_size = self[1]:getSize()
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
	self[1]:paintTo(bb,
		x + self.margin + self.bordersize + self.padding,
		y + self.margin + self.bordersize + self.padding)
end

--[[
A TextWidget puts a string on a single line
]]
TextWidget = Widget:new({
	text = nil,
	face = nil,
	color = 15,
	_bb = nil,
	_length = 0,
	_maxlength = 1200,
})

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
ImageWidget = Widget:new({
	file = nil,
	_bb = nil
})

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
HorizontalGroup = WidgetContainer:new({
	align = "center",
	_size = nil,
})

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
VerticalGroup = WidgetContainer:new({
	align = "center",
	_size = nil,
	_offsets = {}
})

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
