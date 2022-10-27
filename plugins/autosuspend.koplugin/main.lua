local Device = require("device")

-- If a device can power off or go into standby, it can also suspend ;).
if not Device:canSuspend() then
    return { disabled = true, }
end

local Event = require("ui/event")
local NetworkMgr = require("ui/network/manager")
local PluginShare = require("pluginshare")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local util = require("util")
local time = require("ui/time")
local _ = require("gettext")
local Math = require("optmath")
local T = require("ffi/util").template

local default_autoshutdown_timeout_seconds = 3*24*60*60 -- three days
local default_auto_suspend_timeout_seconds = 15*60 -- 15 minutes
local default_auto_standby_timeout_seconds = 4 -- 4 seconds; should be safe on Kobo/Sage

local AutoSuspend = WidgetContainer:extend{
    name = "autosuspend",
    is_doc_only = false,
    autoshutdown_timeout_seconds = default_autoshutdown_timeout_seconds,
    auto_suspend_timeout_seconds = default_auto_suspend_timeout_seconds,
    auto_standby_timeout_seconds = default_auto_standby_timeout_seconds,
    last_action_time = 0,
    is_standby_scheduled = nil,
    task = nil,
    standby_task = nil,
    leave_standby_task = nil,
    wrapped_leave_standby_task = nil,
    going_to_suspend = nil,
}

function AutoSuspend:_enabledStandby()
    return Device:canStandby() and self.auto_standby_timeout_seconds > 0
end

function AutoSuspend:_enabled()
    -- NOTE: Plugin is only enabled if Device:canSuspend(), so we can elide the check here
    return self.auto_suspend_timeout_seconds > 0
end

function AutoSuspend:_enabledShutdown()
    return Device:canPowerOff() and self.autoshutdown_timeout_seconds > 0
end

function AutoSuspend:_schedule(shutdown_only)
    if not self:_enabled() and not self:_enabledShutdown() then
        logger.dbg("AutoSuspend: suspend/shutdown timer is disabled")
        return
    end

    local suspend_delay_seconds, shutdown_delay_seconds
    local is_charging
    -- On devices with an auxiliary battery, we only care about the auxiliary battery being charged...
    local powerd = Device:getPowerDevice()
    if Device:hasAuxBattery() and powerd:isAuxBatteryConnected() then
        is_charging = powerd:isAuxCharging() and not powerd:isAuxCharged()
    else
        is_charging = powerd:isCharging() and not powerd:isCharged()
    end
    -- We *do* want to make sure we attempt to go into suspend/shutdown again while *fully* charged, though.
    if PluginShare.pause_auto_suspend or is_charging then
        suspend_delay_seconds = self.auto_suspend_timeout_seconds
        shutdown_delay_seconds = self.autoshutdown_timeout_seconds
    else
        local now = UIManager:getElapsedTimeSinceBoot()
        suspend_delay_seconds = self.auto_suspend_timeout_seconds - time.to_number(now - self.last_action_time)
        shutdown_delay_seconds = self.autoshutdown_timeout_seconds - time.to_number(now - self.last_action_time)
    end

    -- Try to shutdown first, as we may have been woken up from suspend just for the sole purpose of doing that.
    if self:_enabledShutdown() and shutdown_delay_seconds <= 0 then
        logger.dbg("AutoSuspend: initiating shutdown")
        UIManager:poweroff_action()
    elseif self:_enabled() and suspend_delay_seconds <= 0 and not shutdown_only then
        logger.dbg("AutoSuspend: will suspend the device")
        UIManager:suspend()
    else
        if self:_enabled() and not shutdown_only then
            logger.dbg("AutoSuspend: scheduling next suspend check in", suspend_delay_seconds)
            UIManager:scheduleIn(suspend_delay_seconds, self.task)
        end
        if self:_enabledShutdown() then
            logger.dbg("AutoSuspend: scheduling next shutdown check in", shutdown_delay_seconds)
            UIManager:scheduleIn(shutdown_delay_seconds, self.task)
        end
    end
end

function AutoSuspend:_unschedule()
    if self.task then
        logger.dbg("AutoSuspend: unschedule suspend/shutdown timer")
        UIManager:unschedule(self.task)
    end
end

function AutoSuspend:_start()
    if self:_enabled() or self:_enabledShutdown() then
        logger.dbg("AutoSuspend: start suspend/shutdown timer at", time.format_time(self.last_action_time))
        self:_schedule()
    end
end

