local BasePowerD = require("device/generic/powerd")
local UIManager
local WakeupMgr = require("device/wakeupmgr")
local logger = require("logger")
local ffiUtil = require("ffi/util")
-- liblipclua, see require below

local KindlePowerD = BasePowerD:new{
    fl_min = 0, fl_max = 24,
    fl_warmth_min = 0, fl_warmth_max = 24,

    lipc_handle = nil,
}

function KindlePowerD:init()
    local haslipc, lipc = pcall(require, "liblipclua")
    if haslipc then
        self.lipc_handle = lipc.init("com.github.koreader.kindlepowerd")
    end

    -- On devices where lipc step 0 is *not* off, we add a synthetic fl level where 0 *is* off,
    -- which allows us to keep being able to use said step 0 as the first "on" step.
    if not self.device:canTurnFrontlightOff() then
        self.fl_max = self.fl_max + 1
    end

    if self.device:hasAuxBattery() then
        self.getAuxCapacityHW = function(this)
            return this:unchecked_read_int_file(self.aux_batt_capacity_file)
        end

        self.isAuxBatteryConnectedHW = function(this)
            local status = this:read_str_file(self.aux_batt_status_file)
            if status == nil then
                -- File could not be read, assume not connected
                return false
            end
            -- File was read, assume aux battery is connected
            return true
        end

        self.isAuxChargingHW = function(this)
            -- "Discharging" when discharging
            -- "Full" when full
            -- "Charging" when charging via DCP
            return this:read_str_file(this.aux_batt_status_file) ~= "Discharging"
        end

        self.isAuxChargedHW = function(this)
            return this:read_str_file(this.aux_batt_status_file) == "Full"
        end
    end

    self:initWakeupMgr()
end

-- If we start with the light off (fl_intensity is fl_min), ensure a toggle will set it to the lowest "on" step,
-- and that we update fl_intensity (by using setIntensity and not setIntensityHW).
function KindlePowerD:turnOnFrontlightHW(done_callback)
    self:setIntensity(self.fl_intensity == self.fl_min and self.fl_min + 1 or self.fl_intensity)

    return false
end
-- Which means we need to get rid of the insane fl_intensity == fl_min shortcut in turnOnFrontlight, too...
-- That dates back to #2941, and I have no idea what it's supposed to help with.
function KindlePowerD:turnOnFrontlight(done_callback)
    if not self.device:hasFrontlight() then return end
    if self:isFrontlightOn() then return false end
    local cb_handled = self:turnOnFrontlightHW(done_callback)
    self.is_fl_on = true
    self:stateChanged()
    if not cb_handled and done_callback then
        done_callback()
    end
    return true
end

