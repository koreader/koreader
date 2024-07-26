--[[--
RightContainer aligns its content (1 widget) at the right of its own dimensions
--]]

local BD = require("ui/bidi")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local RightContainer = WidgetContainer:extend{
    allow_mirroring = true,
}

function RightContainer:paintTo(bb, x, y)
    local contentSize = self[1]:getSize()
    --- @fixme
    -- if contentSize.w > self.dimen.w or contentSize.h > self.dimen.h then
        -- throw error? paint to scrap buffer and blit partially?
        -- for now, we ignore this
    -- end
    if not BD.mirroredUILayout() or not self.allow_mirroring then
        x = x + (self.dimen.w - contentSize.w)
    -- else: keep x, as in LeftContainer
    end
    self.dimen.x = x
    self.dimen.y = y + math.floor((self.dimen.h - contentSize.h)/2)
    self[1]:paintTo(bb, self.dimen.x, self.dimen.y)
end

return RightContainer