function AutoSuspend:_start_standby()
    if self:_enabledStandby() then
        logger.dbg("AutoSuspend: start standby timer at", time.format_time(self.last_action_time))
        self:_schedule_standby()
    end
end

-- Variant that only re-engages the shutdown timer for onUnexpectedWakeupLimit
function AutoSuspend:_restart()
    if self:_enabledShutdown() then
        logger.dbg("AutoSuspend: restart shutdown timer at", time.format_time(self.last_action_time))
        self:_schedule(true)
    end
end

function AutoSuspend:init()
    logger.dbg("AutoSuspend: init")
    self.autoshutdown_timeout_seconds = G_reader_settings:readSetting("autoshutdown_timeout_seconds",
        default_autoshutdown_timeout_seconds)
    self.auto_suspend_timeout_seconds = G_reader_settings:readSetting("auto_suspend_timeout_seconds",
        default_auto_suspend_timeout_seconds)
    -- Disabled, until the user opts in.
    self.auto_standby_timeout_seconds = G_reader_settings:readSetting("auto_standby_timeout_seconds", -1)

    -- We only want those to exist as *instance* members
    self.is_standby_scheduled = false
    self.going_to_suspend = false

    UIManager.event_hook:registerWidget("InputEvent", self)
    -- We need an instance-specific function reference to schedule, because in some rare cases,
    -- we may instantiate a new plugin instance *before* tearing down the old one.
    -- If we only cared about accessing the right instance members,
    -- we could use scheduleIn(t, self.function, self),
    -- but we also care about unscheduling the task from *this* instance only:
    -- unschedule(self.function) would unschedule that function for *every* instance,
    -- as self.function == AutoSuspend.function ;).
    self.task = function(shutdown_only)
        self:_schedule(shutdown_only)
    end
    self.standby_task = function()
        self:_schedule_standby()
    end
    self.leave_standby_task = function()
        -- Only if we're not already entering suspend...
        if self.going_to_suspend then
            return
        end

        UIManager:broadcastEvent(Event:new("LeaveStandby"))
    end

    -- Make sure we only have an AllowStandby handler when we actually want one...
    self:toggleStandbyHandler(self:_enabledStandby())

    self.last_action_time = UIManager:getElapsedTimeSinceBoot()
    self:_start()
    self:_start_standby()

    -- self.ui is nil in the testsuite
    if not self.ui or not self.ui.menu then return end
    self.ui.menu:registerToMainMenu(self)
end

-- NOTE: event_hook takes care of overloading this to unregister the hook, too.
function AutoSuspend:onCloseWidget()
    logger.dbg("AutoSuspend: onCloseWidget")

    self:_unschedule()
    self.task = nil

    self:_unschedule_standby()
    self.standby_task = nil
    self.leave_standby_task = nil
end

function AutoSuspend:onInputEvent()
    logger.dbg("AutoSuspend: onInputEvent")
    self.last_action_time = UIManager:getElapsedTimeSinceBoot()
end

function AutoSuspend:_unschedule_standby()
    if self.is_standby_scheduled and self.standby_task then
        logger.dbg("AutoSuspend: unschedule standby timer")
        UIManager:unschedule(self.standby_task)
        -- Restore the UIManager balance, as we run preventStandby right after scheduling this task.
        UIManager:allowStandby()

        self.is_standby_scheduled = false
    end

    -- Make sure we don't trigger a ghost LeaveStandby event...
    if self.leave_standby_task then
        logger.dbg("AutoSuspend: unschedule leave standby task")
        UIManager:unschedule(self.leave_standby_task)
    end
end

