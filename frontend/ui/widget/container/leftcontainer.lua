local WidgetContainer = require("ui/widget/container/widgetcontainer")

--[[
LeftContainer aligns its content (1 widget) at the left of its own dimensions
--]]
local LeftContainer = WidgetContainer:new()

function LeftContainer:paintTo(bb, x, y)
	local contentSize = self[1]:getSize()
	if contentSize.w > self.dimen.w or contentSize.h > self.dimen.h then
		-- throw error? paint to scrap buffer and blit partially?
		-- for now, we ignore this
	end
	self[1]:paintTo(bb, x , y + math.floor((self.dimen.h - contentSize.h)/2))
end

return LeftContainer
