local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Geom = require("ui/geometry")

--[[
BottomContainer contains its content (1 widget) at the bottom of its own
dimensions
--]]
local BottomContainer = WidgetContainer:new()

function BottomContainer:paintTo(bb, x, y)
    local contentSize = self[1]:getSize()
    if contentSize.w > self.dimen.w or contentSize.h > self.dimen.h then
        -- throw error? paint to scrap buffer and blit partially?
        -- for now, we ignore this
    end
    self[1]:paintTo(bb,
        x + math.floor((self.dimen.w - contentSize.w)/2),
        y + (self.dimen.h - contentSize.h))
end

function BottomContainer:contentRange()
    local contentSize = self[1]:getSize()
    return Geom:new{
        x = (self.dimen.x or 0) + math.floor((self.dimen.w - contentSize.w)/2),
        y = (self.dimen.y or 0) + self.dimen.h - contentSize.h,
        w = contentSize.w,
        h = contentSize.h
    }
end

return BottomContainer
