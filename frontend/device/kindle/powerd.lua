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
    if not self.device.hasFrontlight() then return 0 end
    -- Kindle stock software does not use intensity file directly, so we need to read from its
    -- lipc property first.
    if self.lipc_handle ~= nil then
        return self.lipc_handle:get_int_property("com.lab126.powerd", "flIntensity")
    else
        return self:_readFLIntensity()
    end
end

function KindlePowerD:setIntensityHW(intensity)
    if self.lipc_handle ~= nil and intensity > 0 then
        -- NOTE: We want to bypass setIntensity's shenanigans and simply restore the light as-is
        self.lipc_handle:set_int_property(
            "com.lab126.powerd", "flIntensity", intensity)
    else
        -- NOTE: when intensity is 0, We want to really kill the light, so do it manually
        -- (asking lipc to set it to 0 would in fact set it to 1)...
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
    if not self.device.hasFrontlight() then
        return
    end
    if self:isFrontlightOn() then
        -- Kindle stock software should turn on the front light automatically. The follow statement
        -- ensure the consistency of intensity.
        self:turnOnFrontlightHW()
    else
        self:turnOffFrontlightHW()
    end
end

return KindlePowerD
