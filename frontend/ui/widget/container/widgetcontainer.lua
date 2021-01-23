--[[--
WidgetContainer is a container for one or multiple Widgets. It is the base
class for all the container widgets.

Child widgets are stored in WidgetContainer as conventional array items:

    WidgetContainer:new{
        ChildWidgetFoo:new{},
        ChildWidgetBar:new{},
        ...
    }

It handles event propagation and painting (with different alignments) for its children.
]]

local Geom = require("ui/geometry")
local Widget = require("ui/widget/widget")
local Device = require("device")

if Device.should_restrict_JIT then
    jit.off(true, true)
end

local WidgetContainer = Widget:new()

function WidgetContainer:init()
    if self.dimen then
        if self.initDimen then
            self:initDimen()
        else
            if not self.dimen.w then
                self.dimen.w = self[1]:getSize().w
            end
            if not self.dimen.h then
                self.dimen.h = self[1]:getSize().h
            end
        end
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

--[[--
Deletes all child widgets.
]]
function WidgetContainer:clear(skip_free)
    -- HorizontalGroup & VerticalGroup call us after already having called free,
    -- so allow skipping this one ;).
    if not skip_free then
        -- Make sure we free 'em before orphaning them...
        self:free()
    end

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

--[[--
WidgetContainer will pass event to its children by calling their handleEvent
methods. If no child consumes the event (by returning true), it will try
to react to the event by itself.

@tparam ui.event.Event event
@treturn bool true if event is consumed, otherwise false. A consumed event will
not be sent to other widgets.
]]
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
        if widget.free then
            --print("WidgetContainer: Calling free for widget", debug.getinfo(widget.free, "S").short_src, widget, "from", debug.getinfo(self.free, "S").short_src, self)
            widget:free()
        end
    end
end

return WidgetContainer
