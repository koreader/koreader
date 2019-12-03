--[[--
RightContainer aligns its content (1 widget) at the right of its own dimensions
--]]

local BD = require("ui/bidi")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local RightContainer = WidgetContainer:new{
    allow_mirroring = true,
    _mirroredUI = BD.mirroredUILayout(),
}

function RightContainer:paintTo(bb, x, y)
    local contentSize = self[1]:getSize()
    --- @fixme
    -- if contentSize.w > self.dimen.w or contentSize.h > self.dimen.h then
        -- throw error? paint to scrap buffer and blit partially?
        -- for now, we ignore this
    -- end
    if not self._mirroredUI or not self.allow_mirroring then
        x = x + (self.dimen.w - contentSize.w)
    -- else: keep x, as in LeftContainer
    end
    self[1]:paintTo(bb,
        x,
        y + math.floor((self.dimen.h - contentSize.h)/2))
end

return RightContainer
