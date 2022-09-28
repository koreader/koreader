local Widget = require("ui/widget/widget")

--[[
Dummy Widget that reserves vertical space
--]]
local VerticalSpan = Widget:extend{
    width = 0,
}

function VerticalSpan:getSize()
    return {w = 0, h = self.width}
end

return VerticalSpan
