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

local AutoSuspend = {
    settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/koboautosuspend.lua"),
    settings_id = 0,
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

function AutoSuspend:_schedule(settings_id)
    if not self:_enabled() then
        logger.dbg("AutoSuspend:_schedule is disabled")
        return
    end
    if self.settings_id ~= settings_id then
        logger.dbg("AutoSuspend:_schedule registered settings_id ",
                   settings_id,
                   " does not equal to current one ",
                   self.settings_id)
        return
    end

    local delay

    if PluginShare.pause_auto_suspend then
        delay = self.auto_suspend_sec
    else
        delay = self.last_action_sec + self.auto_suspend_sec - os.time()
    end

    if delay <= 0 then
        logger.dbg("AutoSuspend: will suspend the device")
        UIManager:suspend()
    else
        logger.dbg("AutoSuspend: schedule at ", os.time() + delay)
        UIManager:scheduleIn(delay, function() self:_schedule(settings_id) end)
    end
end

function AutoSuspend:_deprecateLastTask()
    self.settings_id = self.settings_id + 1
    logger.dbg("AutoSuspend: deprecateLastTask ", self.settings_id)
end

function AutoSuspend:_start()
    if self:_enabled() then
        logger.dbg("AutoSuspend: start at ", os.time())
        self.last_action_sec = os.time()
        self:_schedule(self.settings_id)
    end
end

function AutoSuspend:init()
    UIManager.event_hook:registerWidget("InputEvent", self)
    self.auto_suspend_sec = self:_readTimeoutSec()
    self:_deprecateLastTask()
    self:_start()
end

function AutoSuspend:onInputEvent()
    logger.dbg("AutoSuspend: onInputEvent")
    self.last_action_sec = os.time()
end

-- We do not want auto suspend procedure to waste battery during suspend. So let's unschedule it
-- when suspending and restart it after resume.
function AutoSuspend:onSuspend()
    logger.dbg("AutoSuspend: onSuspend")
    self:_deprecateLastTask()
end

function AutoSuspend:onResume()
    logger.dbg("AutoSuspend: onResume")
    self:_start()
end

AutoSuspend:init()

local AutoSuspendWidget = WidgetContainer:new{
    name = "autosuspend",
}

function AutoSuspendWidget:addToMainMenu(menu_items)
    menu_items.autosuspend = {
        text = _("Autosuspend timeout"),
        -- This won't ever be registered if the plugin is disabled ;).
        --[[
        enabled_func = function()
            -- NOTE: Pilfered from frontend/pluginloader.lua
            local plugins_disabled = G_reader_settings:readSetting("plugins_disabled") or {}
            return plugins_disabled["autosuspend"] ~= true
        end,
        --]]
        callback = function()
            local InfoMessage = require("ui/widget/infomessage")
            local Screen = Device.screen
            local SpinWidget = require("ui/widget/spinwidget")
            local curr_items = G_reader_settings:readSetting("auto_suspend_timeout_seconds") or 60*60
            local autosuspend_spin = SpinWidget:new {
                width = Screen:getWidth() * 0.6,
                value = curr_items / 60,
                value_min = 5,
                value_max = 240,
                value_hold_step = 15,
                ok_text = _("Set timeout"),
                title_text = _("Timeout in minutes"),
                callback = function(autosuspend_spin)
                    G_reader_settings:saveSetting("auto_suspend_timeout_seconds", autosuspend_spin.value * 60)
                    -- NOTE: Will only take effect after a restart, as we don't have a method to set this live...
                    UIManager:show(InfoMessage:new{
                        text = _("This will take effect on next restart."),
                    })
                end
            }
            UIManager:show(autosuspend_spin)
        end,
    }
end

function AutoSuspendWidget:init()
    -- self.ui is nil in the testsuite
    if not self.ui or not self.ui.menu then return end
    self.ui.menu:registerToMainMenu(self)
end

function AutoSuspendWidget:onInputEvent()
    AutoSuspend:onInputEvent()
end

function AutoSuspendWidget:onSuspend()
    AutoSuspend:onSuspend()
end

function AutoSuspendWidget:onResume()
    AutoSuspend:onResume()
end

return AutoSuspendWidget
