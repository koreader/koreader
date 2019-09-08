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
    _task_queue = {},
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
    if not type(seconds_from_now) == "number" and not type(callback) == "function" then return end

    local epoch = RTC:secondsFromNowToEpoch(seconds_from_now)

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
Remove task from queue.

This method removes a task by either index, scheduled time or callback.

@int idx Task queue index. Mainly useful within this module.
@int epoch The epoch for when this task is scheduled to wake up.
Normally the preferred method for outside callers.
@int callback A scheduled callback function. Store a reference for use
with anonymous functions.
--]]
function WakeupMgr:removeTask(idx, epoch, callback)
    if not type(idx) == "number"
        and not type(epoch) == "number"
        and not type(callback) == "function" then return end

    if #self._task_queue < 1 then return end

    for k, v in ipairs(self._task_queue) do
        if k == idx or epoch == v.epoch or callback == v.callback then
            table.remove(self._task_queue, k)
            return true
        end
    end
end

function WakeupMgr:wakeupAction()
    if #self._task_queue > 0 then
        local task = self._task_queue[1]
        if self:validateWakeupAlarmByProximity(task.epoch) then
            task.callback()
            --- @todo use self:removeTask
            --table.remove(self._task_queue, 1)
            self:removeTask(1)
            return true
        else
            return false
        end
    end
end

function WakeupMgr:setWakeupAlarm(seconds_from_now, enabled)
    return RTC:setWakeupAlarm(seconds_from_now, enabled)
end

function WakeupMgr:unsetWakeupAlarm()
    return RTC:unsetWakeupAlarm()
end

--- Get wakealarm as set by us.
function WakeupMgr:getWakeupAlarm()
    return RTC:getWakeupAlarm()
end

--- Get RTC wakealarm from system.
function WakeupMgr:getWakeupAlarmSys()
    return RTC:getWakeupAlarmSys()
end

function WakeupMgr:validateWakeupAlarmByProximity()
    return RTC:validateWakeupAlarmByProximity()
end

function WakeupMgr:isWakeupAlarmScheduled()
    local wakeup_scheduled = RTC:isWakeupAlarmScheduled()
    logger.dbg("isWakeupAlarmScheduled", wakeup_scheduled)
    return wakeup_scheduled
end

return WakeupMgr
