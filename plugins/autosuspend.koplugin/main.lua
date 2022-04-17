local Device = require("device")

if not Device:isCervantes() and
    not Device:isKindle() and
    not Device:isKobo() and
    not Device:isRemarkable() and
    not Device:isSDL() and
    not Device:isSonyPRSTUX() and
    not Device:isPocketBook() then
    return { disabled = true, }
end

local Event = require("ui/event")
local NetworkMgr = require("ui/network/manager")
local PluginShare = require("pluginshare")
local TimeVal = require("ui/timeval")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local Math = require("optmath")
local T = require("ffi/util").template

local default_autoshutdown_timeout_seconds = 3*24*60*60 -- three days
local default_auto_suspend_timeout_seconds = 15*60 -- 15 minutes
local default_auto_standby_timeout_seconds = 4 -- 4 seconds; should be safe on Kobo/Sage

local AutoSuspend = WidgetContainer:new{
    name = "autosuspend",
    is_doc_only = false,
    autoshutdown_timeout_seconds = default_autoshutdown_timeout_seconds,
    auto_suspend_timeout_seconds = default_auto_suspend_timeout_seconds,
    auto_standby_timeout_seconds = default_auto_standby_timeout_seconds,
    last_action_tv = TimeVal.zero,
    is_standby_scheduled = false,
    task = nil,
    standby_task = nil,
    pause_auto_standby = false,
}

function AutoSuspend:_enabledStandby()
    return Device:canStandby() and self.auto_standby_timeout_seconds > 0
end

function AutoSuspend:_enabled()
    return self.auto_suspend_timeout_seconds > 0
end

function AutoSuspend:_enabledShutdown()
    return Device:canPowerOff() and self.autoshutdown_timeout_seconds > 0
end

function AutoSuspend:_updateLastAction()
    logger.dbg("AutoSuspend: _updateLastAction prologue, last action @", self.last_action_tv:tonumber())
    self.last_action_tv = UIManager:getElapsedTimeSinceBoot()
    logger.dbg("AutoSuspend: _updateLastAction coda, @", self.last_action_tv:tonumber())
end

function AutoSuspend:_schedule(shutdown_only)
    if not self:_enabled() and Device:canPowerOff() and not self:_enabledShutdown() then
        logger.dbg("AutoSuspend:_schedule is disabled")
        return
    end

    local suspend_delay, shutdown_delay
    local is_charging
    -- On devices with an auxiliary battery, we only care about the auxiliary battery being charged...
    local powerd = Device:getPowerDevice()
    if Device:hasAuxBattery() and powerd:isAuxBatteryConnected() then
        is_charging = powerd:isAuxCharging()
    else
        is_charging = powerd:isCharging()
    end
    if PluginShare.pause_auto_suspend or is_charging then
        suspend_delay = self.auto_suspend_timeout_seconds
        shutdown_delay = self.autoshutdown_timeout_seconds
    else
        local now_tv = UIManager:getElapsedTimeSinceBoot()
        suspend_delay = self.auto_suspend_timeout_seconds - (now_tv - self.last_action_tv):tonumber()
        shutdown_delay = self.autoshutdown_timeout_seconds - (now_tv - self.last_action_tv):tonumber()
    end

    -- Try to shutdown first, as we may have been woken up from suspend just for the sole purpose of doing that.
    if self:_enabledShutdown() and shutdown_delay <= 0 then
        logger.dbg("AutoSuspend: initiating shutdown")
        UIManager:poweroff_action()
    elseif self:_enabled() and suspend_delay <= 0 and not shutdown_only then
        logger.dbg("AutoSuspend: will suspend the device")
        UIManager:suspend()
    else
        if self:_enabled() and not shutdown_only then
            logger.dbg("AutoSuspend: scheduling next suspend check in", suspend_delay)
            UIManager:scheduleIn(suspend_delay, self.task)
        end
        if self:_enabledShutdown() then
            logger.dbg("AutoSuspend: scheduling next shutdown check in", shutdown_delay)
            UIManager:scheduleIn(shutdown_delay, self.task)
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
        logger.dbg("AutoSuspend: start suspend/shutdown timer at", self.last_action_tv:tonumber())
        self:_schedule()
    end
end

function AutoSuspend:_start_standby()
    if self:_enabledStandby() then
        logger.dbg("AutoSuspend: start standby timer at", self.last_action_tv:tonumber())
        self:_schedule_standby()
    end
end

-- Variant that only re-engages the shutdown timer for onUnexpectedWakeupLimit
function AutoSuspend:_restart()
    if self:_enabledShutdown() then
        logger.dbg("AutoSuspend: restart shutdown timer at", self.last_action_tv:tonumber())
        self:_schedule(true)
    end
end

