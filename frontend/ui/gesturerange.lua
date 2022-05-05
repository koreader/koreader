local time = require("ui/time")

local GestureRange = {
    -- gesture matching type
    ges = nil,
    -- spatial range, limits the gesture emitting position
    range = nil,
    -- temporal range, limits the gesture emitting rate
    rate = nil,
    -- scale limits of this gesture
    scale = nil,
}

function GestureRange:new(from_o)
    local o = from_o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function GestureRange:match(gs)
    if gs.ges ~= self.ges then
        return false
    end
    if self.range then
        -- Sometimes the widget's dimensions are not available when creating a GestureRange
        -- for some action, so we accept a range function that will only be called at match() time instead.
        -- e.g. range = function() return self.dimen end
        -- That's because most widgets' dimensions are only set at paintTo() time:
        -- e.g., with InputContainer, the x and y fields of `self.dimen`.
        local range
        if type(self.range) == "function" then
            range = self.range()
        else
            range = self.range
        end
        if not range or not range:contains(gs.pos) then
            return false
        end
    end

    if self.rate then
        -- This field sets up rate-limiting (in matches per second).
        -- It's mostly useful for e-Ink devices with less powerful CPUs
        -- and screens that cannot handle the amount of gesture events that would otherwise be generated.
        local last_time = self.last_time or 0
        if gs.time - last_time > time.s(1 / self.rate) then
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
