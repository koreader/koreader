local WidgetContainer = require("ui/widget/container/widgetcontainer")

--[[
A Layout widget that puts objects besides each others
--]]
local HorizontalGroup = WidgetContainer:new{
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

return HorizontalGroup
