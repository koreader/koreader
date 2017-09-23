--[[--
A FrameContainer is some graphics content (1 widget) that is surrounded by a
frame

Example:

    local frame
    frame = FrameContainer:new{
        radius = Screen:scaleBySize(8),
        bordersize = Screen:scaleBySize(3),
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            -- etc
        }
    }

--]]

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Geom = require("ui/geometry")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Screen = Device.screen

local FrameContainer = WidgetContainer:new{
    background = nil,
    color = Blitbuffer.COLOR_BLACK,
    margin = 0,
    radius = 0,
    bordersize = Screen:scaleBySize(2),
    padding = Screen:scaleBySize(5),
    width = nil,
    height = nil,
    invert = false,
}

function FrameContainer:getSize()
    local content_size = self[1]:getSize()
    return Geom:new{
        w = content_size.w + ( self.margin + self.bordersize + self.padding ) * 2,
        h = content_size.h + ( self.margin + self.bordersize + self.padding ) * 2
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

    --@TODO get rid of margin here?  13.03 2013 (houqp)
    if self.background then
        bb:paintRoundedRect(x, y,
                            container_width, container_height,
                            self.background, self.radius)
    end
    if self.bordersize > 0 then
        bb:paintBorder(x + self.margin, y + self.margin,
            container_width - self.margin * 2,
            container_height - self.margin * 2,
            self.bordersize, self.color, self.radius)
    end
    if self[1] then
        self[1]:paintTo(bb,
            x + self.margin + self.bordersize + self.padding,
            y + self.margin + self.bordersize + self.padding)
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
