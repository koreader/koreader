local WidgetContainer = require("ui/widget/container/widgetcontainer")

--[[
RightContainer aligns its content (1 widget) at the right of its own dimensions
--]]
local RightContainer = WidgetContainer:new()

function RightContainer:paintTo(bb, x, y)
    local contentSize = self[1]:getSize()
    if contentSize.w > self.dimen.w or contentSize.h > self.dimen.h then
        -- throw error? paint to scrap buffer and blit partially?
        -- for now, we ignore this
    end
    self[1]:paintTo(bb,
        x + (self.dimen.w - contentSize.w),
        y + math.floor((self.dimen.h - contentSize.h)/2))
end

return RightContainer
