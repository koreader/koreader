local BasePowerD = {
    fl_min = 0,      -- min frontlight intensity
    fl_max = 10,     -- max frontlight intensity
    flIntensity = nil,   -- frontlight intensity
    battCapacity = nil,  -- battery capacity
    device = nil,    -- device object

    capacity_pulled_count = 0,
    capacity_cached_count = 10,
}

function BasePowerD:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    if o.init then o:init() end
    return o
end

function BasePowerD:init() end
function BasePowerD:toggleFrontlight() end
function BasePowerD:setIntensityHW() end
function BasePowerD:getCapacityHW() return "0" end
function BasePowerD:isChargingHW() end
function BasePowerD:suspendHW() end
function BasePowerD:wakeUpHW() end

function BasePowerD:read_int_file(file)
    local fd =  io.open(file, "r")
    if fd then
        local int = fd:read("*all"):match("%d+")
        fd:close()
        return int and tonumber(int) or 0
    else
        return 0
    end
end

function BasePowerD:read_str_file(file)
    local fd =  io.open(file, "r")
    if fd then
        local str = fd:read("*all")
        fd:close()
        return str
    else
        return ""
    end
end

function BasePowerD:normalizeIntensity(intensity)
    intensity = intensity < self.fl_min and self.fl_min or intensity
    return intensity > self.fl_max and self.fl_max or intensity
end

function BasePowerD:setIntensity(intensity)
    self.flIntensity = self:normalizeIntensity(intensity)
    self:setIntensityHW()
end

function BasePowerD:getCapacity()
    if self.capacity_pulled_count == self.capacity_cached_count then
        self.capacity_pulled_count = 0
        return self:getCapacityHW()
    else
        self.capacity_pulled_count = self.capacity_pulled_count + 1
        return self.battCapacity or self:getCapacityHW()
    end
end

function BasePowerD:refreshCapacity()
    -- We want our next getCapacity call to actually pull up to date info instead of a cached value ;)
    self.capacity_pulled_count = self.capacity_cached_count
end

function BasePowerD:isCharging()
    return self:isChargingHW()
end

function BasePowerD:suspend()
    return self:suspendHW()
end

function BasePowerD:wakeUp()
    return self:wakeUpHW()
end

return BasePowerD
