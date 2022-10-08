--[[--
Simple math helper functions
]]

local bit = require("bit")
local dbg = require("dbg")

local Math = {}

local band = bit.band

--[[--
Rounds a percentage.

@tparam float percent
@treturn int rounded percentage
]]
function Math.roundPercent(percent)
    return math.floor(percent * 10000) / 10000
end

--[[--
Rounds away from zero.

@tparam float num
@treturn int ceiled above 0, floored under 0
]]
function Math.roundAwayFromZero(num)
    if num > 0 then
        return math.ceil(num)
    else
        return math.floor(num)
    end
end

--[[--
Rounds a number.
No support for decimal points.

@tparam float num
@treturn int rounded number
]]
function Math.round(num)
    return math.floor(num + 0.5)
end

--[[--
Determines if a number is odd or even.

@int number
@treturn string "odd" or "even"
]]
function Math.oddEven(number)
    if band(number, 1) == 1 then
        return "odd"
    else
        return "even"
    end
end

local function tmin_max(tab, func, op)
    if #tab == 0 then return nil, nil end
    local index, value = 1, tab[1]
    for i = 2, #tab do
        if func then
            if func(value, tab[i]) then
                index, value = i, tab[i]
            end
        elseif op == "min" then
            if value > tab[i] then
                index, value = i, tab[i]
            end
        elseif op == "max" then
               if value < tab[i] then
                index, value = i, tab[i]
            end
        end
    end
    return index, value
end

--[[--
Returns the minimum element of a table.
The optional argument func specifies a one-argument ordering function.

@tparam table tab
@tparam func func
@treturn dynamic minimum element of a table
]]
function Math.tmin(tab, func)
    return tmin_max(tab, func, "min")
end

--[[--
Returns the maximum element of a table.
The optional argument func specifies a one-argument ordering function.

@tparam table tab
@tparam func func
@treturn dynamic maximum element of a table
]]
function Math.tmax(tab, func)
    return tmin_max(tab, func, "max")
end

--[[--
Restricts a value within an interval.

@number value
@number min
@number max
@treturn number value clamped to the interval [min,max]
]]
function Math.clamp(value, min, max)
    if value <= min then
        return min
    elseif value >= max then
        return max
    end
    return value
end
dbg:guard(Math, "minmax",
    function(value, min, max)
        assert(min ~= nil and max ~= nil, "Math.clamp: min " .. min .. " and max " .. nil .. " must not be nil")
        assert(min < max, "Math.clamp: min .. " .. min .. " must be less than max " .. max)
    end)

return Math
