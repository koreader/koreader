--[[
The EventListener is an interface that handles events

EventListeners have a rudimentary event handler/dispatcher that
will call a method "onEventName" for an event with name
"EventName"
--]]
local EventListener = {}

function EventListener:new(o)
    local o = o or {}
    setmetatable(o, self)
    self.__index = self
    if o.init then o:init() end
    return o
end

function EventListener:handleEvent(event)
    if self[event.handler] then
        return self[event.handler](self, unpack(event.args))
    end
end

return EventListener
