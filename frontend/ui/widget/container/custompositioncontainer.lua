--[[
CustomPositionContainer contains its content (1 widget) at a custom position within its own
dimensions
--]]

local Blitbuffer = require("ffi/blitbuffer")
local Screen = require("device").screen
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local CustomPositionContainer = WidgetContainer:extend{
    vertical_position = 0.5,  -- 0.0 = topmost, 1.0 = bottommost
    horizontal_position = 0.5,  -- 0.0 = leftmost, 1.0 = rightmost
    widget = nil,
    alpha = nil,  -- 1 = fully opaque, 0 = fully transparent
    compose_bb = nil,  -- cache for alpha composition
}

function CustomPositionContainer:paintTo(bb, x, y)
    if not self.widget then return end

    local content_size = self.widget:getSize()
    local container_w = (self.dimen and self.dimen.w) or Screen:getWidth()
    local container_h = (self.dimen and self.dimen.h) or Screen:getHeight()

    -- calculate desired position
    local desired_x = math.floor((container_w - content_size.w) * self.horizontal_position)
    local desired_y = math.floor((container_h - content_size.h) * self.vertical_position)

    -- clamp to container bounds
    local x_pos = x + math.max(0, math.min(desired_x, container_w - content_size.w))
    local y_pos = y + math.max(0, math.min(desired_y, container_h - content_size.h))

    -- Handle transparency (similar to MovableContainer but simpler)
    if self.alpha and self.alpha < 1.0 then
        -- Create/recreate compose canvas if needed
        if not self.compose_bb
            or self.compose_bb:getWidth() ~= bb:getWidth()
            or self.compose_bb:getHeight() ~= bb:getHeight()
        then
            if self.compose_bb then
                self.compose_bb:free()
            end
            self.compose_bb = Blitbuffer.new(bb:getWidth(), bb:getHeight(), bb:getType())
        end

        -- Copy the relevant portion of the background from the target buffer to compose buffer
        -- This gives us the actual background (cover image, solid color, etc.) so rounded corners
        -- don't show artifacts.
        self.compose_bb:blitFrom(bb, x_pos, y_pos, x_pos, y_pos, content_size.w, content_size.h)

        -- Paint widget to compose canvas
        self.widget:paintTo(self.compose_bb, x_pos, y_pos)

        -- Blit with alpha to target
        bb:addblitFrom(self.compose_bb, x_pos, y_pos, x_pos, y_pos, content_size.w, content_size.h, self.alpha)
    else
        -- No alpha, direct paint
        self.widget:paintTo(bb, x_pos, y_pos)
    end
end

function CustomPositionContainer:onCloseWidget()
    if self.compose_bb then
        self.compose_bb:free()
        self.compose_bb = nil
    end
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
