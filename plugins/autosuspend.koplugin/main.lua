local Device = require("device")

if not Device:isCervantes() and
    not Device:isKobo() and
    not Device:isRemarkable() and
    not Device:isSDL() and
    not Device:isSonyPRSTUX() and
    not Device:isPocketBook() then
    return { disabled = true, }
end

local PluginShare = require("pluginshare")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local _ = require("gettext")
local T = require("ffi/util").template

local default_autoshutdown_timeout_seconds = 3*24*60*60
local default_auto_suspend_timeout_seconds = 60*60

local AutoSuspend = WidgetContainer:new{
    name = "autosuspend",
    is_doc_only = false,
    autoshutdown_timeout_seconds = G_reader_settings:readSetting("autoshutdown_timeout_seconds") or default_autoshutdown_timeout_seconds,
    auto_suspend_timeout_seconds = G_reader_settings:readSetting("auto_suspend_timeout_seconds") or default_auto_suspend_timeout_seconds,
    last_action_sec = os.time(),
    standby_prevented = false,
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
        local now_ts = os.time()
        delay_suspend = self.last_action_sec + self.auto_suspend_timeout_seconds - now_ts
        delay_shutdown = self.last_action_sec + self.autoshutdown_timeout_seconds - now_ts
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
            UIManager:scheduleIn(delay_suspend, self._schedule, self, shutdown_only)
        end
        if self:_enabledShutdown() then
            logger.dbg("AutoSuspend: scheduling next shutdown check in", delay_shutdown)
            UIManager:scheduleIn(delay_shutdown, self._schedule, self, shutdown_only)
        end
    end
end

function AutoSuspend:_unschedule()
    logger.dbg("AutoSuspend: unschedule")
    UIManager:unschedule(self._schedule)
end

function AutoSuspend:_start()
    if self:_enabled() or self:_enabledShutdown() then
        local now_ts = os.time()
        logger.dbg("AutoSuspend: start at", now_ts)
        self.last_action_sec = now_ts
        self:_schedule()
    end
end

-- Variant that only re-engages the shutdown timer for onUnexpectedWakeupLimit
function AutoSuspend:_restart()
    if self:_enabledShutdown() then
        local now_ts = os.time()
        logger.dbg("AutoSuspend: restart at", now_ts)
        self.last_action_sec = now_ts
        self:_schedule(true)
    end
end

function AutoSuspend:init()
    if Device:isPocketBook() and not Device:canSuspend() then return end
    UIManager.event_hook:registerWidget("InputEvent", self)
    self:_unschedule()
    self:_start()
    -- self.ui is nil in the testsuite
    if not self.ui or not self.ui.menu then return end
    self.ui.menu:registerToMainMenu(self)
end

function AutoSuspend:onInputEvent()
    logger.dbg("AutoSuspend: onInputEvent")
    self.last_action_sec = os.time()
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

function AutoSuspend:addToMainMenu(menu_items)
    menu_items.autosuspend = {
        sorting_hint = "device",
        text = _("Autosuspend timeout"),
        callback = function()
            local InfoMessage = require("ui/widget/infomessage")
            local Screen = Device.screen
            local SpinWidget = require("ui/widget/spinwidget")
            local autosuspend_spin = SpinWidget:new {
                width = math.floor(Screen:getWidth() * 0.6),
                value = self.auto_suspend_timeout_seconds / 60,
                value_min = 5,
                value_max = 240,
                value_hold_step = 15,
                ok_text = _("Set timeout"),
                title_text = _("Timeout in minutes"),
                callback = function(autosuspend_spin)
                    self.auto_suspend_timeout_seconds = autosuspend_spin.value * 60
                    G_reader_settings:saveSetting("auto_suspend_timeout_seconds", self.auto_suspend_timeout_seconds)
                    UIManager:show(InfoMessage:new{
                        text = T(_("The system will automatically suspend after %1 minutes of inactivity."),
                            string.format("%.2f", self.auto_suspend_timeout_seconds / 60)),
                        timeout = 3,
                    })
                    self:_unschedule()
                    self:_start()
                end
            }
            UIManager:show(autosuspend_spin)
        end,
    }
    if not (Device:canPowerOff() or Device:isEmulator()) then return end
    menu_items.autoshutdown = {
        sorting_hint = "device",
        text = _("Autoshutdown timeout"),
        callback = function()
            local InfoMessage = require("ui/widget/infomessage")
            local Screen = Device.screen
            local SpinWidget = require("ui/widget/spinwidget")
            local autosuspend_spin = SpinWidget:new {
                width = math.floor(Screen:getWidth() * 0.6),
                value = self.autoshutdown_timeout_seconds / 60 / 60,
                -- About a minute, good for testing and battery life fanatics.
                -- Just high enough to avoid an instant shutdown death scenario.
                value_min = 0.017,
                -- More than three weeks seems a bit excessive if you want to enable authoshutdown,
                -- even if the battery can last up to three months.
                value_max = 28*24,
                value_hold_step = 24,
                precision = "%.2f",
                ok_text = _("Set timeout"),
                title_text = _("Timeout in hours"),
                callback = function(autosuspend_spin)
                    self.autoshutdown_timeout_seconds = math.floor(autosuspend_spin.value * 60 * 60)
                    G_reader_settings:saveSetting("autoshutdown_timeout_seconds", self.autoshutdown_timeout_seconds)
                    UIManager:show(InfoMessage:new{
                        text = T(_("The system will automatically shut down after %1 hours of inactivity."),
                            string.format("%.2f", self.autoshutdown_timeout_seconds / 60 / 60)),
                        timeout = 3,
                    })
                    self:_unschedule()
                    self:_start()
                end
            }
            UIManager:show(autosuspend_spin)
        end,
    }
end

return AutoSuspend