function AutoSuspend:_schedule_standby()
    -- Start the long list of conditions in which we do *NOT* want to go into standby ;).
    if not Device:canStandby() then
        return
    end

    -- Don't even schedule standby if we haven't set a proper timeout yet.
    -- NOTE: We've essentially split the _enabledStandby check in two branches,
    --       simply to avoid logging noise on devices that can't even standby ;).
    if self.auto_standby_timeout_seconds <= 0 then
        logger.dbg("AutoSuspend: No timeout set, no standby")
        return
    end

    -- When we're in a state where entering suspend is undesirable, we simply postpone the check by the full delay.
    local standby_delay_seconds
    -- NOTE: As this may fire repeatedly, we don't want to poke the actual Device implementation every few seconds,
    --       instead, we rely on NetworkMgr's last known status. (i.e., this *should* match NetworkMgr:isWifiOn).
    if NetworkMgr:getWifiState() then
        -- Don't enter standby if wifi is on, as this will break in fun and interesting ways (from Wi-Fi issues to kernel deadlocks).
        --logger.dbg("AutoSuspend: WiFi is on, delaying standby")
        standby_delay_seconds = self.auto_standby_timeout_seconds
    elseif Device.powerd:isCharging() and not Device:canPowerSaveWhileCharging() then
        -- Don't enter standby when charging on devices where charging *may* prevent entering low power states.
        -- (*May*, because depending on the USB controller, it might depend on what it's plugged to, and how it's setup:
        -- e.g., generally, on those devices, USBNet being enabled is guaranteed to prevent PM).
        -- NOTE: Minor simplification here, we currently don't do the hasAuxBattery dance like in _schedule,
        --       because all the hasAuxBattery devices can currently enter PM states while charging ;).
        --logger.dbg("AutoSuspend: charging, delaying standby")
        standby_delay_seconds = self.auto_standby_timeout_seconds
    else
        local now = UIManager:getElapsedTimeSinceBoot()
        standby_delay_seconds = self.auto_standby_timeout_seconds - time.to_number(now - self.last_action_time)

        -- If we blow past the deadline on the first call of a scheduling cycle,
        -- make sure we don't go straight to allowStandby, as we haven't called preventStandby yet...
        if not self.is_standby_scheduled and standby_delay_seconds <= 0 then
            -- If this happens, it means we hit LeaveStandby or Resume *before* consuming new input events,
            -- e.g., if there weren't any input events at all (woken up by an alarm),
            -- or if the only input events we consumed did not trigger an InputEvent event (woken up by gyro events),
            -- meaning self.last_action_time is further in the past than it ought to.
            -- Delay by the full amount to avoid further bad scheduling interactions.
            standby_delay_seconds = self.auto_standby_timeout_seconds
        end
    end

    if standby_delay_seconds <= 0 then
        -- We blew the deadline, tell UIManager we're ready to enter standby
        self:allowStandby()
    else
        -- Reschedule standby for the full or remaining delay
        -- NOTE: This is fairly chatty, given the low delays, but really helpful nonetheless... :/
        logger.dbg("AutoSuspend: scheduling next standby check in", standby_delay_seconds)
        UIManager:scheduleIn(standby_delay_seconds, self.standby_task)

        -- Prevent standby until we actually blow the deadline
        if not self.is_standby_scheduled then
            self:preventStandby()
        end

        self.is_standby_scheduled = true
    end
end

function AutoSuspend:preventStandby()
    logger.dbg("AutoSuspend: preventStandby")
    -- Tell UIManager that we want to prevent standby until our allowStandby scheduled task runs.
    UIManager:preventStandby()
end

-- NOTE: This is what our scheduled task runs to trip the UIManager state to standby
function AutoSuspend:allowStandby()
    logger.dbg("AutoSuspend: allowStandby")
    -- Tell UIManager that we now allow standby.
    UIManager:allowStandby()

    -- We've just run our course.
    self.is_standby_scheduled = false
end

function AutoSuspend:onSuspend()
    logger.dbg("AutoSuspend: onSuspend")
    -- We do not want auto suspend procedure to waste battery during suspend. So let's unschedule it
    -- when suspending and restart it after resume.
    self:_unschedule()
    self:_unschedule_standby()
    if self:_enabledShutdown() and Device.wakeup_mgr then
        Device.wakeup_mgr:addTask(self.autoshutdown_timeout_seconds, UIManager.poweroff_action)
    end

    -- Make sure we won't attempt to standby during suspend
    -- (because _unschedule_standby calls allowStandby,
    -- so we may trip UIManager's _standbyTransition and end up in AutoSuspend:onAllowStandby)...
    -- NOTE: We only want to do this *once*, because we might get a series of Suspend events before actually getting a Resume!
    --       (e.g., Power (button) -> Charging (USB plug) -> SleepCover).
    if self:_enabledStandby() and not self.going_to_suspend then
        UIManager:preventStandby()
    end

    -- And make sure onLeaveStandby, which will come *after* us if we suspended *during* standby,
    -- won't re-schedule stuff right before entering suspend...
    self.going_to_suspend = true
end

function AutoSuspend:onResume()
    logger.dbg("AutoSuspend: onResume")

    -- Restore standby balance after onSuspend
    if self:_enabledStandby() and self.going_to_suspend then
        UIManager:allowStandby()
    end
    self.going_to_suspend = false

    if self:_enabledShutdown() and Device.wakeup_mgr then
        Device.wakeup_mgr:removeTasks(nil, UIManager.poweroff_action)
    end
    -- Unschedule in case we tripped onUnexpectedWakeupLimit first...
    self:_unschedule()
    -- We should always follow an InputEvent, so last_action_time is already up to date :).
    self:_start()
    self:_unschedule_standby()
    self:_start_standby()
