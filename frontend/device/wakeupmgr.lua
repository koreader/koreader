--[[--
RTC wakeup interface.

Many devices can schedule hardware wakeups with a real time clock alarm.
On embedded devices this can typically be easily manipulated by the user
through `/sys/class/rtc/rtc0/wakealarm`. Some, like the Kobo Aura H2O,
can only schedule wakeups through ioctl.

See also: <https://linux.die.net/man/4/rtc>.
--]]

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
--]]
function WakeupMgr:addTask(task_epoch, task_function)
    table.insert(self._task_queue, {
        task_epoch = task_epoch,
        task_function = task_function,
    })
    --- @todo Binary insert? This table should be so small that performance doesn't matter.
    -- It might be useful to have available as a utility function regardless.
    table.sort(self._task_queue)
end

return WakeupMgr
