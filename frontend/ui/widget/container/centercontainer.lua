local WidgetContainer = require("ui/widget/container/widgetcontainer")

--[[
CenterContainer centers its content (1 widget) within its own dimensions
--]]
local CenterContainer = WidgetContainer:new()

function CenterContainer:paintTo(bb, x, y)
	local contentSize = self[1]:getSize()
	if contentSize.w > self.dimen.w or contentSize.h > self.dimen.h then
		-- throw error? paint to scrap buffer and blit partially?
		-- for now, we ignore this
	end
	local x_pos = x
	local y_pos = y
	if self.ignore ~= "height" then
		y_pos = y + math.floor((self.dimen.h - contentSize.h)/2)
	end
	if self.ignore ~= "width" then
		x_pos = x + math.floor((self.dimen.w - contentSize.w)/2)
	end
	self[1]:paintTo(bb, x_pos, y_pos)
end

return CenterContainer
