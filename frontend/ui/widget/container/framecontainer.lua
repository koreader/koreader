--[[--
A FrameContainer is some graphics content (1 widget) that is surrounded by a
frame

Example:

    local frame
    frame = FrameContainer:new{
        radius = Size.radius.window,
        bordersize = Size.border.window,
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            -- etc
        }
    }

--]]

local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local Geom = require("ui/geometry")
local Size = require("ui/size")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local FrameContainer = WidgetContainer:new{
    background = nil,
    color = Blitbuffer.COLOR_BLACK,
    margin = 0,
    radius = 0,
    inner_bordersize = 0,
    bordersize = Size.border.window,
    padding = Size.padding.default,
    padding_top = nil,
    padding_right = nil,
    padding_bottom = nil,
    padding_left = nil,
    width = nil,
    height = nil,
    invert = false,
    allow_mirroring = true,
    _mirroredUI = BD.mirroredUILayout(),
}

function FrameContainer:getSize()
    local content_size = self[1]:getSize()
    self._padding_top = self.padding_top or self.padding
    self._padding_right = self.padding_right or self.padding
    self._padding_bottom = self.padding_bottom or self.padding
    self._padding_left = self.padding_left or self.padding
    if self._mirroredUI and self.allow_mirroring then
        self._padding_left, self._padding_right = self._padding_right, self._padding_left
    end
    return Geom:new{
        w = content_size.w + ( self.margin + self.bordersize ) * 2 + self._padding_left + self._padding_right,
        h = content_size.h + ( self.margin + self.bordersize ) * 2 + self._padding_top + self._padding_bottom
    }
end

function FrameContainer:paintTo(bb, x, y)
    local my_size = self:getSize()
    self.dimen = Geom:new{
        x = x, y = y,
        w = my_size.w,
        h = my_size.h
    }
    local container_width = self.width or my_size.w
    local container_height = self.height or my_size.h

    local shift_x = 0
    if self._mirroredUI and self.allow_mirroring then
        shift_x = container_width - my_size.w
    end

    --- @todo get rid of margin here?  13.03 2013 (houqp)
    if self.background then
        bb:paintRoundedRect(x, y,
                            container_width, container_height,
                            self.background, self.radius)
    end
    if self.inner_bordersize > 0 then
        --- @warning This doesn't actually support radius, it'll always be a square.
        bb:paintInnerBorder(x + self.margin, y + self.margin,
            container_width - self.margin * 2,
            container_height - self.margin * 2,
            self.inner_bordersize, self.color, self.radius)
    end
    if self.bordersize > 0 then
        bb:paintBorder(x + self.margin, y + self.margin,
            container_width - self.margin * 2,
            container_height - self.margin * 2,
            self.bordersize, self.color, self.radius)
    end
    if self[1] then
        self[1]:paintTo(bb,
            x + self.margin + self.bordersize + self._padding_left + shift_x,
            y + self.margin + self.bordersize + self._padding_top)
    end
    if self.invert then
        bb:invertRect(x + self.bordersize, y + self.bordersize,
            container_width - 2*self.bordersize,
            container_height - 2*self.bordersize)
    end
    if self.dim then
        bb:dimRect(x + self.bordersize, y + self.bordersize,
            container_width - 2*self.bordersize,
            container_height - 2*self.bordersize)
    end
end

return FrameContainer
