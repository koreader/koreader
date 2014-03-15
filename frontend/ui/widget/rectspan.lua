local Widget = require("ui/widget/widget")

--[[
Dummy Widget that reserves vertical and horizontal space
]]
local RectSpan = Widget:new{
    width = 0,
    hright = 0,
}

function RectSpan:getSize()
    return {w = self.width, h = self.height}
end

return RectSpan
