--[[--
The EventListener is an interface that handles events. This is the base class
for @{ui.widget.widget}

EventListeners have a rudimentary event handler/dispatcher that
will call a method "onEventName" for an event with name
"EventName"
]]

local EventListener = {}
local DEBUG = require("dbg")

function EventListener:new(new_o)
    local o = new_o or {}
    setmetatable(o, self)
    self.__index = self
    if o.init then o:init() end
    return o
end

--[[--
Invoke handler method for an event.

Handler method name is determined by @{ui.event.Event}'s handler field.
By default, it's `"on"..Event.name`.

@tparam ui.event.Event event
@treturn bool return true if event is consumed successfully.
]]
function EventListener:handleEvent(event)
    if self[event.handler] then
        if self.id or self.name then
            DEBUG:v(self.id or self.name, "handling event", event)
        end
        return self[event.handler](self, unpack(event.args))
    end
end

return EventListener
