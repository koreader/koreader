local Widget = require("ui/widget/widget")
local Geom = require("ui/geometry")

--[[
ProgressWidget shows a progress bar
--]]
local ProgressWidget = Widget:new{
    width = nil,
    height = nil,
    margin_h = 3,
    margin_v = 1,
    radius = 2,
    bordersize = 1,
    toc_marker_width = DMINIBAR_TOC_MARKER_WIDTH,
    bordercolor = 15,
    bgcolor = 0,
    rectcolor = 10,
    percentage = nil,
    TOC = {},
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
    bb:paintRoundedRect(x, y, my_size.w, my_size.h, self.bgcolor, self.radius)
    bb:paintBorder(x, y, my_size.w, my_size.h,
                    self.bordersize, self.bordercolor, self.radius)
    bb:paintRect(x+self.margin_h, y+self.margin_v+self.bordersize,
                (my_size.w-2*self.margin_h)*self.percentage,
                (my_size.h-2*(self.margin_v+self.bordersize)), self.rectcolor)
    if DMINIBAR_PROGRESS_MARKER then
        if #self.TOC > 0 then
            for i=1, #self.TOC do
                v = self.TOC[i]
                bb:paintRect(x+(my_size.w-2*self.margin_h)*(v.page/self.last), y+self.margin_v+self.bordersize,
                    self.toc_marker_width,(my_size.h-2*(self.margin_v+self.bordersize)), self.bordercolor)
            end
        end
    end
end

function ProgressWidget:setPercentage(percentage)
    self.percentage = percentage
end

return ProgressWidget
