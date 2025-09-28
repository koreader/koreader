--[[
CustomPositionContainer contains its content (1 widget) at a custom position within its own
dimensions
--]]

local Geom = require("ui/geometry")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local CustomPositionContainer = WidgetContainer:extend{
    vertical_position = 0.5,  -- 0.0 = topmost, 1.0 = bottommost
    horizontal_position = 0.5,  -- 0.0 = leftmost, 1.0 = rightmost
    widget = nil,
}

function CustomPositionContainer:paintTo(bb, x, y)
    if not self.widget then return end

    local content_size = self.widget:getSize()
    local container_w = self.dimen.w or content_size.w
    local container_h = self.dimen.h or content_size.h

    -- calculate desired position
    local desired_x = math.floor((container_w - content_size.w) * self.horizontal_position)
    local desired_y = math.floor((container_h - content_size.h) * self.vertical_position)

    -- clamp to container bounds
    local x_pos = x + math.max(0, math.min(desired_x, container_w - content_size.w))
    local y_pos = y + math.max(0, math.min(desired_y, container_h - content_size.h))

    self.widget:paintTo(bb, x_pos, y_pos)
end

function CustomPositionContainer:getSize()
    if self.dimen then
        return self.dimen
    end
    -- return widget size if no dimen set
    if self.widget then
        return self.widget:getSize()
    end
    return { w = 0, h = 0 }
end

return CustomPositionContainer
