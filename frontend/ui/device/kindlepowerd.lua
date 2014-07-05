local BasePowerD = require("ui/device/basepowerd")
-- liblipclua, see require below

local KindlePowerD = BasePowerD:new{
    fl_min = 0, fl_max = 24,
    kpw1_frontlight = "/sys/devices/system/fl_tps6116x/fl_tps6116x0/fl_intensity",
    kpw2_frontlight = "/sys/class/backlight/max77696-bl/brightness",
    kt_kpw_capacity = "/sys/devices/system/yoshi_battery/yoshi_battery0/battery_capacity",
    kpw_charging = "/sys/devices/platform/aplite_charger.0/charging",
    kt_charging = "/sys/devices/platform/fsl-usb2-udc/charging",

    flIntensity = nil,
    battCapacity = nil,
    is_charging = nil,
    lipc_handle = nil,
}

function KindlePowerD:new(o)
    local o = o or {}
    setmetatable(o, self)
    self.__index = self
    if o.init then o:init(o.model) end
    return o
end

function KindlePowerD:init(model)
    local lipc = require("liblipclua")
    if lipc then
        self.lipc_handle = lipc.init("com.github.koreader.kindlepowerd")
    end

    if model == "KindleTouch" then
        self.batt_capacity_file = self.kt_kpw_capacity
        self.is_charging_file = self.kt_charging
    elseif model == "KindlePaperWhite" then
        self.fl_intensity_file = self.kpw1_frontlight
        self.batt_capacity_file = self.kt_kpw_capacity
        self.is_charging_file = self.kpw_charging
    elseif model == "KindlePaperWhite2" then
        self.fl_intensity_file = self.kpw2_frontlight
        self.batt_capacity_file = self.kt_kpw_capacity
        self.is_charging_file = self.kpw_charging
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

function KindlePowerD:coda()
    if self.lipc_handle then
        self.lipc_handle:close()
    end
end

return KindlePowerD
