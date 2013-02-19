--[[
Simple math helper function
]]--

function math.roundAwayFromZero(num)
	if num > 0 then
		return math.ceil(num)
	else
		return math.floor(num)
	end
end

function math.round(num)
	return math.floor(num + 0.5)
end

function math.oddEven(number)
	if number % 2 == 1 then
		return "odd"
	else
		return "even"
	end
end


