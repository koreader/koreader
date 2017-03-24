local logger = require("logger")

local BasePowerD = {
    fl_min = 0,                       -- min frontlight intensity
    fl_max = 10,                      -- max frontlight intensity
    fl_intensity = nil,               -- frontlight intensity
    battCapacity = 0,                 -- battery capacity
    device = nil,                     -- device object

    last_capacity_pull_time = 0,      -- timestamp of last pull
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
function BasePowerD:getCapacityHW() return 0 end
function BasePowerD:isChargingHW() return false end
-- Anything needs to be done before do a real hardware suspend. Such as turn off
-- front light.
function BasePowerD:beforeSuspend() end
-- Anything needs to be done after do a real hardware resume. Such as resume
-- front light state.
function BasePowerD:afterResume() end

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
    if intensity == self.fl_intensity then return end
    self.fl_intensity = self:normalizeIntensity(intensity)
    logger.dbg("set light intensity", self.fl_intensity)
    self:setIntensityHW()
end

function BasePowerD:getCapacity()
    if os.time() - self.last_capacity_pull_time >= 60 then
        self.battCapacity = self:getCapacityHW()
        self.last_capacity_pull_time = os.time()
    end
    return self.battCapacity
end

function BasePowerD:refreshCapacity()
    -- We want our next getCapacity call to actually pull up to date info
    -- instead of a cached value ;)
    self.last_capacity_pull_time = 0
end

function BasePowerD:isCharging()
    return self:isChargingHW()
end

return BasePowerD
