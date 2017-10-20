--[[--
Widget for displaying progress bar.

Configurable attributes:

 * width
 * height
 * margin_v  -- vertical margin for solid infill
 * margin_h  -- horizontal margin for solid infill
 * radius
 * bordersize
 * bordercolor
 * bgcolor
 * rectcolor  -- infill color
 * ticks (list)  -- default to nil, use this if you want to insert markers
 * tick_width
 * last  -- maximum tick, used with ticks

Example:

    local foo_bar = ProgressWidget:new{
        width = Screen:scaleBySize(400),
        height = Screen:scaleBySize(10),
        percentage = 50/100,
    }
    UIManager:show(foo_bar)

]]

local Blitbuffer = require("ffi/blitbuffer")
local Geom = require("ui/geometry")
local Widget = require("ui/widget/widget")
local Screen = require("device").screen

local ProgressWidget = Widget:new{
    width = nil,
    height = nil,
    margin_h = Screen:scaleBySize(3),
    margin_v = Screen:scaleBySize(1),
    radius = Screen:scaleBySize(2),
    bordersize = Screen:scaleBySize(1),
    bordercolor = Blitbuffer.COLOR_BLACK,
    bgcolor = Blitbuffer.COLOR_WHITE,
    rectcolor = Blitbuffer.gray(0.7),
    percentage = nil,
    ticks = nil,
    tick_width = Screen:scaleBySize(3),
    last = nil,
}

function ProgressWidget:getSize()
    return { w = self.width, h = self.height }
end

function ProgressWidget:paintTo(bb, x, y)
    local my_size = self:getSize()
    self.dimen = Geom:new{
        x = x, y = y,
        w = my_size.w,
        h = my_size.h
    }
    if self.dimen.w == 0 or self.dimen.h == 0 then return end

    -- fill background
    bb:paintRoundedRect(x, y, my_size.w, my_size.h, self.bgcolor, self.radius)
    -- paint border
    bb:paintBorder(x, y,
                   my_size.w, my_size.h,
                   self.bordersize, self.bordercolor, self.radius)
    -- paint percentage infill
    bb:paintRect(x+self.margin_h, math.ceil(y+self.margin_v+self.bordersize),
                 math.ceil((my_size.w-2*self.margin_h)*self.percentage),
                 my_size.h-2*(self.margin_v+self.bordersize), self.rectcolor)
    if self.ticks and self.last then
        local bar_width = (my_size.w-2*self.margin_h)
        local y_pos = y + self.margin_v + self.bordersize
        local bar_height = my_size.h-2*(self.margin_v+self.bordersize)
        for i=1, #self.ticks do
            bb:paintRect(
                x + bar_width*(self.ticks[i]/self.last) + self.margin_h,
                y_pos,
                self.tick_width,
                bar_height,
                self.bordercolor)
        end
    end
end

function ProgressWidget:setPercentage(percentage)
    self.percentage = percentage
end

return ProgressWidget
