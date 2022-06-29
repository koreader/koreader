local KindleRTC = {
    _wakeup_scheduled = false,
    _wakeup_scheduled_epoch = nil,
}

-- RTC functions with kindle specific implementations
-- This call always succeeds, errors will only happen at suspend time in
-- powerd:setRtcWakeup()
function KindleRTC:setWakeupAlarm(epoch, enabled)
    enabled = (enabled ~= nil) and enabled or true
    if enabled then
        self._wakeup_scheduled = true
        self._wakeup_scheduled_epoch = epoch
    else
        self:unsetWakeupAlarm()
    end
    return true
end

function KindleRTC:unsetWakeupAlarm()
    self._wakeup_scheduled = false
    self._wakeup_scheduled_epoch = nil
end

function KindleRTC:getWakeupAlarmEpoch()
    return self._wakeup_scheduled_epoch
end

--[[--
Checks if the alarm we set matches the current time.
--]]
function KindleRTC:validateWakeupAlarmByProximity(task_alarm, proximity)
    -- In principle alarm time and current time should match within a second,
    -- but let's be absurdly generous and assume anything within 30 is a match.
    -- In practice, Kobo's suspend() schedules check_unexpected_wakeup 15s *after*
    -- the actual wakeup, so we need to account for at least that much ;).
    proximity = proximity or 30

    -- We want everything in UTC time_t (i.e. a Posix epoch).
    local now = os.time()

    local alarm = self:getWakeupAlarmEpoch()

    if not (alarm and task_alarm) then return end

   -- Everything's in UTC, ask Lua to convert that to a human-readable format in the local timezone
    if task_alarm then
        print("validateWakeupAlarmByProximity:",
            "\ntask              @ " .. task_alarm .. os.date(" (%F %T %z)", task_alarm),
            "\nlast set alarm    @ " .. alarm .. os.date(" (%F %T %z)", alarm),
            "\ncurrent time is     " .. now .. os.date(" (%F %T %z)", now))
    end

    -- If our stored alarm and the provided task alarm don't match,
    -- we're not talking about the same task.
    if task_alarm and alarm ~= task_alarm then return end

    local diff = now - alarm
    -- Kindle stays in Ready to suspend for 10 seconds so the alarm may
    -- fire 10 seconds early
    if diff >= -10 and diff < proximity then return true end
end

function KindleRTC:isWakeupAlarmScheduled()
    return self._wakeup_scheduled
end

return KindleRTC
