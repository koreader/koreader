local BasePowerD = require("device/generic/powerd")
-- liblipclua, see require below

local KindlePowerD = BasePowerD:new{
    fl_min = 0, fl_max = 24,

    flIntensity = nil,
    battCapacity = nil,
    is_charging = nil,
    lipc_handle = nil,
}

function KindlePowerD:init()
    local lipc = require("liblipclua")
    if lipc then
        self.lipc_handle = lipc.init("com.github.koreader.kindlepowerd")
    end
    if self.lipc_handle then
        self.flIntensity = self.lipc_handle:get_int_property("com.lab126.powerd", "flIntensity")
    else
        self.flIntensity = self:read_int_file(self.fl_intensity_file)
    end
end

function KindlePowerD:toggleFrontlight()
    local sysint = self:read_int_file(self.fl_intensity_file)
    if sysint == 0 then
        self:setIntensity(self.flIntensity)
    else
        os.execute("echo -n 0 > " .. self.fl_intensity_file)
    end
end

function KindlePowerD:setIntensityHW()
    if self.lipc_handle ~= nil then
        self.lipc_handle:set_int_property("com.lab126.powerd", "flIntensity", self.flIntensity)
    else
        os.execute("echo -n ".. self.flIntensity .." > " .. self.fl_intensity_file)
    end
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

return KindlePowerD
