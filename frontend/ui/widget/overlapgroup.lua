local WidgetContainer = require("ui/widget/container/widgetcontainer")

--[[
A Layout widget that puts objects above each other
--]]
local OverlapGroup = WidgetContainer:new{
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

return OverlapGroup
