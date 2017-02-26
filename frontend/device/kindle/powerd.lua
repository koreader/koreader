local BasePowerD = require("device/generic/powerd")
-- liblipclua, see require below

local KindlePowerD = BasePowerD:new{
    fl_min = 0, fl_max = 24,

    fl_intensity = nil,
    battCapacity = nil,
    is_charging = nil,
    lipc_handle = nil,

    is_fl_on = false,
}

function KindlePowerD:init()
    local haslipc, lipc = pcall(require, "liblipclua")
    if haslipc and lipc then
        self.lipc_handle = lipc.init("com.github.koreader.kindlepowerd")
    end
    if self.device.hasFrontlight() then
        -- Kindle stock software does not use intensity file directly, so we need to read from its
        -- lipc property first.
        if self.lipc_handle ~= nil then
            self.fl_intensity = self.lipc_handle:get_int_property("com.lab126.powerd", "flIntensity")
        else
            self.fl_intensity = self:_readFLIntensity()
        end
        self:_set_fl_on()
    end
end

function KindlePowerD:toggleFrontlight()
    if not self.device.hasFrontlight() then
        return
    end

    if self:_readFLIntensity() == 0 then
        self:setIntensityHW()
    else
        self:_turnOffFL()
    end
end

function KindlePowerD:setIntensityHW()
    if self.lipc_handle ~= nil and self.fl_intensity > 0 then
        -- NOTE: We want to bypass setIntensity's shenanigans and simply restore the light as-is
        self.lipc_handle:set_int_property("com.lab126.powerd", "flIntensity", self.fl_intensity)
    else
        -- NOTE: when fl_intensity is 0, We want to really kill the light, so do it manually
        -- (asking lipc to set it to 0 would in fact set it to 1)...
        os.execute("echo -n ".. self.fl_intensity .." > " .. self.fl_intensity_file)
    end
    self:_set_fl_on()
end

function KindlePowerD:getCapacityHW()
    if self.lipc_handle ~= nil then
        self.battCapacity = self.lipc_handle:get_int_property("com.lab126.powerd", "battLevel")
    else
        self.battCapacity = self:read_int_file(self.batt_capacity_file)
    end
    return self.battCapacity
end

function KindlePowerD:isChargingHW()
    if self.lipc_handle ~= nil then
        self.is_charging = self.lipc_handle:get_int_property("com.lab126.powerd", "isCharging")
    else
        self.is_charging = self:read_int_file(self.is_charging_file)
    end
    return self.is_charging == 1
end

function KindlePowerD:__gc()
    if self.lipc_handle then
        self.lipc_handle:close()
        self.lipc_handle = nil
    end
end

function KindlePowerD:_turnOffFL()
    -- NOTE: We want to really kill the light, so do it manually (asking lipc to set it to 0 would in fact set it to 1)...
    os.execute("echo -n 0 > " .. self.fl_intensity_file)
    self.is_fl_on = false
end

function KindlePowerD:_readFLIntensity()
    return self:read_int_file(self.fl_intensity_file)
end

function KindlePowerD:_set_fl_on()
    self.is_fl_on = (self.fl_intensity > 0)
end

function KindlePowerD:afterResume()
    if not self.device.hasFrontlight() then
        return
    end
    if self.is_fl_on then
        -- Kindle stock software should turn on the front light automatically. The follow statement
        -- ensure the consistency of intensity.
        self:setIntensityHW()
    else
        self:_turnOffFL()
    end
end

return KindlePowerD
