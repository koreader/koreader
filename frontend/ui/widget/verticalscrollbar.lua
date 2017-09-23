local Blitbuffer = require("ffi/blitbuffer")
local Geom = require("ui/geometry")
local Widget = require("ui/widget/widget")
local Screen = require("device").screen

local VerticalScrollBar = Widget:new{
    enable = true,
    low = 0,
    high = 1,
    width = Screen:scaleBySize(6),
    height = Screen:scaleBySize(50),
    bordersize = Screen:scaleBySize(1),
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
