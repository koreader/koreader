--[[
Simple math helper function
]]--

local Math = {}

function Math.roundAwayFromZero(num)
    if num > 0 then
        return math.ceil(num)
    else
        return math.floor(num)
    end
end

function Math.round(num)
    return math.floor(num + 0.5)
end

function Math.oddEven(number)
    if number % 2 == 1 then
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

--[[
Return the minimum element of a table.
The optional argument func specifies a one-argument ordering function.
]]--
function Math.tmin(tab, func)
    return tmin_max(tab, func, "min")
end

--[[
Return the maximum element of a table.
The optional argument func specifies a one-argument ordering function.
]]--
function Math.tmax(tab, func)
    return tmin_max(tab, func, "max")
end

return Math
