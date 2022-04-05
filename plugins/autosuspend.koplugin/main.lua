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

function AutoSuspend:_schedule(shutdown_only)
    if not self:_enabled() and Device:canPowerOff() and not self:_enabledShutdown() then
        logger.dbg("AutoSuspend:_schedule is disabled")
        return
    end

    local delay_suspend, delay_shutdown

    if PluginShare.pause_auto_suspend or Device.powerd:isCharging() then
        delay_suspend = self.auto_suspend_timeout_seconds
        delay_shutdown = self.autoshutdown_timeout_seconds
    else
        local now_tv = UIManager:getElapsedTimeSinceBoot()
        delay_suspend = (self.last_action_tv - now_tv):tonumber() + self.auto_suspend_timeout_seconds
        delay_shutdown = (self.last_action_tv - now_tv):tonumber() + self.autoshutdown_timeout_seconds
    end

    -- Try to shutdown first, as we may have been woken up from suspend just for the sole purpose of doing that.
    if self:_enabledShutdown() and delay_shutdown <= 0 then
        logger.dbg("AutoSuspend: initiating shutdown")
        UIManager:poweroff_action()
    elseif self:_enabled() and delay_suspend <= 0 and not shutdown_only then
        logger.dbg("AutoSuspend: will suspend the device")
        UIManager:suspend()
    else
        if self:_enabled() and not shutdown_only then
            logger.dbg("AutoSuspend: scheduling next suspend check in", delay_suspend)
            UIManager:scheduleIn(delay_suspend, self.task)
        end
        if self:_enabledShutdown() then
            logger.dbg("AutoSuspend: scheduling next shutdown check in", delay_shutdown)
            UIManager:scheduleIn(delay_shutdown, self.task)
        end
    end
end

function AutoSuspend:_unschedule()
    if self.task then
        logger.dbg("AutoSuspend: unschedule")
        UIManager:unschedule(self.task)
    end
end

function AutoSuspend:_start()
    if self:_enabled() or self:_enabledShutdown() then
        self.last_action_tv = UIManager:getElapsedTimeSinceBoot()
        logger.dbg("AutoSuspend: start at", self.last_action_tv:tonumber())
        self:_schedule()
    end
end

-- Variant that only re-engages the shutdown timer for onUnexpectedWakeupLimit
function AutoSuspend:_restart()
    if self:_enabledShutdown() then
        self.last_action_tv = UIManager:getElapsedTimeSinceBoot()
        logger.dbg("AutoSuspend: restart at", self.last_action_tv:tonumber())
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
        self:allowStandby()
    end

    self:_start()
    self:_reschedule_standby()

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

    if not Device:canStandby() then return end

    self:_unschedule_standby()
    self.standby_task = nil
end

function AutoSuspend:onInputEvent()
    logger.dbg("AutoSuspend: onInputEvent")
    self.last_action_tv = UIManager:getElapsedTimeSinceBoot()

    -- NOTE: The fact that we run this on *this* event ensures we don't have to handle the standby scheduling
    --       at all in setSuspendShutdownTimes ;).
    self:_reschedule_standby()
end

function AutoSuspend:_unschedule_standby()
    if self.is_standby_scheduled and self.standby_task then
        logger.dbg("AutoSuspend: unschedule standby")
        UIManager:unschedule(self.standby_task)
        -- Restore the UIManager balance, as we run preventStandby right after scheduling this task.
        UIManager:allowStandby()

        self.is_standby_scheduled = false
    end
end

function AutoSuspend:_reschedule_standby()
    if not Device:canStandby() then return end

    -- We may have just disabled the feature, so unschedule before checking it.
    self:_unschedule_standby()

    if not self:_enabledStandby() then return end

    logger.dbg("AutoSuspend: schedule autoStandby in", self.auto_standby_timeout_seconds)
    UIManager:scheduleIn(self.auto_standby_timeout_seconds, self.standby_task)
    self.is_standby_scheduled = true

    -- Prevent standby until our scheduled allowStandby
    self:preventStandby()
end

function AutoSuspend:preventStandby()
    logger.dbg("AutoSuspend:preventStandby")
    -- Tell UIManager that we want to prevent standby until our allowStandby scheduled task runs.
    UIManager:preventStandby()
end

