local TimeVal = require("ui/timeval")

local GestureRange = {
    -- gesture matching type
    ges = nil,
    -- spatial range limits the gesture emitting position
    range = nil,
    -- temproal range limits the gesture emitting rate
    rate = nil,
    -- scale limits of this gesture
    scale = nil,
}

function GestureRange:new(o)
    local o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function GestureRange:match(gs)
    if gs.ges ~= self.ges then
        return false
    end
    if self.range then
        -- sometimes widget dimenension is not available when creating a gesturerage
        -- for some action, now we accept a range function that will be later called
        -- and the result of which will be used to check gesture match
        -- e.g. range = function() return self.dimen end
        -- for inputcontainer given that the x and y field of `self.dimen` is only
        -- filled when the inputcontainer is painted into blitbuffer
        local range = nil
        if type(self.range) == "function" then
            range = self.range()
        else
            range = self.range
        end
        if not range:contains(gs.pos) then
            return false
        end
    end
    if self.rate then
        -- This filed restraints the upper limit rate(matches per second).
        -- It's most useful for e-ink devices with less powerfull CPUs and
        -- screens that cannot handle gesture events that otherwise will be
        -- generated
        local last_time = self.last_time or TimeVal:new{}
        if gs.time - last_time > TimeVal:new{usec = 1000000 / self.rate} then
            self.last_time = gs.time
        else
            return false
        end
    end
    if self.scale then
        local scale = gs.distance or gs.span
        if self.scale[1] > scale or self.scale[2] < scale then
            return false
        end
    end
    if self.direction then
        if self.direction ~= gs.direction then
            return false
        end
    end
    return true
end

return GestureRange
