--[[
Events are messages that are passed through the widget tree

Events need a "name" attribute as minimal data.

In order to see how event propagation works and how to make
widgets event-aware see the implementation in WidgetContainer
below.
]]
local Event = {}

function Event:new(name, ...)
    local o = {
        handler = "on"..name,
        args = {...}
    }
    setmetatable(o, self)
    self.__index = self
    return o
end

return Event
