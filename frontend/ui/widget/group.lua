require "ui/widget/container"


--[[
A Layout widget that puts objects besides each others
--]]
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
			widget:paintTo(bb,
				x + self._offsets[i].x,
				y + math.floor((size.h - self._offsets[i].y) / 2))
		elseif self.align == "top" then
			widget:paintTo(bb, x + self._offsets[i].x, y)
		elseif self.align == "bottom" then
			widget:paintTo(bb, x + self._offsets[i].x, y + size.h - self._offsets[i].y)
		end
	end
end

function HorizontalGroup:clear()
	self:free()
	WidgetContainer.clear(self)
end

function HorizontalGroup:resetLayout()
	self._size = nil
	self._offsets = {}
end

function HorizontalGroup:free()
	self:resetLayout()
	WidgetContainer.free(self)
end


--[[
A Layout widget that puts objects under each other
--]]
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
			widget:paintTo(bb,
				x + math.floor((size.w - self._offsets[i].x) / 2),
				y + self._offsets[i].y)
		elseif self.align == "left" then
			widget:paintTo(bb, x, y + self._offsets[i].y)
		elseif self.align == "right" then
			widget:paintTo(bb,
				x + size.w - self._offsets[i].x,
				y + self._offsets[i].y)
		end
	end
end

function VerticalGroup:clear()
	self:free()
	WidgetContainer.clear(self)
end

function VerticalGroup:resetLayout()
	self._size = nil
	self._offsets = {}
end

function VerticalGroup:free()
	self:resetLayout()
	WidgetContainer.free(self)
end


--[[
A Layout widget that puts objects above each other
--]]
OverlapGroup = WidgetContainer:new{
	_size = nil,
}

function OverlapGroup:getSize()
	if not self._size then
		self._size = {w = 0, h = 0}
		self._offsets = { x = math.huge, y = math.huge }
		for i, widget in ipairs(self) do
			local w_size = widget:getSize()
			if self._size.h < w_size.h then
				self._size.h = w_size.h
			end
			if self._size.w < w_size.w then
				self._size.w = w_size.w
			end
		end
	end

	if self.dimen.w then
		self._size.w = self.dimen.w
	end
	if self.dimen.h then
		self._size.h = self.dimen.h
	end

	return self._size
end

function OverlapGroup:paintTo(bb, x, y)
	local size = self:getSize()

	for i, wget in ipairs(self) do
		local wget_size = wget:getSize()
		if wget.align == "right" then
			wget:paintTo(bb, x+size.w-wget_size.w, y)
		elseif wget.align == "center" then
			wget:paintTo(bb, x+math.floor((size.w-wget_size.w)/2), y)
		else
			-- default to left
			wget:paintTo(bb, x, y)
		end
	end
end

