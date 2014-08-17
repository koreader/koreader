local Geom = require("ui/geometry")
local Widget = require("ui/widget/widget")

--[[
WidgetContainer is a container for another Widget
--]]
local WidgetContainer = Widget:new()

function WidgetContainer:init()
    if not self.dimen then
        self.dimen = Geom:new{}
    end
    if not self.dimen.w then
        self.dimen.w = self[1].getSize().w
    end
    if not self.dimen.h then
        self.dimen.h = self[1].getSize().h
    end
end

function WidgetContainer:getSize()
    if self.dimen then
        -- fixed size
        return self.dimen
    elseif self[1] then
        -- return size of first child widget
        return self[1]:getSize()
    else
        return Geom:new{ w = 0, h = 0 }
    end
end

--[[
delete all child widgets
--]]
function WidgetContainer:clear()
    while table.remove(self) do end
end

function WidgetContainer:paintTo(bb, x, y)
    -- default to pass request to first child widget
    if self[1] then
        x = x + (self.dimen.x or 0)
        y = y + (self.dimen.y or 0)
        if self.align == "top" then
            local contentSize = self[1]:getSize()
            self[1]:paintTo(bb,
                x + math.floor((self.dimen.w - contentSize.w)/2), y)
        elseif self.align == "bottom" then
            local contentSize = self[1]:getSize()
            self[1]:paintTo(bb,
                x + math.floor((self.dimen.w - contentSize.w)/2),
                y + (self.dimen.h - contentSize.h))
        elseif self.align == "center" then
            local contentSize = self[1]:getSize()
            self[1]:paintTo(bb,
                x + math.floor((self.dimen.w - contentSize.w)/2),
                y + math.floor((self.dimen.h - contentSize.h)/2))
        else
            return self[1]:paintTo(bb, x, y)
        end
    end
end

function WidgetContainer:propagateEvent(event)
    -- propagate to children
    for _, widget in ipairs(self) do
        if widget:handleEvent(event) then
            -- stop propagating when an event handler returns true
            return true
        end
    end
    return false
end

--[[
Containers will pass events to children or react on them themselves
--]]
function WidgetContainer:handleEvent(event)
    if not self:propagateEvent(event) then
        -- call our own standard event handler
        return Widget.handleEvent(self, event)
    else
        return true
    end
end

function WidgetContainer:free()
    for _, widget in ipairs(self) do
        if widget.free then widget:free() end
    end
end

return WidgetContainer
