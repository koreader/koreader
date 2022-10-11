--[[--
Events are messages that are passed through the widget tree.

Events need a "name" attribute as minimal data.

To see how event propagation works and how to make
widgets event-aware see the implementation in @{ui.widget.container.widgetcontainer}.

A detailed guide to events can be found in @{Events.md|the event programmer's guide}.
]]

--[[--
@field handler name for the handler method: `"on"..Event.name`
@field args array of arguments for the event
@table Event
]]
local Event = {}

--[[--
Creates a new event.

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
        args = table.pack(...),
    }
    setmetatable(o, self)
    self.__index = self
    return o
end

return Event
