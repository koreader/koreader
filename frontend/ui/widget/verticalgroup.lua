local WidgetContainer = require("ui/widget/container/widgetcontainer")

--[[
A Layout widget that puts objects under each other
--]]
local VerticalGroup = WidgetContainer:new{
    align = "center",
    _size = nil,
    _offsets = {}
}

function VerticalGroup:getSize()
    if not self._size then
        self._size = { w = 0, h = 0 }
        self._offsets = { }
        for i, widget in ipairs(self) do
            local w_size = widget:getSize()
            self._offsets[i] = {
                x = w_size.w,
                y = self._size.h,
            }
            self._size.h = self._size.h + w_size.h
            if w_size.w > self._size.w then
                self._size.w = w_size.w
            end
        end
    end
    return self._size
end

function VerticalGroup:paintTo(bb, x, y)
    local size = self:getSize()

    for i, widget in ipairs(self) do
        if self.align == "center" then
            widget:paintTo(bb,
                x + math.floor((size.w - self._offsets[i].x) / 2),
                y + self._offsets[i].y)
        elseif self.align == "left" then
            widget:paintTo(bb, x, y + self._offsets[i].y)
        elseif self.align == "right" then
            widget:paintTo(bb,
                x + size.w - self._offsets[i].x,
                y + self._offsets[i].y)
        end
    end
end

function VerticalGroup:clear()
    self:free()
    WidgetContainer.clear(self)
end

function VerticalGroup:resetLayout()
    self._size = nil
    self._offsets = {}
end

function VerticalGroup:free()
    self:resetLayout()
    WidgetContainer.free(self)
end

return VerticalGroup
