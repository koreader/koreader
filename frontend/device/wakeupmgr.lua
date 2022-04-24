--[[--
RTC wakeup interface.

Many devices can schedule hardware wakeups with a real time clock alarm.
On embedded devices this can typically be easily manipulated by the user
through `/sys/class/rtc/rtc0/wakealarm`. Some, like the Kobo Aura H2O,
can only schedule wakeups through ioctl.

See @{ffi.rtc} for implementation details.

See also: <https://linux.die.net/man/4/rtc>.
--]]

local RTC = require("ffi/rtc")
local logger = require("logger")

--[[--
WakeupMgr base class.

@table WakeupMgr
--]]
local WakeupMgr = {
    dev_rtc = "/dev/rtc0", -- RTC device
    _task_queue = {},      -- Table with epoch at which to schedule the task and the function to be scheduled.
}

--[[--
Initiate a WakeupMgr instance.

@usage
local WakeupMgr = require("device/wakeupmgr")
local wakeup_mgr = WakeupMgr:new{
    -- The default is `/dev/rtc0`, but some devices have more than one RTC.
    -- You might therefore need to use `/dev/rtc1`, etc.
    dev_rtc = "/dev/rtc0",
}
--]]
function WakeupMgr:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    if o.init then o:init() end
    return o
end

--[[--
Add a task to the queue.

@todo Group by type to avoid useless wakeups.
For example, maintenance, sync, and shutdown.
I'm not sure if the distinction between maintenance and sync makes sense
but it's wifi on vs. off.
--]]
function WakeupMgr:addTask(seconds_from_now, callback)
    local epoch = RTC:secondsFromNowToEpoch(seconds_from_now)
    logger.info("WakeupMgr: scheduling wakeup in", seconds_from_now)

    local old_upcoming_task = (self._task_queue[1] or {}).epoch

    table.insert(self._task_queue, {
        epoch = epoch,
        callback = callback,
    })
    --- @todo Binary insert? This table should be so small that performance doesn't matter.
    -- It might be useful to have that available as a utility function regardless.
    table.sort(self._task_queue, function(a, b) return a.epoch < b.epoch end)

    local new_upcoming_task = self._task_queue[1].epoch

    if not old_upcoming_task or (new_upcoming_task < old_upcoming_task) then
        self:setWakeupAlarm(self._task_queue[1].epoch)
    end
end

--[[--
Remove task(s) from queue.

This method removes one or more tasks by either scheduled time or callback.
If any tasks are left on exit, the next one will will automatically be re-scheduled.

@int epoch The epoch for when this task is scheduled to wake up.
Normally the preferred method for outside callers.
@int callback A scheduled callback function. Store a reference for use
with anonymous functions.
@treturn bool (true if one or more tasks were removed; false otherwise; nil if the task queue is empty).
--]]
function WakeupMgr:removeTasks(epoch, callback)
    if #self._task_queue < 1 then return end

    local removed = false
    for k = #self._task_queue, 1, -1 do
        local v = self._task_queue[k]
        if epoch == v.epoch or callback == v.callback then
            table.remove(self._task_queue, k)
            removed = true
        end
    end

    -- Re-schedule the next wakeup action, if any.
    -- NOTE: We could be doing fancy checks like addTask, but, really, we'd just be saving an ioctl :p.
    if self._task_queue[1] then
        self:setWakeupAlarm(self._task_queue[1].epoch)
    end

    return removed
end

--[[--
Variant of @{removeTasks} that will only remove a single task, identified by its task queue index.

@int idx Task queue index. Mainly useful within this module.
@treturn bool (true if a task was removed; false otherwise).
--]]
function WakeupMgr:removeTask(idx)
    local removed = false
    -- We don't want to keep the pop'ed entry around, we just want to know if we pop'ed something.
    if table.remove(self._task_queue, idx) then
        removed = true
    end

    -- Re-schedule the next wakeup action, if any.
    -- NOTE: Same as above, this should technically only be necessary if we successfully pop'ed idx 1 ;).
    if self._task_queue[1] then
        self:setWakeupAlarm(self._task_queue[1].epoch)
    end

    return removed
end

--[[--
Execute wakeup action.

This method should be called by the device resume logic in case of a scheduled wakeup.

It checks if the wakeup was scheduled by us using @{validateWakeupAlarmByProximity},
in which case the task is executed.

Regardless of the success of the proximity check, the next task (if any) is re-scheduled.

@int proximity Proximity window to the scheduled wakeup (passed to @{validateWakeupAlarmByProximity}).
@treturn bool (true if we were truly woken up by the scheduled wakeup; false otherwise; nil if there weren't any tasks scheduled).
--]]
function WakeupMgr:wakeupAction(proximity)
    if #self._task_queue > 0 then
        local executed = false
        local task = self._task_queue[1]
        if self:validateWakeupAlarmByProximity(task.epoch, proximity) then
            task.callback()
            self:removeTask(1)
            executed = true
        end

        -- Re-schedule the next wakeup action, if any.
        if self._task_queue[1] then
            self:setWakeupAlarm(self._task_queue[1].epoch)
        end
        return executed
    end

    return nil
end

--[[--
Set wakeup alarm.

Simple wrapper for @{ffi.rtc.setWakeupAlarm}.
--]]
function WakeupMgr:setWakeupAlarm(epoch, enabled)
    return RTC:setWakeupAlarm(epoch, enabled)
end

--[[--
Unset wakeup alarm.

Simple wrapper for @{ffi.rtc.unsetWakeupAlarm}.
--]]
function WakeupMgr:unsetWakeupAlarm()
    return RTC:unsetWakeupAlarm()
end

--[[--
Get wakealarm as set by us.

Simple wrapper for @{ffi.rtc.getWakeupAlarm}.
--]]
function WakeupMgr:getWakeupAlarm()
    return RTC:getWakeupAlarm()
end

--[[--
Get RTC wakealarm from system.

Simple wrapper for @{ffi.rtc.getWakeupAlarm}.
--]]
function WakeupMgr:getWakeupAlarmSys()
    return RTC:getWakeupAlarmSys()
end

--[[--
Validate wakeup alarm.

Checks if we set the alarm.

Simple wrapper for @{ffi.rtc.validateWakeupAlarmByProximity}.
--]]
function WakeupMgr:validateWakeupAlarmByProximity(task_alarm_epoch, proximity)
    return RTC:validateWakeupAlarmByProximity(task_alarm_epoch, proximity)
end

--[[--
Check if a wakeup is scheduled.

Simple wrapper for @{ffi.rtc.isWakeupAlarmScheduled}.
--]]
function WakeupMgr:isWakeupAlarmScheduled()
    local wakeup_scheduled = RTC:isWakeupAlarmScheduled()
    if wakeup_scheduled then
        -- NOTE: This can't return nil given that we're behind an isWakeupAlarmScheduled check.
        local alarm = RTC:getWakeupAlarmEpoch()
        logger.dbg("WakeupMgr:isWakeupAlarmScheduled: An alarm is scheduled for " .. alarm .. os.date(" (%F %T %z)", alarm))
    else
        logger.dbg("WakeupMgr:isWakeupAlarmScheduled: No alarm is currently scheduled.")
    end
    return wakeup_scheduled
end

return WakeupMgr
