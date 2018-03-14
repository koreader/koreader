--[[--
An UnderlineContainer is a WidgetContainer that is able to paint
a line under its child node.
--]]


local Blitbuffer = require("ffi/blitbuffer")
local Geom = require("ui/geometry")
local Size = require("ui/size")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local UnderlineContainer = WidgetContainer:new{
    linesize = Size.line.thick,
    padding = Size.padding.tiny,
    -- TODO: shouldn't this default to black instead?
    color = Blitbuffer.COLOR_WHITE,
    vertical_align = "top",
}

function UnderlineContainer:getSize()
    local contentSize = self[1]:getSize()
    return Geom:new{
        w = contentSize.w,
        h = contentSize.h + self.linesize + 2*self.padding
    }
end

function UnderlineContainer:paintTo(bb, x, y)
    local container_size = self:getSize()
    self.dimen = Geom:new{
        x = x, y = y,
        w = container_size.w,
        h = container_size.h
    }
    local content_size = self[1]:getSize()
    local p_y = y
    if self.vertical_align == "center" then
        p_y = math.floor((container_size.h - content_size.h) / 2) + y
    elseif self.vertical_align == "bottom" then
        p_y = (container_size.h - content_size.h) + y
    end
    self[1]:paintTo(bb, x, p_y)
    bb:paintRect(x, y + container_size.h - self.linesize,
        container_size.w, self.linesize, self.color)
end

return UnderlineContainer
