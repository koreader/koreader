--[[--
CenterContainer centers its content (1 widget) within its own dimensions
--]]

local WidgetContainer = require("ui/widget/container/widgetcontainer")

local CenterContainer = WidgetContainer:new()

function CenterContainer:paintTo(bb, x, y)
    local content_size = self[1]:getSize()
    -- FIXME
    -- if content_size.w > self.dimen.w or content_size.h > self.dimen.h then
        -- throw error? paint to scrap buffer and blit partially?
        -- for now, we ignore this
    -- end
    local x_pos = x
    local y_pos = y
    if self.ignore ~= "height" then
        y_pos = y + math.floor((self.dimen.h - content_size.h)/2)
    end
    if self.ignore ~= "width" then
        x_pos = x + math.floor((self.dimen.w - content_size.w)/2)
    end
    self[1]:paintTo(bb, x_pos, y_pos)
end

return CenterContainer
