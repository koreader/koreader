local util = require("ffi/util")

local TimeVal = {
    sec = 0,
    usec = 0,
}

function TimeVal:new(o)
    local o = o or {}
    if o.sec == nil then
        o.sec = 0
    end
    if o.usec == nil then
        o.usec = 0
    elseif o.usec > 1000000 then
        o.sec = o.sec + math.floor(o.usec/1000000)
        o.usec = o.usec % 1000000
    end
    setmetatable(o, self)
    self.__index = self
    return o
end


function TimeVal:__lt(time_b)
    if self.sec < time_b.sec then
        return true
    elseif self.sec > time_b.sec then
        return false
    else
        -- self.sec == time_b.sec
        if self.usec < time_b.usec then
            return true
        else
            return false
        end
    end
end

function TimeVal:__le(time_b)
    if self.sec < time_b.sec then
        return true
    elseif self.sec > time_b.sec then
        return false
    else
        -- self.sec == time_b.sec
        if self.usec > time_b.usec then
            return false
        else
            return true
        end
    end
end

function TimeVal:__eq(time_b)
    if self.sec == time_b.sec and self.usec == time_b.usec then
        return true
    else
        return false
    end
end

function TimeVal:__sub(time_b)
    local diff = TimeVal:new{}

    diff.sec = self.sec - time_b.sec
    diff.usec = self.usec - time_b.usec

    if diff.sec < 0 and diff.usec > 0 then
        diff.sec = diff.sec + 1
        diff.usec = diff.usec - 1000000
    elseif diff.sec > 0 and diff.usec < 0 then
        diff.sec = diff.sec - 1
        diff.usec = diff.usec + 1000000
    end

    return diff
end

function TimeVal:__add(time_b)
    local sum = TimeVal:new{}

    sum.sec = self.sec + time_b.sec
    sum.usec = self.usec + time_b.usec
    if sum.usec > 1000000 then
        sum.usec = sum.usec - 1000000
        sum.sec = sum.sec + 1
    end

    if sum.sec < 0 and sum.usec > 0 then
        sum.sec = sum.sec + 1
        sum.usec = sum.usec - 1000000
    elseif sum.sec > 0 and sum.usec < 0 then
        sum.sec = sum.sec - 1
        sum.usec = sum.usec + 1000000
    end

    return sum
end

function TimeVal:now()
    local sec, usec = util.gettime()
    return TimeVal:new{sec = sec, usec = usec}
end

return TimeVal