function AutoSuspend:init()
    logger.dbg("AutoSuspend: init")
    if Device:isPocketBook() and not Device:canSuspend() then return end

    self.autoshutdown_timeout_seconds = G_reader_settings:readSetting("autoshutdown_timeout_seconds",
        default_autoshutdown_timeout_seconds)
    self.auto_suspend_timeout_seconds = G_reader_settings:readSetting("auto_suspend_timeout_seconds",
        default_auto_suspend_timeout_seconds)

    -- Disabled, until the user opts in.
    self.auto_standby_timeout_seconds = G_reader_settings:readSetting("auto_standby_timeout_seconds", -1)

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

    self:_updateLastAction()
    self:_start()
    self:_start_standby()

    -- self.ui is nil in the testsuite
    if not self.ui or not self.ui.menu then return end
    self.ui.menu:registerToMainMenu(self)
end

-- For event_hook automagic deregistration purposes
function AutoSuspend:onCloseWidget()
    logger.dbg("AutoSuspend: onCloseWidget")
    if Device:isPocketBook() and not Device:canSuspend() then return end

    self:_unschedule()
    self.task = nil

    self:_unschedule_standby()
    self.standby_task = nil
end

function AutoSuspend:onInputEvent()
    logger.dbg("AutoSuspend: onInputEvent")
    self:_updateLastAction()
end

function AutoSuspend:_unschedule_standby()
    if self.is_standby_scheduled and self.standby_task then
        logger.dbg("AutoSuspend: unschedule standby timer")
        UIManager:unschedule(self.standby_task)
        -- Restore the UIManager balance, as we run preventStandby right after scheduling this task.
        UIManager:allowStandby()

        self.is_standby_scheduled = false
    end
end

function AutoSuspend:_schedule_standby()
    -- Start the long list of conditions in which we do *NOT* want to go into standby ;).
    if not Device:canStandby() then
        -- NOTE: This partly duplicates what `_enabledStandby` does,
        --       but it's here to avoid logging noise on devices that can't even standby ;).
        return
    end

    -- Don't even schedule standby if we haven't set a proper timeout yet.
    if not self:_enabledStandby() then
        logger.dbg("AutoSuspend: No timeout set, no standby")
        return
    end

    -- When we're in a state where entering suspend is undesirable, we simply postpone the check by the full delay.
    local standby_delay
    if NetworkMgr:isWifiOn() then
        -- Don't enter standby if wifi is on, as this will break in fun and interesting ways (from Wi-Fi issues to kernel deadlocks).
        --logger.dbg("AutoSuspend: WiFi is on, delaying standby")
        standby_delay = self.auto_standby_timeout_seconds
    elseif Device.powerd:isCharging() and not Device:canPowerSaveWhileCharging() then
        -- Don't enter standby when charging on devices where charging prevents entering low power states.
        -- NOTE: Minor simplification here, we currently don't do the hasAuxBattery dance like in _schedule,
        --       because all the hasAuxBattery devices can currently enter PM states while charging ;).
        --logger.dbg("AutoSuspend: charging, delaying standby")
        standby_delay = self.auto_standby_timeout_seconds
    else
        local now_tv = UIManager:getElapsedTimeSinceBoot()
        standby_delay = self.auto_standby_timeout_seconds - (now_tv - self.last_action_tv):tonumber()

        -- If we somehow blow past the deadline on the first call of a scheduling cycle,
        -- make sure we don't go straight to allowStandby, as we haven't called preventStandby yet...
        -- (This shouldn't really ever happen, unless something is going seriously wrong somewhere).
        if not self.is_standby_scheduled and standby_delay <= 0 then
            standby_delay = 0.001
        end
    end

    if standby_delay <= 0 then
        -- We blew the deadline, tell UIManager we're ready to enter standby
        self:allowStandby()
    else
        -- Reschedule standby for the full or remaining delay
        -- NOTE: This is fairly chatty, given the low delays, but really helpful nonetheless... :/
        logger.dbg("AutoSuspend: scheduling next standby check in", standby_delay)
        UIManager:scheduleIn(standby_delay, self.standby_task)

        -- Prevent standby until we actually blow the deadline
        if not self.is_standby_scheduled then
            self:preventStandby()
        end

        self.is_standby_scheduled = true
    end
end

function AutoSuspend:preventStandby()
    -- Tell UIManager that we want to prevent standby until our allowStandby scheduled task runs.
    UIManager:preventStandby()
end

-- NOTE: This is what our scheduled task runs to trip the UIManager state to standby
function AutoSuspend:allowStandby()
    logger.dbg("AutoSuspend: allowStandby")
    -- Tell UIManager that we now allow standby.
    UIManager:allowStandby()

    -- This is necessary for wakeup from standby, as the deadline for receiving input events
    -- is calculated from the time to the next scheduled function.
    -- Make sure this function comes soon, as the time for going to standby after a scheduled wakeup
    -- is prolonged by the given time. Any time between 0.500 and 0.001 seconds should do.
    -- Let's call it deadline_guard.
    UIManager:scheduleIn(0.100, function() end)

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
    if self:_enabledStandby() then
        UIManager:preventStandby()
    end

    -- And make sure onLeaveStandby, which will come *after* us if we suspended *during* standby,
    -- won't re-schedule stuff right before entering suspend...
    self.pause_auto_standby = true
end

function AutoSuspend:onResume()
    logger.dbg("AutoSuspend: onResume")

    -- Restore standby balance after onSuspend
    self.pause_auto_standby = false
    if self:_enabledStandby() then
        UIManager:allowStandby()
    end

    if self:_enabledShutdown() and Device.wakeup_mgr then
        Device.wakeup_mgr:removeTask(nil, nil, UIManager.poweroff_action)
    end
    -- Unschedule in case we tripped onUnexpectedWakeupLimit first...
    self:_unschedule()
    -- We should always follow an InputEvent, so last_action_tv is already up to date :).
    self:_start()
    self:_unschedule_standby()
    self:_start_standby()
