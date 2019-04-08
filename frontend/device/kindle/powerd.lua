local BasePowerD = require("device/generic/powerd")
-- liblipclua, see require below

local KindlePowerD = BasePowerD:new{
    fl_min = 0, fl_max = 24,

    lipc_handle = nil,
}

function KindlePowerD:init()
    local haslipc, lipc = pcall(require, "liblipclua")
    if haslipc and lipc then
        self.lipc_handle = lipc.init("com.github.koreader.kindlepowerd")
    end
end

function KindlePowerD:frontlightIntensityHW()
    if not self.device:hasFrontlight() then return 0 end
    -- Kindle stock software does not use intensity file directly, so we need to read from its
    -- lipc property first.
    if self.lipc_handle ~= nil then
        return self.lipc_handle:get_int_property("com.lab126.powerd", "flIntensity")
    else
        -- NOTE: This fallback is of dubious use, as it will NOT match our expected [fl_min..fl_max] range,
        --       each model has a specific curve.
        return self:_readFLIntensity()
    end
end

function KindlePowerD:setIntensityHW(intensity)
    -- NOTE: This means we *require* a working lipc handle to set the FL:
    --       it knows what the UI values should map to for the specific hardware much better than us.
    if self.lipc_handle ~= nil then
        -- NOTE: We want to bypass setIntensity's shenanigans and simply restore the light as-is
        self.lipc_handle:set_int_property(
            "com.lab126.powerd", "flIntensity", intensity)
    end
    if intensity == 0 then
        -- NOTE: when intensity is 0, we want to *really* kill the light, so do it manually
        -- (asking lipc to set it to 0 would in fact set it to 1 on most Kindles).
        -- We do *both* to make the fl restore on resume less jarring on devices where lipc 0 != off.
        os.execute("echo -n ".. intensity .." > " .. self.fl_intensity_file)
    end
end

function KindlePowerD:getCapacityHW()
    if self.lipc_handle ~= nil then
        return self.lipc_handle:get_int_property("com.lab126.powerd", "battLevel")
    else
        return self:read_int_file(self.batt_capacity_file)
    end
end

function KindlePowerD:isChargingHW()
    local is_charging
    if self.lipc_handle ~= nil then
        is_charging = self.lipc_handle:get_int_property("com.lab126.powerd", "isCharging")
    else
        is_charging = self:read_int_file(self.is_charging_file)
    end
    return is_charging == 1
end

function KindlePowerD:__gc()
    if self.lipc_handle then
        self.lipc_handle:close()
        self.lipc_handle = nil
    end
end

function KindlePowerD:_readFLIntensity()
    return self:read_int_file(self.fl_intensity_file)
end

function KindlePowerD:afterResume()
    if not self.device:hasFrontlight() then
        return
    end
    local UIManager = require("ui/uimanager")
    if self:isFrontlightOn() then
        -- The Kindle framework should turn the front light back on automatically.
        -- The following statement ensures consistency of intensity, but should basically always be redundant,
        -- since we set intensity via lipc and not sysfs ;).
        -- NOTE: This is race-y, and we want to *lose* the race, hence the use of the scheduler (c.f., #4392)
        UIManager:tickAfterNext(function() self:turnOnFrontlightHW() end)
    else
        -- But in the off case, we *do* use sysfs, so this one actually matters.
        UIManager:tickAfterNext(function() self:turnOffFrontlightHW() end)
    end
end

function KindlePowerD:toggleSuspend()
    if self.lipc_handle then
        self.lipc_handle:set_int_property("com.lab126.powerd", "powerButton", 1)
    end
end

return KindlePowerD
