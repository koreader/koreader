local UIManager -- will be updated when available
local TimeVal = require("ui/timeval")
local logger = require("logger")
local BasePowerD = {
    fl_min = 0,                       -- min frontlight intensity
    fl_max = 10,                      -- max frontlight intensity
    fl_intensity = nil,               -- frontlight intensity
    batt_capacity = 0,                -- battery capacity
    aux_batt_capacity = 0,            -- auxiliary battery capacity
    device = nil,                     -- device object

    last_capacity_pull_time = TimeVal:new{ sec = -61, usec = 0},      -- timestamp of last pull
    last_aux_capacity_pull_time = TimeVal:new{ sec = -61, usec = 0},  -- timestamp of last pull

    is_fl_on = false,                 -- whether the frontlight is on
}

function BasePowerD:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    assert(o.fl_min < o.fl_max)
    if o.init then o:init() end
    if o.device and o.device:hasFrontlight() then
        o.fl_intensity = o:frontlightIntensityHW()
        o:_decideFrontlightState()
    end
    return o
end

function BasePowerD:readyUI()
    UIManager = require("ui/uimanager")
end

function BasePowerD:init() end
function BasePowerD:setIntensityHW(intensity) end
function BasePowerD:getCapacityHW() return 0 end
function BasePowerD:getAuxCapacityHW() return 0 end
function BasePowerD:isAuxBatteryConnectedHW() return false end
function BasePowerD:getDismissBatteryStatus() return self.battery_warning end
function BasePowerD:setDismissBatteryStatus(status) self.battery_warning = status end
function BasePowerD:isChargingHW() return false end
function BasePowerD:isAuxChargingHW() return false end
function BasePowerD:frontlightIntensityHW() return 0 end
function BasePowerD:isFrontlightOnHW() return self.fl_intensity > self.fl_min end
function BasePowerD:turnOffFrontlightHW() self:setIntensityHW(self.fl_min) end
function BasePowerD:turnOnFrontlightHW() self:setIntensityHW(self.fl_intensity) end --- @fixme: what if fl_intensity == fl_min (c.f., kindle)?
-- Anything needs to be done before do a real hardware suspend. Such as turn off
-- front light.
function BasePowerD:beforeSuspend() end
-- Anything needs to be done after do a real hardware resume. Such as resume
-- front light state.
function BasePowerD:afterResume() end

function BasePowerD:isFrontlightOn()
    assert(self ~= nil)
    return self.is_fl_on
end

function BasePowerD:_decideFrontlightState()
    assert(self ~= nil)
    assert(self.device:hasFrontlight())
    self.is_fl_on = self:isFrontlightOnHW()
end

function BasePowerD:isFrontlightOff()
    return not self:isFrontlightOn()
end

function BasePowerD:frontlightIntensity()
    assert(self ~= nil)
    if not self.device:hasFrontlight() then return 0 end
    if self:isFrontlightOff() then return 0 end
    return self.fl_intensity
end

function BasePowerD:toggleFrontlight()
    assert(self ~= nil)
    if not self.device:hasFrontlight() then return false end
    if self:isFrontlightOn() then
        return self:turnOffFrontlight()
    else
        return self:turnOnFrontlight()
    end
end

function BasePowerD:turnOffFrontlight()
    assert(self ~= nil)
    if not self.device:hasFrontlight() then return end
    if self:isFrontlightOff() then return false end
    self:turnOffFrontlightHW()
    self.is_fl_on = false
    self:stateChanged()
    return true
end

function BasePowerD:turnOnFrontlight()
    assert(self ~= nil)
    if not self.device:hasFrontlight() then return end
    if self:isFrontlightOn() then return false end
    if self.fl_intensity == self.fl_min then return false end  --- @fixme what the hell?
    self:turnOnFrontlightHW()
    self.is_fl_on = true
    self:stateChanged()
    return true
end

function BasePowerD:read_int_file(file)
    local fd = io.open(file, "r")
    if fd then
        local int = fd:read("*number")
        fd:close()
        return int or 0
    else
        return 0
    end
end

function BasePowerD:unchecked_read_int_file(file)
    local fd = io.open(file, "r")
    if fd then
        local int = fd:read("*number")
        fd:close()
        return int
    else
        return
    end
end

function BasePowerD:read_str_file(file)
    local fd = io.open(file, "r")
    if fd then
        local str = fd:read("*line")
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
    if not self.device:hasFrontlight() then return false end
    if intensity == self:frontlightIntensity() then return false end
    self.fl_intensity = self:normalizeIntensity(intensity)
    self:_decideFrontlightState()
    logger.dbg("set light intensity", self.fl_intensity)
    self:setIntensityHW(self.fl_intensity)
    self:stateChanged()
    return true
end

function BasePowerD:getCapacity()
    -- BasePowerD is loaded before UIManager.
    -- Nothing *currently* calls this before UIManager is actually loaded, but future-proof this anyway.
    local now_ts
    if UIManager then
        now_ts = UIManager:getTime()
    else
        now_ts = TimeVal:now()
    end

    if (now_ts - self.last_capacity_pull_time):tonumber() >= 60 then
        self.batt_capacity = self:getCapacityHW()
        self.last_capacity_pull_time = now_ts
    end
    return self.batt_capacity
end

function BasePowerD:isCharging()
    return self:isChargingHW()
end

function BasePowerD:getAuxCapacity()
    local now_ts
    if UIManager then
        now_ts = UIManager:getTime()
    else
        now_ts = TimeVal:now()
    end

    if (now_ts - self.last_aux_capacity_pull_time):tonumber() >= 60 then
        local aux_batt_capa = self:getAuxCapacityHW()
        -- If the read failed, don't update our cache, and retry next time.
        if aux_batt_capa then
            self.aux_batt_capacity = aux_batt_capa
            self.last_aux_capacity_pull_time = now_ts
        end
    end
    return self.aux_batt_capacity
end

function BasePowerD:invalidateCapacityCache()
    self.last_capacity_pull_time = TimeVal:new{ sec = -61, usec = 0}
    self.last_aux_capacity_pull_time = TimeVal:new{ sec = -61, usec = 0}
end

function BasePowerD:isAuxCharging()
    return self:isAuxChargingHW()
end

function BasePowerD:isAuxBatteryConnected()
    return self:isAuxBatteryConnectedHW()
end

function BasePowerD:stateChanged()
    -- BasePowerD is loaded before UIManager. So we cannot broadcast events before UIManager has been loaded.
    if UIManager then
        local Event = require("ui/event")
        UIManager:broadcastEvent(Event:new("FrontlightStateChanged"))
    end
end

-- Silly helper to avoid code duplication ;).
function BasePowerD:getBatterySymbol(is_charging, capacity)
    if is_charging then
        return ""
    else
        if capacity >= 100 then
            return ""
        elseif capacity >= 90 then
            return ""
        elseif capacity >= 80 then
            return ""
        elseif capacity >= 70 then
            return ""
        elseif capacity >= 60 then
            return ""
        elseif capacity >= 50 then
            return ""
        elseif capacity >= 40 then
            return ""
        elseif capacity >= 30 then
            return ""
        elseif capacity >= 20 then
            return ""
        elseif capacity >= 10 then
            return ""
        else
            return ""
        end
    end
end

return BasePowerD