end

function AutoSuspend:onLeaveStandby()
    logger.dbg("AutoSuspend: onLeaveStandby")
    self:_start_standby()
end

function AutoSuspend:onUnexpectedWakeupLimit()
    logger.dbg("AutoSuspend: onUnexpectedWakeupLimit")
    -- Only re-engage the *shutdown* schedule to avoid doing the same dance indefinitely.
    self:_restart()
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

    local left_val
    if time_scale == 2 then
        left_val = math.floor(setting_val / (24*3600))
    elseif time_scale == 1 then
        left_val = math.floor(setting_val / 3600)
    else
        left_val = math.floor(setting_val / 60)
    end

    local right_val
    if time_scale == 2 then
        right_val = math.floor(setting_val / 3600) % 24
    elseif time_scale == 1 then
        right_val = math.floor(setting_val / 60) % 60
    else
        right_val = math.floor(setting_val) % 60
    end
    local time_spinner
    time_spinner = DateTimeWidget:new {
        is_date = false,
        hour = left_val,
        min = right_val,
        hour_hold_step = 5,
        min_hold_step = 10,
        hour_max = (time_scale == 2 and math.floor(range[2] / (24*3600)))
            or (time_scale == 1 and math.floor(range[2] / 3600))
            or math.floor(range[2] / 60),
        min_max = (time_scale == 2 and 23) or 59,
        ok_text = _("Set timeout"),
        title_text = title,
        info_text = info,
        callback = function(time)
            if time_scale == 2 then
                self[setting] = (time.hour * 24 + time.min) * 3600
            elseif time_scale == 1 then
                self[setting] = time.hour * 3600 + time.min * 60
            else
                self[setting] = time.hour * 60 + time.min
            end
            self[setting] = Math.clamp(self[setting], range[1], range[2])
            G_reader_settings:saveSetting(setting, self[setting])
            if is_standby then
                self:_unschedule_standby()
                self:_start_standby()
            else
                self:_unschedule()
                self:_start()
            end
            if touchmenu_instance then touchmenu_instance:updateItems() end
            local time_string = util.secondsToClockDuration("modern", self[setting],
                time_scale == 2 or time_scale == 1, true, true)
            time_string = time_string:gsub("00m$", ""):gsub("^0+m", ""):gsub("^0", "")
            UIManager:show(InfoMessage:new{
                text = T(_("%1: %2"), title, time_string),
                timeout = 3,
            })
        end,
        default_value = util.secondsToClockDuration("modern", default_value,
            time_scale == 2 or time_scale == 1, true, true):gsub("00m$", ""):gsub("^00m:", ""),
        default_callback = function()
            local hour
            if time_scale == 2 then
                hour = math.floor(default_value / (24*3600))
            elseif time_scale == 1 then
                hour = math.floor(default_value / 3600)
            else
                hour = math.floor(default_value / 60)
            end
            local min
            if time_scale == 2 then
                min = math.floor(default_value / 3600) % 24
            elseif time_scale == 1 then
                min = math.floor(default_value / 60) % 60
            else
                min = math.floor(default_value % 60)
            end
            time_spinner:update(nil, hour, min)
        end,
        extra_text = _("Disable"),
        extra_callback = function(this)
            self[setting] = -1 -- disable with a negative time/number
            G_reader_settings:saveSetting(setting, -1)
            if is_standby then
                self:_unschedule_standby()
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
    menu_items.autosuspend = {
        sorting_hint = "device",
        checked_func = function()
            return self:_enabled()
        end,
        text_func = function()
            if self.auto_suspend_timeout_seconds and self.auto_suspend_timeout_seconds > 0 then
                local time_string = util.secondsToClockDuration("modern",
                    self.auto_suspend_timeout_seconds, true, true, true):gsub("00m$", ""):gsub("^00m:", "")
                return T(_("Autosuspend timeout: %1"), time_string)
            else
                return _("Autosuspend timeout")
            end
        end,
        keep_menu_open = true,
        callback = function(touchmenu_instance)
            -- 60 sec (1') is the minimum and 24*3600 sec (1day) is the maximum suspend time.
            -- A suspend time of one day seems to be excessive.
            -- But or battery testing it might give some sense.
            self:pickTimeoutValue(touchmenu_instance,
                _("Timeout for autosuspend"), _("Enter time in hours and minutes."),
                "auto_suspend_timeout_seconds", default_auto_suspend_timeout_seconds,
                {60, 24*3600}, 1)
        end,
    }
    if Device:canPowerOff() or Device:isEmulator() then
        menu_items.autoshutdown = {
            sorting_hint = "device",
            checked_func = function()
                return self:_enabledShutdown()
            end,
            text_func = function()
                if self.autoshutdown_timeout_seconds and self.autoshutdown_timeout_seconds > 0 then
                    local time_string = util.secondsToClockDuration("modern", self.autoshutdown_timeout_seconds,
                        true, true, true):gsub("00m$", ""):gsub("^00m:", "")
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
                    _("Timeout for autoshutdown"),  _("Enter time in days and hours."),
                    "autoshutdown_timeout_seconds", default_autoshutdown_timeout_seconds,
                    {5*60, 28*24*3600}, 2)
            end,
        }
    end
    if Device:canStandby() then
        local standby_help = _([[Standby puts the device into a power-saving state in which the screen is on and user input can be performed.

Standby can not be entered if Wi-Fi is on.

Upon user input, the device needs a certain amount of time to wake up. Generally, the newer the device, the less noticeable this delay will be, but it can be fairly aggravating on slower devices.]])

        menu_items.autostandby = {
            sorting_hint = "device",
            checked_func = function()
                return self:_enabledStandby()
            end,
            text_func = function()
                if self.auto_standby_timeout_seconds and self.auto_standby_timeout_seconds > 0 then
                    local time_string = util.secondsToClockDuration("modern", self.auto_standby_timeout_seconds,
                        false, true, true):gsub("00m$", ""):gsub("^0+m", ""):gsub("^0", "")
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
                    {default_auto_standby_timeout_seconds, 15*60}, 0)
            end,
        }
    end
