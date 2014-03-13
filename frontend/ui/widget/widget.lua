local EventListener = require("ui/widget/eventlistener")

--[[
This is a generic Widget interface

widgets can be queried about their size and can be paint.
that's it for now. Probably we need something more elaborate
later.

if the table that was given to us as parameter has an "init"
method, it will be called. use this to set _instance_ variables
rather than class variables.
--]]
local Widget = EventListener:new()

--[[
Use this method to define a class that's inherited from current class.
It only setup the metabale (or prototype chain) and will not initiatie
a real instance, i.e. call self:init()
--]]
function Widget:extend(o)
    local o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

--[[
Use this method to initiatie a instance of a class, don't use it for class
definition.
--]]
function Widget:new(o)
    o = self:extend(o)
    -- Both o._init and o.init are called on object create. But o._init is used
    -- for base widget initialization (basic component used to build other
    -- widgets). While o.init is for higher level widgets, for example Menu
    -- Widget
    if o._init then o:_init() end
    if o.init then o:init() end
    return o
end

function Widget:getSize()
    return self.dimen
end

function Widget:paintTo(bb, x, y)
end

return Widget
