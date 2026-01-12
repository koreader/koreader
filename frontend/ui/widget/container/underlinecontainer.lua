--[[--
An UnderlineContainer is a WidgetContainer that is able to paint
a line under its child node.
--]]


local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local Geom = require("ui/geometry")
local Size = require("ui/size")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local UnderlineContainer = WidgetContainer:extend{
    linesize = Size.line.thick,
    padding = Size.padding.tiny,
    -- We default to white to be invisible by default for FocusManager use-cases (only switching to black @ onFocus)
    color = Blitbuffer.COLOR_WHITE,
    vertical_align = "top",
    line_width = nil, -- (Don't use this, it's there because of the complex and ugly layout in TouchMenuItem)
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
    if not self.dimen then
        self.dimen = Geom:new{
            x = x, y = y,
            w = container_size.w,
            h = container_size.h
        }
    else
        self.dimen.x = x
        self.dimen.y = y
    end

    local line_width = self.line_width or self.dimen.w
    local line_x = x
    if BD.mirroredUILayout() then
        line_x = line_x + self.dimen.w - line_width
    end

    local content_size = self[1]:getSize()
    local p_y = y
    if self.vertical_align == "center" then
        p_y = math.floor((container_size.h - content_size.h) / 2) + y
    elseif self.vertical_align == "bottom" then
        p_y = (container_size.h - content_size.h) + y
    end
    self[1]:paintTo(bb, x, p_y)
    bb:paintRect(line_x, y + container_size.h - self.linesize,
        line_width, self.linesize, self.color)
end

return UnderlineContainer
