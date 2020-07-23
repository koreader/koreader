local BasePowerD = require("device/generic/powerd")
local SDL = require("ffi/SDL2_0")

local SDLPowerD = BasePowerD:new{}

function SDLPowerD:getCapacityHW()
    local _, _, _, percent = SDL.getPowerInfo()
    -- -1 looks a bit odd compared to 0
    if percent == -1 then return 0 end
    return percent
end

function SDLPowerD:isChargingHW()
    local ok, charging = SDL.getPowerInfo()
    if ok then return charging end
    return false
end

return SDLPowerD
