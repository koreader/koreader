local BasePowerD = require("device/generic/powerd")
local SysfsLight = require("device/sysfs_light")
local ffiUtil = require("ffi/util")

local Remarkable_PowerD = BasePowerD:new{
    is_charging = nil,
    fl = nil,
    fl_min = 0, fl_max = 2047,
}

function Remarkable_PowerD:_syncLightOnStart()
    local new_intensity = G_reader_settings:readSetting("frontlight_intensity") or nil
    local is_frontlight_on = G_reader_settings:readSetting("is_frontlight_on") or nil

    if new_intensity ~= nil then
        self.hw_intensity = new_intensity
    end

    if is_frontlight_on ~= nil then
        self.initial_is_fl_on = is_frontlight_on
    end

    if self.initial_is_fl_on == false and self.hw_intensity == 0 then
        self.hw_intensity = 1
    end
end


function Remarkable_PowerD:init()
    self.hw_intensity = 20
    self.initial_is_fl_on = true

    if self.device:hasFrontlight() then
        self.fl = SysfsLight:new(self.device.frontlight_settings)
        self:_syncLightOnStart()
    end
end

function Remarkable_PowerD:saveSettings()
    if self.device:hasFrontlight() then
        local cur_intensity = self.fl_intensity
        local cur_is_fl_on = self.is_fl_on
        G_reader_settings:saveSetting("frontlight_intensity", cur_intensity)
        G_reader_settings:saveSetting("is_frontlight_on", cur_is_fl_on)
    end
end

function Remarkable_PowerD:frontlightIntensityHW()
    if not self.device:hasFrontlight() then return 0 end
    return self.hw_intensity
end

function Remarkable_PowerD:isFrontlightOnHW()
    if self.initial_is_fl_on ~= nil then
        local ret = self.initial_is_fl_on
        self.initial_is_fl_on = nil
        return ret
    end
    return self.hw_intensity > 0
end

function Remarkable_PowerD:setIntensityHW(intensity)
    if not self.device:hasFrontlight() then return end
    self:setBrightness(intensity)
    self.hw_intensity = intensity
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
    if toggle == nil then
        -- Flip it
        toggle = self:isHallSensorEnabled() and 1 or 0
    else
        -- Honor the requested state
        toggle = toggle and 1 or 0
    end
    ffiUtil.writeToSysfs(toggle, self.hall_file)

    G_reader_settings:saveSetting("remarkable_hall_effect_sensor_enabled", toggle == 0 and true or false)
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
        self:setBrightness(self.hw_intensity)
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
    -- for rMPP '0' is on and '4' is off
    if (value > 0) then
        ffiUtil.writeToSysfs(0, sysfs_directory .. "/bl_power")
    else
        ffiUtil.writeToSysfs(4, sysfs_directory .. "/bl_power")
    end
    ffiUtil.writeToSysfs(value, sysfs_directory .. "/brightness")
end

return Remarkable_PowerD
