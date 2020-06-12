local Device = require("device")

if not Device:isCervantes() and not Device:isKobo() and not Device:isSDL() and not Device:isSonyPRSTUX() then
    return { disabled = true, }
end

local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local PluginShare = require("pluginshare")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local _ = require("gettext")
local T = require("ffi/util").template

local default_autoshutdown_timeout_seconds = 3*24*60*60

local AutoSuspend = WidgetContainer:new{
    name = "autosuspend",
    is_doc_only = false,
    autoshutdown_timeout_seconds = G_reader_settings:readSetting("autoshutdown_timeout_seconds") or default_autoshutdown_timeout_seconds,
    settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/koboautosuspend.lua"),
    last_action_sec = os.time(),
}

function AutoSuspend:_readTimeoutSecFrom(settings)
    local sec = settings:readSetting("auto_suspend_timeout_seconds")
    if type(sec) == "number" then
        return sec
    end
    return -1
end

function AutoSuspend:_readTimeoutSec()
    local candidates = { self.settings, G_reader_settings }
    for _, candidate in ipairs(candidates) do
        local sec = self:_readTimeoutSecFrom(candidate)
        if sec ~= -1 then
            return sec
        end
    end

    -- default setting is 60 minutes
    return 60 * 60
end

function AutoSuspend:_enabled()
    return self.auto_suspend_sec > 0
end

function AutoSuspend:_enabledShutdown()
    return Device:canPowerOff() and self.autoshutdown_timeout_seconds > 0
end

function AutoSuspend:_schedule()
    if not self:_enabled() then
        logger.dbg("AutoSuspend:_schedule is disabled")
        return
    end

    local delay_suspend, delay_shutdown

    if PluginShare.pause_auto_suspend then
        delay_suspend = self.auto_suspend_sec
        delay_shutdown = self.autoshutdown_timeout_seconds
    else
        delay_suspend = self.last_action_sec + self.auto_suspend_sec - os.time()
        delay_shutdown = self.last_action_sec + self.autoshutdown_timeout_seconds - os.time()
    end

    if delay_suspend <= 0 then
        logger.dbg("AutoSuspend: will suspend the device")
        UIManager:suspend()
    elseif delay_shutdown <= 0 then
        logger.dbg("AutoSuspend: initiating shutdown")
        UIManager:poweroff_action()
    else
        if self:_enabled() then
            logger.dbg("AutoSuspend: schedule suspend at ", os.time() + delay_suspend)
            UIManager:scheduleIn(delay_suspend, self._schedule, self)
        end
        if self:_enabledShutdown() then
            logger.dbg("AutoSuspend: schedule shutdown at ", os.time() + delay_shutdown)
            UIManager:scheduleIn(delay_shutdown, self._schedule, self)
        end
    end
end

function AutoSuspend:_unschedule()
    logger.dbg("AutoSuspend: unschedule")
    UIManager:unschedule(self._schedule)
end

function AutoSuspend:_start()
    if self:_enabled() or self:_enabledShutdown() then
        logger.dbg("AutoSuspend: start at ", os.time())
        self.last_action_sec = os.time()
        self:_schedule()
    end
end

function AutoSuspend:init()
    UIManager.event_hook:registerWidget("InputEvent", self)
    self.auto_suspend_sec = self:_readTimeoutSec()
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
    self:_start()
end

function AutoSuspend:addToMainMenu(menu_items)
    menu_items.autosuspend = {
        text = _("Autosuspend timeout"),
        callback = function()
            local InfoMessage = require("ui/widget/infomessage")
            local Screen = Device.screen
            local SpinWidget = require("ui/widget/spinwidget")
            local curr_items = G_reader_settings:readSetting("auto_suspend_timeout_seconds") or 60*60
            local autosuspend_spin = SpinWidget:new {
                width = math.floor(Screen:getWidth() * 0.6),
                value = curr_items / 60,
                value_min = 5,
                value_max = 240,
                value_hold_step = 15,
                ok_text = _("Set timeout"),
                title_text = _("Timeout in minutes"),
                callback = function(autosuspend_spin)
                    local autosuspend_timeout_seconds = autosuspend_spin.value * 60
                    self.auto_suspend_sec = autosuspend_timeout_seconds
                    G_reader_settings:saveSetting("auto_suspend_timeout_seconds", autosuspend_timeout_seconds)
                    UIManager:show(InfoMessage:new{
                        text = T(_("The system will automatically suspend after %1 minutes of inactivity."),
                            string.format("%.2f", autosuspend_timeout_seconds/60)),
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
        text = _("Autoshutdown timeout"),
        callback = function()
            local InfoMessage = require("ui/widget/infomessage")
            local Screen = Device.screen
            local SpinWidget = require("ui/widget/spinwidget")
            local curr_items = self.autoshutdown_timeout_seconds
            local autosuspend_spin = SpinWidget:new {
                width = math.floor(Screen:getWidth() * 0.6),
                value = curr_items / 60 / 60,
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
                    local autoshutdown_timeout_seconds = math.floor(autosuspend_spin.value * 60*60)
                    self.autoshutdown_timeout_seconds = autoshutdown_timeout_seconds
                    G_reader_settings:saveSetting("autoshutdown_timeout_seconds", autoshutdown_timeout_seconds)
                    UIManager:show(InfoMessage:new{
                        text = T(_("The system will automatically shut down after %1 hours of inactivity."),
                            string.format("%.2f", autoshutdown_timeout_seconds/60/60)),
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
