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
    _task_queue = nil,      -- Table with epoch at which to schedule the task and the function to be scheduled.
    rtc = RTC, -- The RTC implementation to use, defaults to the RTC module.
    dodgy_rtc = false, -- If the RTC has trouble with timers further away than UINT16_MAX (e.g., on i.MX5).
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

function WakeupMgr:init()
    self._task_queue = {}

    -- Propagate rtc quirks to the RTC backend
    self.rtc.dev_rtc = self.dev_rtc
    self.rtc.dodgy_rtc = self.dodgy_rtc
end

-- This is a dummy task we use when working around i.MX5 RTC issues.
-- We need to be able to recognize it so that we can deal with it in removeTasks...
function WakeupMgr.DummyTaskCallback()
end

--[[--
Add a task to the queue.

@todo Group by type to avoid useless wakeups.
For example, maintenance, sync, and shutdown.
I'm not sure if the distinction between maintenance and sync makes sense
but it's wifi on vs. off.
--]]
function WakeupMgr:addTask(seconds_from_now, callback)
    -- Make sure we passed valid input, so that stuff doesn't break in fun and interesting ways (especially in removeTasks).
    assert(type(seconds_from_now) == "number", "delay is not a number")
    assert(type(callback) == "function", "callback is not a function")

    local old_upcoming_task = (self._task_queue[1] or {}).epoch

    -- NOTE: Apparently, some RTCs have trouble with timers further away than UINT16_MAX, so,
    --       if necessary, setup an alarm chain to work it around...
    --       c.f., https://github.com/koreader/koreader/issues/8039#issuecomment-1263547625
    if self.dodgy_rtc and seconds_from_now > 0xFFFF then
        logger.info("WakeupMgr: scheduling a chain of alarms for a wakeup in", seconds_from_now)

        local seconds_left = seconds_from_now
        while seconds_left > 0 do
            local epoch = RTC:secondsFromNowToEpoch(seconds_left)
            logger.info("WakeupMgr: scheduling wakeup in", seconds_left, "->", epoch)

            -- We only need a callback for the final wakeup, we take care of not breaking the chain when an action is pop'ed.
            table.insert(self._task_queue, {
                epoch = epoch,
                callback = seconds_left == seconds_from_now and callback or self.DummyTaskCallback,
            })

            seconds_left = seconds_left - 0xFFFF
        end
    else
        local epoch = RTC:secondsFromNowToEpoch(seconds_from_now)
        logger.info("WakeupMgr: scheduling wakeup in", seconds_from_now, "->", epoch)

        table.insert(self._task_queue, {
            epoch = epoch,
            callback = callback,
        })
    end

    table.sort(self._task_queue, function(a, b) return a.epoch < b.epoch end)

    local new_upcoming_task = self._task_queue[1].epoch
    if not old_upcoming_task or (new_upcoming_task < old_upcoming_task) then
        self:setWakeupAlarm(new_upcoming_task)
    end
end

--[[--
Remove task(s) from queue.

This method removes one or more tasks by either scheduled time or callback.
If any tasks are left on exit, the upcoming one will automatically be scheduled (if necessary).

@int epoch The epoch for when this task is scheduled to wake up.
Normally the preferred method for outside callers.
@int callback A scheduled callback function. Store a reference for use
with anonymous functions.
@treturn bool (true if one or more tasks were removed; false otherwise; nil if the task queue is empty).
--]]
function WakeupMgr:removeTasks(epoch, callback)
    if #self._task_queue == 0 then return end

    local removed = false
    local reschedule = false
    local match_epoch = epoch
    for k = #self._task_queue, 1, -1 do
        local v = self._task_queue[k]
        -- NOTE: For the DummyTaskCallback shenanigans, we at least try to only remove those that come earlier than our match...
        if (epoch == v.epoch or callback == v.callback) or
           (self.dodgy_rtc and match_epoch and self.DummyTaskCallback == v.callback and v.epoch < match_epoch) then
            if not match_epoch then
                match_epoch = v.epoch
            end
            table.remove(self._task_queue, k)
            removed = true
            -- If we've successfully pop'ed the upcoming task, we need to schedule the next one (if any) on exit.
            if k == 1 then
                reschedule = true
            end
        end
    end

    -- Schedule the next wakeup action, if any (and if necessary).
    if reschedule and self._task_queue[1] then
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

    -- Schedule the next wakeup action, if any (and if necessary).
    if removed and idx == 1 and self._task_queue[1] then
        self:setWakeupAlarm(self._task_queue[1].epoch)
    end

    return removed
