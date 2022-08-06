-- Mock RTC implementation backed by kindle's system powerd via lipc
local MockRTC = {
    _wakeup_scheduled = false,
    _wakeup_scheduled_epoch = nil,
}

-- This call always succeeds, errors will only happen at suspend time in
-- powerd:setRtcWakeup()
function MockRTC:setWakeupAlarm(epoch, enabled)
    enabled = (enabled ~= nil) and enabled or true
    if enabled then
        self._wakeup_scheduled = true
        self._wakeup_scheduled_epoch = epoch
    else
        self:unsetWakeupAlarm()
    end
    return true
end

function MockRTC:unsetWakeupAlarm()
    self._wakeup_scheduled = false
    self._wakeup_scheduled_epoch = nil
end

function MockRTC:getWakeupAlarmEpoch()
    return self._wakeup_scheduled_epoch
end

--[[--
Checks if the alarm we set matches the current time.
--]]
function MockRTC:validateWakeupAlarmByProximity(task_alarm, proximity)
    -- In principle alarm time and current time should match within a second,
    -- but let's be absurdly generous and assume anything within 30 is a match.
    -- In practice, suspend() schedules check_unexpected_wakeup 15s *after*
    -- the actual wakeup, so we need to account for at least that much ;).
    proximity = proximity or 30

    -- We want everything in UTC time_t (i.e. a Posix epoch).
    local now = os.time()
    local alarm = self:getWakeupAlarmEpoch()
    if not (alarm and task_alarm) then return end

   -- Everything's in UTC, ask Lua to convert that to a human-readable format in the local timezone
    print("validateWakeupAlarmByProximity:",
        "\ntask              @ " .. task_alarm .. os.date(" (%F %T %z)", task_alarm),
        "\nlast set alarm    @ " .. alarm .. os.date(" (%F %T %z)", alarm),
        "\ncurrent time is     " .. now .. os.date(" (%F %T %z)", now))

    -- If our stored alarm and the provided task alarm don't match,
    -- we're not talking about the same task.
    if task_alarm and alarm ~= task_alarm then return end

    local diff = now - alarm
    if diff >= 0 and diff < proximity then return true end
end

function MockRTC:isWakeupAlarmScheduled()
    return self._wakeup_scheduled
end

return MockRTC
