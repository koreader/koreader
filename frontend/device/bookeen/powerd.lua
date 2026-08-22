local BasePowerD = require("device/generic/powerd")

local base_path = '/sys/class/power_supply/battery/'

local Bookeen_PowerD = BasePowerD:new{
    fl_min = 0,
    fl_max = 255,
    is_charging = nil,
    capacity_file = base_path .. 'capacity',
    status_file = base_path .. 'status',
}

function Bookeen_PowerD:init()
end

function Bookeen_PowerD:frontlightIntensityHW()
    local std_out = io.popen('/bin/frontlight', "r")
    if std_out then
        local output = std_out:read("*all")
        std_out:close()
        return 255 - tonumber(output)
    end
    return 0
end

function Bookeen_PowerD:setIntensityHW(intensity)
    local inv_intensity = 255 - intensity
    local std_out = io.popen('/bin/frontlight ' .. tostring(inv_intensity))
    if std_out then
        std_out:close()
    end
    self:_decideFrontlightState()
end

function Bookeen_PowerD:getCapacityHW()
    return self:read_int_file(self.capacity_file)
end

function Bookeen_PowerD:isChargingHW()
    return self:read_str_file(self.status_file) == "Charging"
end

-- NOTE: These two used to be empty overrides, which silently broke suspend in two ways:
--       the Suspend/Resume Events were never broadcast (so plugins, and the frontlight,
--       never learned about it), and input was never inhibited, so a keypress during the
--       screensaver would leak through. Both matter now that the power button actually
--       reaches onPowerEvent (c.f. Bookeen:setEventHandlers). Modelled on cervantes/powerd.
function Bookeen_PowerD:beforeSuspend()
    -- The frontlight is a separate rail from the panel and stays lit across `mem` suspend,
    -- so drive it to 0 explicitly. Do *not* go through turnOffFrontlight(): that records
    -- fl_was_on for the interactive toggle, which would then fight the user's own setting.
    -- self.fl_intensity is left untouched, so afterResume can just re-assert it.
    if self:isFrontlightOn() then
        self:setIntensityHW(self.fl_min)
    end

    -- Inhibit user input and emit the Suspend event.
    self.device:_beforeSuspend()
end

function Bookeen_PowerD:afterResume()
    -- MONOTONIC doesn't tick across suspend, so the cached capacity is stale by definition.
    self:invalidateCapacityCache()

    -- Re-assert whatever the frontlight was set to before we zeroed it above. Note this
    -- reads fl_intensity rather than querying /bin/frontlight: the hardware value is 0
    -- right now, so probing it would latch the off state permanently.
    if self:isFrontlightOn() then
        self:setIntensityHW(self.fl_intensity)
    end

    -- Restore user input and emit the Resume event.
    self.device:_afterResume()
end

return Bookeen_PowerD

