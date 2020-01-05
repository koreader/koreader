--[[--
This is a generic Widget interface, which is the base class for all other widgets.

Widgets can be queried about their size and can be painted on screen.
that's it for now. Probably we need something more elaborate
later.

If the table that was given to us as parameter has an "init"
method, it will be called. use this to set _instance_ variables
rather than class variables.
]]

local EventListener = require("ui/widget/eventlistener")

--- Widget base class
-- @table Widget
local Widget = EventListener:new()

--[[--
Use this method to define a subclass widget class that's inherited from a
base class widget. It only setups the metabale (or prototype chain) and will
not initiate a real instance, i.e. call self:init().

@tparam Widget baseclass
@treturn Widget
]]
function Widget:extend(baseclass)
    local o = baseclass or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

--[[--
Use this method to initiatie a instance of a class, don't use it for class
definition because it also calls self:init().

@tparam Widget o
@treturn Widget
]]
function Widget:new(o)
    o = self:extend(o)
    -- Both o._init and o.init are called on object creation. But o._init is
    -- used for base widget initialization (basic component used to build other
    -- widgets). While o.init is for higher level widgets, for example Menu
    -- Widget
    if o._init then o:_init() end
    if o.init then o:init() end
    return o
end

--[[
FIXME: enable this doc section when we verified all self.dimen is a Geom so we
can return self.dime:copy().

Return size of the widget.

@treturn ui.geometry.Geom
--]]
function Widget:getSize()
    return self.dimen
end

--[[--
Paint widget to a BlitBuffer.

@tparam BlitBuffer bb BlitBuffer to paint to. If it's the screen BlitBuffer, then
widget will show up on screen refresh.
@int x x offset within the BlitBuffer
@int y y offset within the BlitBuffer
]]
function Widget:paintTo(bb, x, y)
end

return Widget
