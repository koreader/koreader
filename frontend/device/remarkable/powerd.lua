local BasePowerD = require("device/generic/powerd")
local SysfsLight = require("device/sysfs_light")
local ffiUtil = require("ffi/util")

local Remarkable_PowerD = BasePowerD:new{
    is_charging = nil,
    fl = nil,
    fl_min = 0, fl_max = 2047,
}

function Remarkable_PowerD:init()
    if self.device:hasFrontlight() then
        self.fl = SysfsLight:new(self.device.frontlight_settings)
    end
end

function Remarkable_PowerD:saveSettings()
    if self.device:hasFrontlight() then
        G_reader_settings:saveSetting("frontlight_intensity", self.fl_intensity)
        G_reader_settings:saveSetting("is_frontlight_on", self.is_fl_on)
    end
end

function Remarkable_PowerD:frontlightIntensityHW()
    if not self.device:hasFrontlight() then return 0 end
    local val = self:read_int_file(self.fl.frontlight_white .. "/brightness")
    if val == 0 then
        val = G_reader_settings:readSetting("frontlight_intensity") or 20
    end
    return val
end

function Remarkable_PowerD:isFrontlightOnHW()
    if not self.device:hasFrontlight() then return false end
    -- 0 is on, 4 is off as documented in Linux backlight.h
    return self:read_int_file(self.fl.frontlight_white .. "/bl_power") == 0
end

function Remarkable_PowerD:setIntensityHW(intensity)
    if not self.device:hasFrontlight() then return end
    self:setBrightness(intensity)
    self:_decideFrontlightState()
end

function Remarkable_PowerD:getCapacityHW()
    return self:read_int_file(self.capacity_file)
end

function Remarkable_PowerD:isChargingHW()
    return self:read_str_file(self.status_file) == "Charging"
end

function Remarkable_PowerD:hasHallSensor()
    return self.hall_file ~= nil
end

function Remarkable_PowerD:isHallSensorEnabled()
    local int = self:read_int_file(self.hall_file)
    return int == 0
end

function Remarkable_PowerD:onToggleHallSensor(toggle)
    local inhibit_value
    if toggle == nil then
        -- Flip it
        inhibit_value = self:isHallSensorEnabled() and 1 or 0
    else
        -- Honor the requested state
        inhibit_value = toggle and 0 or 1
    end
    ffiUtil.writeToSysfs(inhibit_value, self.hall_file)

    G_reader_settings:saveSetting("remarkable_hall_effect_sensor_enabled", inhibit_value == 0)
end

function Remarkable_PowerD:beforeSuspend()
    -- Inhibit user input and emit the Suspend event.
    self.device:_beforeSuspend()

    if self.fl then
        self:setBrightness(0)
    end
end

function Remarkable_PowerD:afterResume()
    if self.fl then
        if self.fl_was_on then
            self:setBrightness(self.fl_intensity)
        else
            self:setBrightness(0)
        end
    end

    self:invalidateCapacityCache()

    -- Restore user input and emit the Resume event.
    self.device:_afterResume()
end

function Remarkable_PowerD:setBrightness(brightness)
    self:_set_light_value(self.fl.frontlight_white, brightness)
end

function Remarkable_PowerD:_set_light_value(sysfs_directory, value)
    if not sysfs_directory then return end
    -- 0 is on, 4 is off as documented in Linux backlight.h
    if (value > 0) then
        ffiUtil.writeToSysfs(0, sysfs_directory .. "/bl_power")
    else
        ffiUtil.writeToSysfs(4, sysfs_directory .. "/bl_power")
    end
    ffiUtil.writeToSysfs(value, sysfs_directory .. "/brightness")
end

return Remarkable_PowerD
