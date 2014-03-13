local Widget = require("ui/widget/widget")
local Geom = require("ui/geometry")

local VerticalScrollBar = Widget:new{
    enable = true,
    low = 0,
    high = 1,
    
    width = 6,
    height = 50,
    bordersize = 1,
    bordercolor = 15,
    radius = 0,
    rectcolor = 15,
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
    bb:paintRect(x + self.bordersize, y + self.bordersize + self.low*self.height,
                self.width - 2*self.bordersize,
                self.height * (self.high - self.low), self.rectcolor)
end

return VerticalScrollBar
