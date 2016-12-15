--[[--
Events are messages that are passed through the widget tree

Events need a "name" attribute as minimal data.

In order to see how event propagation works and how to make
widgets event-aware see the implementation in @{ui.widget.container.widgetcontainer}.
]]

--[[--
@field handler name for the handler method: `"on"..Event.name`
@field args array of arguments for the event
@table Event
]]
local Event = {}

--[[--
Create a new event.

@string name
@tparam[opt] ... arguments for the event
@treturn Event

@usage
local Event = require("ui/event")
Event:new("GotoPage", 1)
]]
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