function KindlePowerD:frontlightIntensityHW()
    if not self.device:hasFrontlight() then return 0 end
    -- Kindle stock software does not use intensity file directly, so go through lipc to keep us in sync.
    if self.lipc_handle ~= nil then
        -- Handle the step 0 switcheroo on ! canTurnFrontlightOff devices...
        if self.device:canTurnFrontlightOff() then
            return self.lipc_handle:get_int_property("com.lab126.powerd", "flIntensity")
        else
            local lipc_fl_intensity = self.lipc_handle:get_int_property("com.lab126.powerd", "flIntensity")
            -- NOTE: If lipc returns 0, compare against what the kernel says,
            --       to avoid breaking on/off detection on devices where lipc 0 doesn't actually turn it off (<= PW3),
            --       c.f., #5986
            if lipc_fl_intensity == self.fl_min then
                local sysfs_fl_intensity = self:_readFLIntensity()
                if sysfs_fl_intensity ~= self.fl_min then
                    -- Return something potentially slightly off (as we can't be sure of the sysfs -> lipc mapping),
                    -- but, more importantly, something that's not fl_min (0), so we properly detect the light as on,
                    -- and update fl_intensity accordingly.
                    -- That's only tripped if it was set to fl_min from the stock UI,
                    -- as we ourselves *do* really turn it off when we do that.
                    return self.fl_min + 1
                else
                    return self.fl_min
                end
            else
                -- We've added a synthetic step...
                return lipc_fl_intensity + 1
            end
        end
    else
        -- NOTE: This fallback is of dubious use, as it will NOT match our expected [fl_min..fl_max] range,
        --       each model has a specific curve.
        return self:_readFLIntensity()
    end
end

-- Make sure isFrontlightOn reflects the actual HW state,
-- as self.fl_intensity is kept as-is when toggling the light off,
-- in order to be able to toggle it back on at the right intensity.
function KindlePowerD:isFrontlightOnHW()
    local hw_intensity = self:frontlightIntensityHW()
    return hw_intensity > self.fl_min
end

function KindlePowerD:setIntensityHW(intensity)
    -- Handle the synthetic step switcheroo on ! canTurnFrontlightOff devices...
    local turn_it_off = false
    if not self.device:canTurnFrontlightOff() then
        if intensity > 0 then
            intensity = intensity - 1
        else
            -- And if we *really* requested 0, turn it off manually.
            turn_it_off = true
        end
    end
    -- NOTE: This means we *require* a working lipc handle to set the FL:
    --       it knows what the UI values should map to for the specific hardware much better than us.
    if self.lipc_handle ~= nil then
        -- NOTE: We want to bypass setIntensity's shenanigans and simply restore the light as-is
        self.lipc_handle:set_int_property("com.lab126.powerd", "flIntensity", intensity)
    end
    if turn_it_off then
        -- NOTE: when intensity is 0, we want to *really* kill the light, so do it manually
        -- (asking lipc to set it to 0 would in fact set it to > 0 on ! canTurnFrontlightOff Kindles).
        -- We do *both* to make the fl restore on resume less jarring on devices where lipc 0 != off.
        ffiUtil.writeToSysfs(intensity, self.fl_intensity_file)

        -- And in case there are two LED groups...
        -- This should never happen as all warmth devices so far canTurnFrontlightOff
        if self.warmth_intensity_file then
            ffiUtil.writeToSysfs(intensity, self.warmth_intensity_file)
        end
    end

    -- The state might have changed, make sure we don't break isFrontlightOn
    self:_decideFrontlightState()
end

function KindlePowerD:frontlightWarmthHW()
    if self.lipc_handle ~= nil then
        local nat_warmth = self.lipc_handle:get_int_property("com.lab126.powerd", "currentAmberLevel")
        if nat_warmth then
            -- [0...24] -> [0...100]
            return self:fromNativeWarmth(nat_warmth)
        else
            return 0
        end
    end
end

function KindlePowerD:setWarmthHW(warmth)
    if self.lipc_handle ~= nil then
        self.lipc_handle:set_int_property("com.lab126.powerd", "currentAmberLevel", warmth)
    end
end

function KindlePowerD:getCapacityHW()
    if self.lipc_handle ~= nil then
        return self.lipc_handle:get_int_property("com.lab126.powerd", "battLevel")
    elseif self.batt_capacity_file then
        return self:read_int_file(self.batt_capacity_file)
    else
        local std_out = io.popen("gasgauge-info -c 2>/dev/null", "r")
        if std_out then
            local result = std_out:read("*number")
            std_out:close()
            return result or 0
        else
            return 0
        end
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

function KindlePowerD:isChargedHW()
    -- Older kernels don't necessarily have this...
    if self.batt_status_file then
        return self:read_str_file(self.batt_status_file) == "Full"
    end

    return false
end

function KindlePowerD:hasHallSensor()
    return self.hall_file ~= nil
end

function KindlePowerD:isHallSensorEnabled()
    local int = self:read_int_file(self.hall_file)
    return int == 1
end

function KindlePowerD:onToggleHallSensor(toggle)
    if toggle == nil then
        -- Flip it
        toggle = self:isHallSensorEnabled() and 0 or 1
    else
        -- Honor the requested state
        toggle = toggle and 1 or 0
    end
    ffiUtil.writeToSysfs(toggle, self.hall_file)

    G_reader_settings:saveSetting("kindle_hall_effect_sensor_enabled", toggle == 1 and true or false)
end

function KindlePowerD:_readFLIntensity()
    return self:read_int_file(self.fl_intensity_file)
end

function KindlePowerD:toggleSuspend()
    if self.lipc_handle then
        self.lipc_handle:set_int_property("com.lab126.powerd", "powerButton", 1)
    else
        os.execute("powerd_test -p")
    end
end

-- Kindle only allows setting the RTC via lipc during the ReadyToSuspend state
function KindlePowerD:setRtcWakeup(seconds_from_now)
    if self.lipc_handle then
        self.lipc_handle:set_int_property("com.lab126.powerd", "rtcWakeup", seconds_from_now)
    end
end

-- Check the powerd state: are we still in screensaver mode.
function KindlePowerD:getPowerdState()
    if self.lipc_handle then
        return self.lipc_handle:get_string_property("com.lab126.powerd", "state")
    end
end

function KindlePowerD:checkUnexpectedWakeup()
    local state = self:getPowerdState()
    logger.dbg("Powerd resume state:", state)
    -- If we moved on to the active state,
    -- then we were woken by user input not our alarm.
    if state ~= "screenSaver" and state ~= "suspended" then return end

    if self.device.wakeup_mgr:isWakeupAlarmScheduled() and self.device.wakeup_mgr:wakeupAction(90) then
        logger.info("Kindle scheduled wakeup")
    else
        logger.info("Kindle unscheduled wakeup")
    end
end

-- Dummy functions. They will be defined in initWakeupMgr
function KindlePowerD:wakeupFromSuspend() end
function KindlePowerD:readyToSuspend() end

-- Support WakeupMgr on Lipc & supportsScreensaver devices.
function KindlePowerD:initWakeupMgr()
    if not self.device:supportsScreensaver() then return end
    if self.lipc_handle == nil then return end

    function KindlePowerD:wakeupFromSuspend(ts)
        -- Give the device a few seconds to settle.
        -- This filters out user input resumes -> device will resume to active
        -- Also the Kindle stays in Ready to suspend for 10 seconds
        -- so the alarm may fire 10 seconds early
        UIManager:scheduleIn(15, self.checkUnexpectedWakeup, self)
    end

    function KindlePowerD:readyToSuspend(delay)
        if self.device.wakeup_mgr:isWakeupAlarmScheduled() then
            local now = os.time()
            local alarm = self.device.wakeup_mgr:getWakeupAlarmEpoch()
            if alarm > now then
                -- Powerd / Lipc need seconds_from_now not epoch
                self:setRtcWakeup(alarm - now)
            else
                -- wakeup time is in the past
                self.device.wakeup_mgr:removeTasks(alarm)
            end
        end
    end

    self.device.wakeup_mgr = WakeupMgr:new{rtc = require("device/kindle/mockrtc")}
end

-- Ask powerd to reset the t1 timeout, so that AutoSuspend can do its thing properly
function KindlePowerD:resetT1Timeout()
    -- NOTE: powerd will only send a t1TimerReset event every $(kdb get system/daemon/powerd/send_t1_reset_interval) (15s),
    --       which is just fine, as we should only request it at most every 5 minutes ;).
    -- NOTE: This will fail if the device is already showing the screensaver.
    if self.lipc_handle then
        -- AFAIK, the value is irrelevant
        self.lipc_handle:set_int_property("com.lab126.powerd", "touchScreenSaverTimeout", 1)
    else
        os.execute("lipc-set-prop -i com.lab126.powerd touchScreenSaverTimeout 1")
    end
end

function KindlePowerD:beforeSuspend()
    -- Inhibit user input and emit the Suspend event.
    self.device:_beforeSuspend()
end

function KindlePowerD:afterResume()
    self:invalidateCapacityCache()

    -- Restore user input and emit the Resume event.
    self.device:_afterResume()

    if not self.device:hasFrontlight() then
        return
    end
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

function KindlePowerD:UIManagerReadyHW(uimgr)
    UIManager = uimgr
end

--- @fixme: This won't ever fire on its own, as KindlePowerD is already a metatable on a plain table.
function KindlePowerD:__gc()
    if self.lipc_handle then
        self.lipc_handle:close()
        self.lipc_handle = nil
    end
end

return KindlePowerD
