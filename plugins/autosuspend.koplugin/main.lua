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
local Math = require("optmath")
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

function AutoSuspend:setSuspendShutdownTimes(touchmenu_instance, title, info, setting,
        default_value, range, is_day_hour)
    -- Attention if is_day_hour then time.hour stands for days and time.min for hours

    local InfoMessage = require("ui/widget/infomessage")
    local DateTimeWidget = require("ui/widget/datetimewidget")

    local setting_val = self[setting] > 0 and self[setting] or default_value

    local left_val = is_day_hour and math.floor(setting_val / (24*3600))
        or math.floor(setting_val / 3600)
    local right_val = is_day_hour and math.floor(setting_val / 3600) % 24
        or math.floor((setting_val / 60) % 60)
    local time_spinner
    time_spinner = DateTimeWidget:new {
        is_date = false,
        hour = left_val,
        min = right_val,
        hour_hold_step = 5,
        min_hold_step = 10,
        hour_max = is_day_hour and math.floor(range[2] / (24*3600)) or math.floor(range[2] / 3600),
        min_max = is_day_hour and 23 or 59,
        ok_text = _("Set timeout"),
        title_text = title,
        info_text = info,
        callback = function(time)
            self[setting] = is_day_hour and (time.hour * 24 * 3600 + time.min * 3600)
                or (time.hour * 3600 + time.min * 60)
            self[setting] = Math.clamp(self[setting], range[1], range[2])
            G_reader_settings:saveSetting(setting, self[setting])
            self:_unschedule()
            self:_start()
            if touchmenu_instance then touchmenu_instance:updateItems() end
            local time_string = util.secondsToClockDuration("modern", self[setting], true, true, true)
            time_string = time_string:gsub("00m","")
            UIManager:show(InfoMessage:new{
                text = T(_("%1: %2"), title, time_string),
                timeout = 3,
            })
        end,
        default_value = util.secondsToClockDuration("modern", default_value, true, true, true):gsub("00m$",""),
        default_callback = function()
            local hour = is_day_hour and math.floor(default_value / (24*3600))
                or math.floor(default_value / 3600)
            local min = is_day_hour and math.floor(default_value / 3600) % 24
                or math.floor(default_value / 60) % 60
            time_spinner:update(nil, hour, min)
        end,
        extra_text = _("Disable"),
        extra_callback = function(_self)
            self[setting] = -1 -- disable with a negative time/number
            self:_unschedule()
            if touchmenu_instance then touchmenu_instance:updateItems() end
            UIManager:show(InfoMessage:new{
                text = T(_("%1: disabled"), title),
                timeout = 3,
            })
            _self:onClose()
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
                    self.auto_suspend_timeout_seconds, true, true, true):gsub("00m$","")
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
                {60, 24*3600}, false)
        end,
    }
    if not (Device:canPowerOff() or Device:isEmulator()) then return end
    menu_items.autoshutdown = {
        sorting_hint = "device",
        checked_func = function()
            return self:_enabledShutdown()
        end,
        text_func = function()
            if self.autoshutdown_timeout_seconds and self.autoshutdown_timeout_seconds > 0 then
                local time_string = util.secondsToClockDuration("modern",
                    self.autoshutdown_timeout_seconds, true, true, true):gsub("00m$","")
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
                {5*60, 28*24*3600}, true)
        end,
    }
end

return AutoSuspend