end

function AutoSuspend:onLeaveStandby()
    logger.dbg("AutoSuspend: onLeaveStandby")
    -- Unschedule suspend and shutdown, as the realtime clock has ticked
    self:_unschedule()
    -- Reschedule suspend and shutdown (we'll recompute the delay based on the last user input, *not* the current time).
    -- i.e., the goal is to behave as if we'd never unscheduled it, making sure we do *NOT* reset the delay to the full timeout.
    self:_start()
    -- Assuming _start didn't send us straight to onSuspend (i.e., we were woken from standby by the scheduled suspend task!)...
    if not self.going_to_suspend then
        -- Reschedule standby, too (we're guaranteed that no standby task is currently scheduled, hence the lack of unscheduling).
        self:_start_standby()
    end
end

function AutoSuspend:onUnexpectedWakeupLimit()
    logger.dbg("AutoSuspend: onUnexpectedWakeupLimit")
    -- Should be unnecessary, because we should *always* follow onSuspend, which already does this...
    -- Better safe than sorry, though ;).
    self:_unschedule()
    -- Only re-engage the *shutdown* schedule to avoid doing the same dance indefinitely.
    self:_restart()
end

function AutoSuspend:onNotCharging()
    logger.dbg("AutoSuspend: onNotCharging")
    -- Make sure both the suspend & shutdown timers are re-engaged on unplug,
    -- in case we hit an UnexpectedWakeupLimit during the charge cycle...
    self:_unschedule()
    self:_start()
end

-- time_scale:
-- 2 ... display day:hour
-- 1 ... display hour:min
-- else ... display min:sec
function AutoSuspend:pickTimeoutValue(touchmenu_instance, title, info, setting,
        default_value, range, time_scale)
    -- NOTE: if is_day_hour then time.hour stands for days and time.min for hours

    local InfoMessage = require("ui/widget/infomessage")
    local DateTimeWidget = require("ui/widget/datetimewidget")

    local setting_val = self[setting] > 0 and self[setting] or default_value

    -- Standby uses a different scheduled task than suspend/shutdown
    local is_standby = setting == "auto_standby_timeout_seconds"

    local day, hour, minute, second
    local day_max, hour_max, min_max, sec_max
    if time_scale == 2 then
        day = math.floor(setting_val * (1/(24*3600)))
        hour = math.floor(setting_val * (1/3600)) % 24
        day_max = math.floor(range[2] * (1/(24*3600))) - 1
        hour_max = 23
    elseif time_scale == 1 then
        hour = math.floor(setting_val * (1/3600))
        minute = math.floor(setting_val * (1/60)) % 60
        hour_max = math.floor(range[2] * (1/3600)) - 1
        min_max = 59
    else
        minute = math.floor(setting_val * (1/60))
        second = math.floor(setting_val) % 60
        min_max =  math.floor(range[2] * (1/60)) - 1
        sec_max = 59
    end

    local time_spinner
    time_spinner = DateTimeWidget:new {
        day = day,
        hour = hour,
        min = minute,
        sec = second,
        day_hold_step = 5,
        hour_hold_step = 5,
        min_hold_step = 10,
        sec_hold_step = 10,
        day_max = day_max,
        hour_max = hour_max,
        min_max = min_max,
        sec_max = sec_max,
        ok_text = _("Set timeout"),
        title_text = title,
        info_text = info,
        callback = function(t)
            self[setting] = (((t.day or 0) * 24 +
                             (t.hour or 0)) * 60 +
                             (t.min or 0)) * 60 +
                             (t.sec or 0)
            self[setting] = Math.clamp(self[setting], range[1], range[2])
            G_reader_settings:saveSetting(setting, self[setting])
            if is_standby then
                self:_unschedule_standby()
                self:toggleStandbyHandler(self:_enabledStandby())
                self:_start_standby()
            else
                self:_unschedule()
                self:_start()
            end
            if touchmenu_instance then touchmenu_instance:updateItems() end
            local time_string = util.secondsToClockDuration("modern", self[setting],
                time_scale == 2 or time_scale == 1, true, true)
            UIManager:show(InfoMessage:new{
                text = T(_("%1: %2"), title, time_string),
                timeout = 3,
            })
        end,
        default_value = util.secondsToClockDuration("modern", default_value,
            time_scale == 2 or time_scale == 1, true, true),
        default_callback = function()
            local day, hour, min, sec -- luacheck: ignore 431
            if time_scale == 2 then
                day = math.floor(default_value * (1/(24*3600)))
                hour = math.floor(default_value * (1/3600)) % 24
            elseif time_scale == 1 then
                hour = math.floor(default_value * (1/3600))
                min = math.floor(default_value * (1/60)) % 60
            else
                min = math.floor(default_value * (1/60))
                sec = math.floor(default_value % 60)
            end
            time_spinner:update(nil, nil, day, hour, min, sec) -- It is ok to pass nils here.
        end,
        extra_text = _("Disable"),
        extra_callback = function(this)
            self[setting] = -1 -- disable with a negative time/number
            G_reader_settings:saveSetting(setting, -1)
            if is_standby then
                self:_unschedule_standby()
                self:toggleStandbyHandler(false)
            else
                self:_unschedule()
            end
            if touchmenu_instance then touchmenu_instance:updateItems() end
            UIManager:show(InfoMessage:new{
                text = T(_("%1: disabled"), title),
                timeout = 3,
            })
            this:onClose()
        end,
        keep_shown_on_apply = true,
    }
    UIManager:show(time_spinner)
end

function AutoSuspend:addToMainMenu(menu_items)
    -- Device:canSuspend() check elided because it's a plugin requirement
    menu_items.autosuspend = {
        sorting_hint = "device",
        checked_func = function()
            return self:_enabled()
        end,
        text_func = function()
            if self.auto_suspend_timeout_seconds and self.auto_suspend_timeout_seconds > 0 then
                local time_string = util.secondsToClockDuration("modern",
                    self.auto_suspend_timeout_seconds, true, true, true)
                return T(_("Autosuspend timeout: %1"), time_string)
            else
                return _("Autosuspend timeout")
            end
        end,
        keep_menu_open = true,
        callback = function(touchmenu_instance)
            -- 60 sec (1') is the minimum and 24*3600 sec (1day) is the maximum suspend time.
            -- A suspend time of one day seems to be excessive.
            -- But it might make sense for battery testing.
            self:pickTimeoutValue(touchmenu_instance,
                _("Timeout for autosuspend"), _("Enter time in hours and minutes."),
                "auto_suspend_timeout_seconds", default_auto_suspend_timeout_seconds,
                {60, 24*3600}, 1)
        end,
    }
    if Device:canPowerOff() then
        menu_items.autoshutdown = {
            sorting_hint = "device",
            checked_func = function()
                return self:_enabledShutdown()
            end,
            text_func = function()
                if self.autoshutdown_timeout_seconds and self.autoshutdown_timeout_seconds > 0 then
                    local time_string = util.secondsToClockDuration("modern", self.autoshutdown_timeout_seconds,
                        true, true, true)
                    return T(_("Autoshutdown timeout: %1"), time_string)
                else
                    return _("Autoshutdown timeout")
                end
            end,
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                -- 5*60 sec (5') is the minimum and 28*24*3600 (28days) is the maximum shutdown time.
                -- Minimum time has to be big enough, to avoid start-stop death scenarious.
                -- Maximum more than four weeks seems a bit excessive if you want to enable authoshutdown,
                -- even if the battery can last up to three months.
                self:pickTimeoutValue(touchmenu_instance,
                    _("Timeout for autoshutdown"), _("Enter time in days and hours."),
                    "autoshutdown_timeout_seconds", default_autoshutdown_timeout_seconds,
                    {5*60, 28*24*3600}, 2)
            end,
        }
    end
    if Device:canStandby() then
        local standby_help = _([[Standby puts the device into a power-saving state in which the screen is on and user input can be performed.

Standby can not be entered if Wi-Fi is on.

Upon user input, the device needs a certain amount of time to wake up. Generally, the newer the device, the less noticeable this delay will be, but it can be fairly aggravating on slower devices.]])
        -- Add a big fat warning on unreliable NTX boards
        if Device:isKobo() and not Device:hasReliableMxcWaitFor() then
            standby_help = standby_help .. "\n" ..
                           _([[Your device is known to be extremely unreliable, as such, failure to enter a power-saving state *may* hang the kernel, resulting in a full device hang or a device restart.]])
        end

        menu_items.autostandby = {
            sorting_hint = "device",
            checked_func = function()
                return self:_enabledStandby()
            end,
            text_func = function()
                if self.auto_standby_timeout_seconds and self.auto_standby_timeout_seconds > 0 then
                    local time_string = util.secondsToClockDuration("modern", self.auto_standby_timeout_seconds,
                        false, true, true, true)
                    return T(_("Autostandby timeout: %1"), time_string)
                else
                    return _("Autostandby timeout")
                end
            end,
            help_text = standby_help,
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                -- 4 sec is the minimum and 15*60 sec (15min) is the maximum standby time.
                -- We need a minimum time, so that scheduled function have a chance to execute.
                -- A standby time of 15 min seem excessive.
                -- But or battery testing it might give some sense.
                self:pickTimeoutValue(touchmenu_instance,
                    _("Timeout for autostandby"), _("Enter time in minutes and seconds."),
                    "auto_standby_timeout_seconds", default_auto_standby_timeout_seconds,
                    {3, 15*60}, 0)
            end,
        }
    end
end

-- KOReader is merely waiting for user input right now.
-- UI signals us that standby is allowed at this very moment because nothing else goes on in the background.
-- NOTE: To make sure this will not even run when autostandby is disabled,
--       this is only aliased as `onAllowStandby` when necessary.
--       (Because the Event is generated regardless of us, as many things can call UIManager:allowStandby).
function AutoSuspend:AllowStandbyHandler()
    logger.dbg("AutoSuspend: onAllowStandby")
    -- This piggy-backs minimally on the UI framework implemented for the PocketBook autostandby plugin,
    -- see its own AllowStandby handler for more details.

    local wake_in
    -- Wake up before the next scheduled function executes (e.g. footer update, suspend ...)
    local next_task_time = UIManager:getNextTaskTime()
    if next_task_time then
        -- Wake up slightly after the formerly scheduled event,
        -- to avoid resheduling the same function after a fraction of a second again (e.g. don't draw footer twice).
        wake_in = math.floor(time.to_number(next_task_time)) + 1
    else
        wake_in = math.huge
    end

    if wake_in >= 3 then -- don't go into standby, if scheduled wakeup is in less than 3 secs
        UIManager:broadcastEvent(Event:new("EnterStandby"))
        logger.dbg("AutoSuspend: entering standby with a wakeup alarm in", wake_in, "s")

        -- This obviously needs a matching implementation in Device, the canonical one being Kobo.
        Device:standby(wake_in)

        logger.dbg("AutoSuspend: left standby after", time.format_time(Device.last_standby_time), "s")

        -- We delay the LeaveStandby event (our onLeaveStandby handler is responsible for rescheduling everything properly),
        -- to make sure UIManager will consume the input events that woke us up first
        -- (in case we were woken up by user input, as opposed to an rtc wake alarm)!
        -- (This ensures we'll use an up to date last_action_time, and that it only ever gets updated from *user* input).
        -- NOTE: While UIManager consumes scheduled tasks before input events, we do *NOT* have to rely on tickAfterNext,
        --       solely because of where we run inside an UI frame (via UIManager:_standbyTransition):
        --       we're neither a scheduled task nor an input event, we run *between* scheduled tasks and input polling.
        --       That means we go straight to input polling when returning, *without* a trip through the task queue
        --       (c.f., UIManager:_checkTasks in UIManager:handleInput).
        UIManager:nextTick(self.leave_standby_task)

        -- Since we go straight to input polling, and that our time spent in standby won't have affected the already computed
        -- input polling deadline (because MONOTONIC doesn't tick during standby/suspend),
        -- tweak said deadline to make sure poll will return immediately, so we get a chance to run through the task queue ASAP.
        -- This ensures we get a LeaveStandby event in a timely fashion,
        -- even when there isn't actually any user input happening (e.g., woken up by the rtc alarm).
        -- This shouldn't prevent us from actually consuming any pending input events first,
        -- because if we were woken up by user input, those events should already be in the evdev queue...
        UIManager:consumeInputEarlyAfterPM(true)
    else
        if not self.going_to_suspend then
            self:_start_standby()
        end
    end
end

function AutoSuspend:toggleStandbyHandler(toggle)
    if toggle then
        self.onAllowStandby = self.AllowStandbyHandler
    else
        self.onAllowStandby = nil
    end
end

return AutoSuspend