-- NOTE: This is the scheduled task that should trip the UIManager state to standby
function AutoSuspend:allowStandby()
    logger.dbg("AutoSuspend:allowStandby")
    -- Tell UIManager that we now allow standby.
    UIManager:allowStandby()

    -- This is necessary for wakeup from standby, as the deadline for receiving input events
    -- is calculated from the time to the next scheduled function.
    -- Make sure this function comes soon, as the time for going to standby after a scheduled wakeup
    -- is prolonged by the given time. Any time between 0.500 and 0.001 seconds would go.
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
end

function AutoSuspend:onResume()
    logger.dbg("AutoSuspend: onResume")
    if self:_enabledShutdown() and Device.wakeup_mgr then
        Device.wakeup_mgr:removeTask(nil, nil, UIManager.poweroff_action)
    end
    -- Unschedule in case we tripped onUnexpectedWakeupLimit first...
    self:_unschedule()
    self:_start()
    self:_reschedule_standby()
end

function AutoSuspend:onLeaveStandby()
    self:_reschedule_standby()
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
function AutoSuspend:setSuspendShutdownTimes(touchmenu_instance, title, info, setting,
        default_value, range, time_scale)
    -- Attention if is_day_hour then time.hour stands for days and time.min for hours

    local InfoMessage = require("ui/widget/infomessage")
    local DateTimeWidget = require("ui/widget/datetimewidget")

    local setting_val = self[setting] > 0 and self[setting] or default_value

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
            self:_unschedule()
            self:_start()
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
            self:_unschedule()
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
            self:setSuspendShutdownTimes(touchmenu_instance,
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
                self:setSuspendShutdownTimes(touchmenu_instance,
                    _("Timeout for autoshutdown"),  _("Enter time in days and hours."),
                    "autoshutdown_timeout_seconds", default_autoshutdown_timeout_seconds,
                    {5*60, 28*24*3600}, 2)
            end,
        }
    end
    if Device:canStandby() then
        local standby_help = _([[Standby puts the device into a power-saving state in which the screen is on and user input can be performed.

Standby can not be entered if Wi-Fi is on.

Upon user input, the device needs a certain amount of time to wake up. With some devices this period of time is not noticeable, with other devices it can be annoying.]])

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
                self:setSuspendShutdownTimes(touchmenu_instance,
                    _("Timeout for autostandby"), _("Enter time in minutes and seconds."),
                    "auto_standby_timeout_seconds", default_auto_standby_timeout_seconds,
                    {4, 15*60}, 0)
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

    -- Don't enter standby if we haven't set a proper timeout yet.
    if not self:_enabledStandby() then
        logger.dbg("AutoSuspend: No timeout set, no standby")
        return
    end

    -- Don't enter standby if wifi is on, as this will break in fun and interesting ways (from Wi-Fi issues to kernel deadlocks).
    if NetworkMgr:isWifiOn() then
        logger.dbg("AutoSuspend: WiFi is on, no standby")
        return
    end

    -- Don't enter standby when charging on devices where charging prevents entering low power states.
    if Device.powerd:isCharging() and not Device:canPowerSaveWhileCharging() then
        logger.dbg("AutoSuspend: charging, no standby")
        return
    end

    if Device:canStandby() then
        local wake_in = math.huge
        -- The next scheduled function should be the deadline_guard
        -- Wake up before the second next scheduled function executes (e.g. footer update, suspend ...)
        local scheduler_times = UIManager:getNextTaskTimes(2)
        if #scheduler_times == 2 then
            -- Wake up slightly after the formerly scheduled event, to avoid resheduling the same function
            -- after a fraction of a second again (e.g. don't draw footer twice).
            wake_in = math.floor(scheduler_times[2]:tonumber()) + 1
        end

        if wake_in > 3 then -- don't go into standby, if scheduled wakeup is in less than 3 secs
            UIManager:broadcastEvent(Event:new("EnterStandby"))
            logger.dbg("AutoSuspend: going to standby and wake in " .. wake_in .. "s zZzzZzZzzzzZZZzZZZz")

            -- This obviously needs a matching implementation in Device, the canonical one being Kobo.
            Device:standby(wake_in)

            logger.dbg("AutoSuspend: leaving standby after " .. Device.last_standby_tv:tonumber() .. " s")

            UIManager:broadcastEvent(Event:new("LeaveStandby"))
            self:_unschedule() -- unschedule suspend and shutdown, as the realtime clock has ticked
            self:_schedule()   -- reschedule suspend and shutdown with the new time
        end
        -- Don't do a `self:_reschedule_standby()` here, as this will interfere with suspend.
        -- Leave that to onLeaveStandby.
    end
end

return AutoSuspend