end

-- KOReader is merely waiting for user input right now.
-- UI signals us that standby is allowed at this very moment because nothing else goes on in the background.
function AutoSuspend:onAllowStandby()
    logger.dbg("AutoSuspend: onAllowStandby")
    -- This piggy-backs minimally on the UI framework implemented for the PocketBook autostandby plugin,
    -- see its own AllowStandby handler for more details.

    local wake_in = math.huge
    -- The next scheduled function should be our deadline_guard (c.f., `AutoSuspend:allowStandby`).
    -- Wake up before the second next scheduled function executes (e.g. footer update, suspend ...)
    local scheduler_times = UIManager:getNextTaskTimes(2)
    if #scheduler_times == 2 then
        -- Wake up slightly after the formerly scheduled event,
        -- to avoid resheduling the same function after a fraction of a second again (e.g. don't draw footer twice).
        wake_in = math.floor(scheduler_times[2]:tonumber()) + 1
    end

    if wake_in > 3 then -- don't go into standby, if scheduled wakeup is in less than 3 secs
        UIManager:broadcastEvent(Event:new("EnterStandby"))
        logger.dbg("AutoSuspend: entering standby with a wakeup alarm in", wake_in, "s")

        -- This obviously needs a matching implementation in Device, the canonical one being Kobo.
        Device:standby(wake_in)

        logger.dbg("AutoSuspend: left standby after", Device.last_standby_tv:tonumber(), "s")

        -- Make sure UIManager will consume the input events that woke us up first (in case we were woken up by user input,
        -- as opposed to an rtc wake alarm)!
        -- (This ensures we'll use an up to date last_action_tv, and that it only ever gets updated from *user* input).
        UIManager:nextTick(function()
            -- Only if we're not already entering suspend...
            if self.pause_auto_standby then
                return
            end

            UIManager:broadcastEvent(Event:new("LeaveStandby"))
            self:_unschedule() -- unschedule suspend and shutdown, as the realtime clock has ticked
            self:_start()      -- reschedule suspend and shutdown (we'll recompute the delay based on the last user input, *not* the current time).
                               -- i.e., the goal is to behave as if we'd never unscheduled it, making sure we do *NOT* reset the delay to the full timeout.
        end)
    end
    -- We don't reschedule standby here, as this will interfere with suspend.
    -- Leave that to `onLeaveStandby`.
end

return AutoSuspend
