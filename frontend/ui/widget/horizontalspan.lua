local Widget = require("ui/widget/widget")

--[[
Dummy Widget that reserves horizontal space
--]]
local HorizontalSpan = Widget:new{
    width = 0,
}

function HorizontalSpan:getSize()
    return {w = self.width, h = 0}
end

return HorizontalSpan
