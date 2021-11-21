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

local PluginShare = require("pluginshare")
local TimeVal = require("ui/timeval")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local T = require("ffi/util").template

local default_autoshutdown_timeout_seconds = 3*24*60*60 -- three days
local default_auto_suspend_timeout_seconds = 15*60 -- 15 minutes

local AutoSuspend = WidgetContainer:new{
    name = "autosuspend",
    is_doc_only = false,
    autoshutdown_timeout_seconds = default_autoshutdown_timeout_seconds,
    auto_suspend_timeout_seconds = default_auto_suspend_timeout_seconds,
    last_action_tv = TimeVal.zero,
    standby_prevented = false,
    task = nil,
}

function AutoSuspend:_enabled()
    return self.auto_suspend_timeout_seconds > 0
end

function AutoSuspend:_enabledShutdown()
    return Device:canPowerOff() and self.autoshutdown_timeout_seconds > 0
end

function AutoSuspend:_schedule(shutdown_only)
    if not self:_enabled() and (Device:canPowerOff() and not self:_enabledShutdown()) then
        logger.dbg("AutoSuspend:_schedule is disabled")
        return
    end

    local delay_suspend, delay_shutdown

    if PluginShare.pause_auto_suspend or Device.standby_prevented or Device.powerd:isCharging() then
        delay_suspend = self.auto_suspend_timeout_seconds
        delay_shutdown = self.autoshutdown_timeout_seconds
    else
        local now_tv = UIManager:getTime()
        delay_suspend = self.last_action_tv + TimeVal:new{ sec = self.auto_suspend_timeout_seconds, usec = 0 } - now_tv
        delay_suspend = delay_suspend:tonumber()
        delay_shutdown = self.last_action_tv + TimeVal:new{ sec = self.autoshutdown_timeout_seconds, usec = 0 } - now_tv
        delay_shutdown = delay_shutdown:tonumber()
    end

    -- Try to shutdown first, as we may have been woken up from suspend just for the sole purpose of doing that.
    if delay_shutdown <= 0 then
        logger.dbg("AutoSuspend: initiating shutdown")
        UIManager:poweroff_action()
    elseif delay_suspend <= 0 and not shutdown_only then
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
        local now_tv = UIManager:getTime()
        logger.dbg("AutoSuspend: start at", now_tv:tonumber())
        self.last_action_tv = now_tv
        self:_schedule()
    end
end

-- Variant that only re-engages the shutdown timer for onUnexpectedWakeupLimit
function AutoSuspend:_restart()
    if self:_enabledShutdown() then
        local now_tv = UIManager:getTime()
        logger.dbg("AutoSuspend: restart at", now_tv:tonumber())
        self.last_action_tv = now_tv
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

    UIManager.event_hook:registerWidget("InputEvent", self)
    -- We need an instance-specific function reference to schedule, because in some rare cases,
    -- we may instantiate a new plugin instance *before* tearing down the old one.
    self.task = function(shutdown_only)
        self:_schedule(shutdown_only)
    end
    self:_start()
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
end

function AutoSuspend:onInputEvent()
    logger.dbg("AutoSuspend: onInputEvent")
    self.last_action_tv = UIManager:getTime()
end

function AutoSuspend:onSuspend()
    logger.dbg("AutoSuspend: onSuspend")
    -- We do not want auto suspend procedure to waste battery during suspend. So let's unschedule it
    -- when suspending and restart it after resume.
    self:_unschedule()
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
end

function AutoSuspend:onUnexpectedWakeupLimit()
    logger.dbg("AutoSuspend: onUnexpectedWakeupLimit")
    -- Only re-engage the *shutdown* schedule to avoid doing the same dance indefinitely.
    self:_restart()
end

function AutoSuspend:onAllowStandby()
    self.standby_prevented = false
end

function AutoSuspend:onPreventStandby()
    self.standby_prevented = true
end

function AutoSuspend:setSuspendShutdownTimes(touchmenu_instance, title, setting, default_value)
    local InfoMessage = require("ui/widget/infomessage")
    local DateTimeWidget = require("ui/widget/datetimewidget")
    -- About a minute, good for testing and battery life fanatics.
    -- Just high enough to avoid an instant shutdown death scenario.
    local min_time = 60
    -- More than three weeks seems a bit excessive if you want to enable authoshutdown/suspend,
    -- even if the battery can last up to three months.
    local max_time_h = 21*24
    local max_time = max_time_h * 3600
    local duration_format = G_reader_settings:readSetting("duration_format", "classic")
    local function show_info_message()
        UIManager:show(InfoMessage:new{
            text = T(_("%1: %2"), title,
                util.secondsToClockDuration(duration_format, self[setting], true)),
            timeout = 3,
        })
    end
    UIManager:show(DateTimeWidget:new {
        is_date = false,
        hour = math.floor(self[setting] / 3600),
        min = math.floor((self[setting] / 60) % 60),
        hour_hold_step = 24,
        min_hold_step = 10,
        hour_max = max_time_h,
        ok_text = _("Set timeout"),
        title_text = title,
        info_text = _("Set time in hours and minutes."),
        callback = function(time)
            self[setting] = math.floor((time.hour * 60 + time.min) * 60)
            if self[setting] < min_time then
                self[setting] = min_time
            elseif self[setting] > max_time then
                self[setting] = max_time
            end
            G_reader_settings:saveSetting(setting, self[setting])
            self:_unschedule()
            self:_start()
            if touchmenu_instance then touchmenu_instance:updateItems() end
            show_info_message()
        end,
        extra_text = T(_("Set to default: %1"),util.secondsToClockDuration(duration_format, default_value, true)),
        extra_callback = function()
            self[setting] = default_value
            G_reader_settings:saveSetting(setting, default_value)
            if touchmenu_instance then touchmenu_instance:updateItems() end
            show_info_message()
        end,
    })
end

function AutoSuspend:addToMainMenu(menu_items)
    menu_items.autosuspend = {
        sorting_hint = "device",
        text_func = function()
            if self.auto_suspend_timeout_seconds  then
                local duration_format = G_reader_settings:readSetting("duration_format", "classic")
                return T(_("Autosuspend timeout: %1"),
                    util.secondsToClockDuration(duration_format, self.auto_suspend_timeout_seconds, true))
            else
                return _("Autosuspend timeout")
            end
        end,
        keep_menu_open = true,
        callback = function(touchmenu_instance)
            self:setSuspendShutdownTimes(touchmenu_instance, _("Timeout for autosuspend"),
                "auto_suspend_timeout_seconds", default_auto_suspend_timeout_seconds)
        end,
    }
    if not (Device:canPowerOff() or Device:isEmulator()) then return end
    menu_items.autoshutdown = {
        sorting_hint = "device",
        text_func = function()
            if self.autoshutdown_timeout_seconds  then
                local duration_format = G_reader_settings:readSetting("duration_format", "classic")
                return T(_("Autoshutdown timeout: %1"),
                    util.secondsToClockDuration(duration_format, self.autoshutdown_timeout_seconds, true))
            else
                return _("Autoshutdown timeout")
            end
        end,
        keep_menu_open = true,
        callback = function(touchmenu_instance)
            self:setSuspendShutdownTimes(touchmenu_instance, _("Timeout for autoshutdown"),
                "autoshutdown_timeout_seconds", default_autoshutdown_timeout_seconds)
        end,
    }
end

return AutoSuspend
