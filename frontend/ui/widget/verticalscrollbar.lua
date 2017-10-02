local Blitbuffer = require("ffi/blitbuffer")
local Geom = require("ui/geometry")
local Size = require("ui/size")
local Widget = require("ui/widget/widget")

local VerticalScrollBar = Widget:new{
    enable = true,
    low = 0,
    high = 1,
    width = Size.padding.default,
    height = Size.item.height_large,
    bordersize = Size.border.thin,
    bordercolor = Blitbuffer.COLOR_BLACK,
    radius = 0,
    rectcolor = Blitbuffer.COLOR_BLACK,
}

function VerticalScrollBar:getSize()
    return Geom:new{
        w = self.width,
        h = self.height
    }
end

function VerticalScrollBar:set(low, high)
    self.low = low > 0 and low or 0
    self.high = high < 1 and high or 1
end

function VerticalScrollBar:paintTo(bb, x, y)
    if not self.enable then return end
    bb:paintBorder(x, y, self.width, self.height,
                   self.bordersize, self.bordercolor, self.radius)
    bb:paintRect(x + self.bordersize, y + self.bordersize + self.low * self.height,
                 self.width - 2 * self.bordersize,
                 (self.height - 2 * self.bordersize) * (self.high - self.low), self.rectcolor)
end

return VerticalScrollBar
