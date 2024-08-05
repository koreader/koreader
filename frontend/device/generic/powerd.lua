local Event = require("ui/event")
local Math = require("optmath")
local UIManager
local logger = require("logger")
local time = require("ui/time")
local BasePowerD = {
    fl_min = 0,                       -- min frontlight intensity
    fl_max = 10,                      -- max frontlight intensity
    fl_intensity = nil,               -- frontlight intensity
    fl_warmth_min = 0,                -- min warmth level
    fl_warmth_max = 100,              -- max warmth level
    fl_warmth = nil,                  -- warmth level
    batt_capacity = 0,                -- battery capacity
    aux_batt_capacity = 0,            -- auxiliary battery capacity
    device = nil,                     -- device object

    last_capacity_pull_time = time.s(-61),      -- timestamp of last pull
    last_aux_capacity_pull_time = time.s(-61),  -- timestamp of last pull

    is_fl_on = false,                 -- whether the frontlight is on
    fl_was_on = nil,                  -- whether the frontlight *was* on before suspend
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
        o:updateResumeFrontlightState()
    end
    --- @note: Post-init, as the min/max values may be computed at runtime on some platforms
    assert(o.fl_warmth_min < o.fl_warmth_max)
    -- For historical reasons, the *public* PowerD warmth API always expects warmth to be in the [0...100] range...
    self.warmth_scale = 100 / o.fl_warmth_max
    --- @note: Some platforms cannot actually read fl/warmth level from the HW,
    --         in which case the implementation should just return self.fl_warmth (c.f., kobo).
    if o.device and o.device:hasNaturalLight() then
        o.fl_warmth = o:frontlightWarmthHW()
    end
    return o
end

function BasePowerD:init() end
--- @note: This should *always* call self:_decideFrontlightState() in its coda (unless you have a custom isFrontlightOn implementation)!
function BasePowerD:setIntensityHW(intensity)
    self:_decideFrontlightState()
end
--- @note: Unlike the "public" setWarmth, this one takes a value in the *native* scale!
function BasePowerD:setWarmthHW(warmth) end
function BasePowerD:getCapacityHW() return 0 end
function BasePowerD:getAuxCapacityHW() return 0 end
function BasePowerD:isAuxBatteryConnectedHW() return false end
function BasePowerD:getDismissBatteryStatus() return self.battery_warning end
function BasePowerD:setDismissBatteryStatus(status) self.battery_warning = status end
--- @note: Should ideally return true as long as the device is plugged in, even once the battery is full...
function BasePowerD:isChargingHW() return false end
--- @note: ...at which point this should start returning true (i.e., plugged in & fully charged).
function BasePowerD:isChargedHW() return false end
function BasePowerD:isAuxChargingHW() return false end
function BasePowerD:isAuxChargedHW() return false end
function BasePowerD:frontlightIntensityHW() return 0 end
function BasePowerD:isFrontlightOnHW() return self.fl_intensity > self.fl_min end
--- @note: done_callback is used to display Notifications,
---        some implementations *may* need to handle it themselves because of timing constraints,
---        in which case they should return *true* here, so that the public API knows not to consume the callback early.
function BasePowerD:turnOffFrontlightHW(done_callback)
    self:setIntensityHW(self.fl_min)

    -- Nothing fancy required, so we leave done_callback handling to the public API
    return false
end
function BasePowerD:turnOnFrontlightHW(done_callback)
    --- @fixme: what if fl_intensity == fl_min (c.f., kindle)?
    self:setIntensityHW(self.fl_intensity)

    return false
end
function BasePowerD:frontlightWarmthHW() return 0 end
-- Anything that needs to be done before doing a real hardware suspend.
-- (Such as turning the front light off).
-- Do *not* omit calling Device's _beforeSuspend method! This default implementation passes `false` so as *not* to disable input events during PM.
function BasePowerD:beforeSuspend() self.device:_beforeSuspend(false) end
-- Anything that needs to be done after doing a real hardware resume.
-- (Such as restoring front light state).
-- Do *not* omit calling Device's _afterResume method!
function BasePowerD:afterResume()
    -- MONOTONIC doesn't tick during suspend,
    -- invalidate the last battery capacity pull time so that we get up to date data immediately.
    self:invalidateCapacityCache()

    self.device:_afterResume(false)
end

-- Update our UIManager reference once it's ready
function BasePowerD:UIManagerReady(uimgr)
    -- Our own ref
    UIManager = uimgr
    -- Let implementations do the same thing, too
    self:UIManagerReadyHW(uimgr)
end
-- Ditto, but for implementations
function BasePowerD:UIManagerReadyHW(uimgr) end

function BasePowerD:isFrontlightOn()
    return self.is_fl_on
end

function BasePowerD:_decideFrontlightState()
    assert(self.device:hasFrontlight())
    self.is_fl_on = self:isFrontlightOnHW()
end

-- Separate from _decideFrontlightState, as this is only called by *interactive* codepaths
function BasePowerD:updateResumeFrontlightState()
    self.fl_was_on = self:isFrontlightOn()
end

function BasePowerD:isFrontlightOff()
    return not self:isFrontlightOn()
end

function BasePowerD:frontlightIntensity()
    if not self.device:hasFrontlight() then return 0 end
    if self:isFrontlightOff() then return 0 end
    --- @note: We assume that nothing other than us will set the frontlight level,
    ---        so we only actually query the HW during initialization.
    ---        (Also, some platforms do not actually have any way of querying the HW).
    return self.fl_intensity
end

function BasePowerD:toggleFrontlight(done_callback)
    if not self.device:hasFrontlight() then return false end
    if self:isFrontlightOn() then
        return self:turnOffFrontlight(done_callback)
    else
        return self:turnOnFrontlight(done_callback)
    end
end

function BasePowerD:turnOffFrontlight(done_callback)
    if not self.device:hasFrontlight() then return end
    if self:isFrontlightOff() then return false end
    local cb_handled = self:turnOffFrontlightHW(done_callback)
    self.is_fl_on = false
    self:stateChanged()
    if not cb_handled and done_callback then
        done_callback()
    end
    return true
end

function BasePowerD:turnOnFrontlight(done_callback)
    if not self.device:hasFrontlight() then return end
    if self:isFrontlightOn() then return false end
    if self.fl_intensity == self.fl_min then return false end  --- @fixme what the hell?
    local cb_handled = self:turnOnFrontlightHW(done_callback)
    self.is_fl_on = true
    self:stateChanged()
    if not cb_handled and done_callback then
        done_callback()
    end
    return true
end

function BasePowerD:frontlightWarmth()
    if not self.device:hasNaturalLight() then
        return 0
    end
    --- @note: No live query, much like frontlightIntensity
    return self.fl_warmth
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
        return nil
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

--- @note: Takes an intensity in the native scale (i.e., [self.fl_min, self.fl_max])
function BasePowerD:setIntensity(intensity)
    if not self.device:hasFrontlight() then return false end
    if intensity == self:frontlightIntensity() then return false end
    self.fl_intensity = self:normalizeIntensity(intensity)
    logger.dbg("set light intensity", self.fl_intensity)
    self:setIntensityHW(self.fl_intensity)
    self:stateChanged()
    return true
end

function BasePowerD:normalizeWarmth(warmth)
    warmth = warmth < 0 and 0 or warmth
    return warmth > 100 and 100 or warmth
end

function BasePowerD:toNativeWarmth(ko_warmth)
    return Math.round(ko_warmth / self.warmth_scale)
end

function BasePowerD:fromNativeWarmth(nat_warmth)
    return Math.round(nat_warmth * self.warmth_scale)
end

--- @note: Takes a warmth in the *KOReader* scale (i.e., [0, 100], *sic*)
function BasePowerD:setWarmth(warmth, force_setting)
    if not self.device:hasNaturalLight() then return false end
    if not force_setting and warmth == self:frontlightWarmth() then return false end
    -- Which means that fl_warmth is *also* in the KOReader scale (unlike fl_intensity)
    self.fl_warmth = self:normalizeWarmth(warmth)
    local nat_warmth = self:toNativeWarmth(self.fl_warmth)
    logger.dbg("set light warmth", self.fl_warmth, "->", nat_warmth)
    self:setWarmthHW(nat_warmth)
    self:stateChanged()
    return true
end

function BasePowerD:getCapacity()
    -- BasePowerD is loaded before UIManager.
    -- Nothing *currently* calls this before UIManager is actually loaded, but future-proof this anyway.
    local now
    if UIManager then
        now = UIManager:getElapsedTimeSinceBoot()
    else
        -- Add time the device was in standby and suspend
        now = time.now() + self.device.total_standby_time + self.device.total_suspend_time
    end

    if now - self.last_capacity_pull_time >= time.s(60) then
        self.batt_capacity = self:getCapacityHW()
        self.last_capacity_pull_time = now
    end
    return self.batt_capacity
end

function BasePowerD:isCharging()
    return self:isChargingHW()
end

function BasePowerD:isCharged()
    return self:isChargedHW()
end

function BasePowerD:getAuxCapacity()
    local now

    if UIManager then
        now = UIManager:getElapsedTimeSinceBoot()
    else
        -- Add time the device was in standby and suspend
        now = time.now() + self.device.total_standby_time + self.device.total_suspend_time
    end

    if now - self.last_aux_capacity_pull_time >= time.s(60) then
        local aux_batt_capa = self:getAuxCapacityHW()
        -- If the read failed, don't update our cache, and retry next time.
        if aux_batt_capa then
            self.aux_batt_capacity = aux_batt_capa
            self.last_aux_capacity_pull_time = now
        end
    end
    return self.aux_batt_capacity
end

function BasePowerD:invalidateCapacityCache()
    self.last_capacity_pull_time = time.s(-61)
    self.last_aux_capacity_pull_time = self.last_capacity_pull_time
end

function BasePowerD:isAuxCharging()
    return self:isAuxChargingHW()
end

function BasePowerD:isAuxCharged()
    return self:isAuxChargedHW()
end

function BasePowerD:isAuxBatteryConnected()
    return self:isAuxBatteryConnectedHW()
end

function BasePowerD:stateChanged()
    -- BasePowerD is loaded before UIManager. So we cannot broadcast events before UIManager has been loaded.
    if UIManager then
        UIManager:broadcastEvent(Event:new("FrontlightStateChanged"))
    end
end

-- Silly helper to avoid code duplication ;).
function BasePowerD:getBatterySymbol(is_charged, is_charging, capacity)
    if is_charged then
        return ""
    elseif is_charging then
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
