--- A set of functions to extend math.random and math.randomseed.

local bit = require("bit")
local random = {}

--- Uses current time as seed to randomize.
function random.seed()
    math.randomseed(os.time())
end

random.seed()

--- Returns a UUID (v4, random).
function random.uuid(with_dash)
    local array = {}
    for i = 1, 16 do
        table.insert(array, math.random(256) - 1)
    end
    -- The 13th character should be 4.
    array[7] = bit.band(array[7], 79)
    array[7] = bit.bor(array[7], 64)
    -- The 17th character should be 8 / 9 / a / b.
    array[9] = bit.band(array[9], 191)
    array[9] = bit.bor(array[9], 128)
    if with_dash then
        return string.format("%02X%02X%02X%02X-%02X%02X-%02X%02X-%02X%02X-%02X%02X%02X%02X%02X%02X",
                             unpack(array))
    else
        return string.format("%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X",
                             unpack(array))
    end
end

return random
