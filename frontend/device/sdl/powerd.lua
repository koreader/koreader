local BasePowerD = require("device/generic/powerd")
local SDL = require("ffi/SDL2_0")

local SDLPowerD = BasePowerD:new{
    -- these values are just used on the emulator
    hw_intensity = 50,
    fl_min = 0,
    fl_max = 100,
    fl_warmth = 50,
    fl_warmth_min = 0,
    fl_warmth_max = 100,
}

function SDLPowerD:frontlightIntensityHW()
    return self.hw_intensity
end

function SDLPowerD:setIntensityHW(intensity)
    require("logger").info("set brightness to", intensity)
    self.hw_intensity = intensity or self.hw_intensity
end


function SDLPowerD:setWarmth(level)
    require("logger").info("set warmth to", level)
    self.fl_warmth = level or self.fl_warmth
end

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