end

--[[--
Execute wakeup action.

This method should be called by the device resume logic in case of a scheduled wakeup.

It checks if the wakeup was scheduled by us using @{validateWakeupAlarmByProximity},
in which case the task is executed.

If necessary, the next upcoming task (if any) is scheduled on exit.

@int proximity Proximity window to the scheduled wakeup (passed to @{validateWakeupAlarmByProximity}).
@treturn bool (true if we were truly woken up by the scheduled wakeup; false otherwise; nil if there weren't any tasks scheduled).
--]]
function WakeupMgr:wakeupAction(proximity)
    if self._task_queue[1] then
        local task = self._task_queue[1]
        if self:validateWakeupAlarmByProximity(task.epoch, proximity) then
            task.callback()
            -- NOTE: removeTask will take care of scheduling the next upcoming task, if necessary.
            self:removeTask(1)

            return true
        end

        return false
    end

    return nil
end

--[[--
Set wakeup alarm.

Simple wrapper for @{ffi.rtc.setWakeupAlarm}.
--]]
function WakeupMgr:setWakeupAlarm(epoch, enabled)
    logger.dbg("WakeupMgr:setWakeupAlarm for", epoch, os.date("(%F %T %z)", epoch))
    return self.rtc:setWakeupAlarm(epoch, enabled)
end

--[[--
Unset wakeup alarm.

Simple wrapper for @{ffi.rtc.unsetWakeupAlarm}.
--]]
function WakeupMgr:unsetWakeupAlarm()
    -- Apparently, toggling the interrupt doesn't work on some RTCs,
    -- and not necessarily the ones we've flagged as dodgy... (#10031).
    -- Deal with this insanity by ensuring the alarm is not set in the future,
    -- by overwriting the current alarm with an already expired disabled one.
    logger.dbg("WakeupMgr:unsetWakeupAlarm will invalidate any future alarms")
    self:setWakeupAlarm(0, false)
    return self.rtc:unsetWakeupAlarm()
end

--[[--
Get wakealarm as set by us.

Simple wrapper for @{ffi.rtc.getWakeupAlarm}.
--]]
function WakeupMgr:getWakeupAlarm()
    return self.rtc:getWakeupAlarm()
end

--[[--
Get wakealarm epoch as set by us.

Simple wrapper for @{ffi.rtc.getWakeupAlarmEpoch}.
--]]
function WakeupMgr:getWakeupAlarmEpoch()
    return self.rtc:getWakeupAlarmEpoch()
end

--[[--
Get RTC wakealarm from system.

Simple wrapper for @{ffi.rtc.getWakeupAlarmSys}.
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
    return self.rtc:validateWakeupAlarmByProximity(task_alarm_epoch, proximity)
end

--[[--
Check if a wakeup is scheduled.

Simple wrapper for @{ffi.rtc.isWakeupAlarmScheduled}.
--]]
function WakeupMgr:isWakeupAlarmScheduled()
    local wakeup_scheduled = self.rtc:isWakeupAlarmScheduled()
    if wakeup_scheduled then
        -- NOTE: This can't return nil given that we're behind an isWakeupAlarmScheduled check.
        local alarm = self.rtc:getWakeupAlarmEpoch()
        logger.dbg("WakeupMgr:isWakeupAlarmScheduled: An alarm is scheduled for " .. alarm .. os.date(" (%F %T %z)", alarm))
    else
        logger.dbg("WakeupMgr:isWakeupAlarmScheduled: No alarm is currently scheduled.")
    end
    return wakeup_scheduled
end

return WakeupMgr
