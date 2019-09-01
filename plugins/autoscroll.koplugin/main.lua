local Device = require("device")
local Event = require("ui/event")
local PluginShare = require("pluginshare")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local _ = require("gettext")
local T = require("ffi/util").template

local AutoScroll = WidgetContainer:new{
    name = 'autoscroll',
    is_doc_only = true,
    auto_scroll_sec = G_reader_settings:readSetting("auto_scroll_timeout_seconds") or 0,
    enabled = G_reader_settings:isTrue("auto_scroll_enabled"),
    settings_id = 0,
    last_action_sec = os.time(),
}

function AutoScroll:_enabled()
    return self.enabled and self.auto_scroll_sec > 0
end

function AutoScroll:_schedule(settings_id)
    if not self:_enabled() then
        logger.dbg("AutoScroll:_schedule is disabled")
        return
    end
    if self.settings_id ~= settings_id then
        logger.dbg("AutoScroll:_schedule registered settings_id ",
                   settings_id,
                   " does not equal to current one ",
                   self.settings_id)
        return
    end

    local delay

    if PluginShare.pause_auto_scroll then
        delay = self.auto_scroll_sec
    else
        delay = self.last_action_sec + self.auto_scroll_sec - os.time()
    end

    if delay <= 0 then
        logger.dbg("AutoScroll: go to next page")
        self.ui:handleEvent(Event:new("GotoViewRel", 1))
        logger.dbg("AutoScroll: schedule at ", os.time() + self.auto_scroll_sec)
        UIManager:scheduleIn(self.auto_scroll_sec, function() self:_schedule(settings_id) end)
    else
        logger.dbg("AutoScroll: schedule at ", os.time() + delay)
        UIManager:scheduleIn(delay, function() self:_schedule(settings_id) end)
    end
end

function AutoScroll:_deprecateLastTask()
    self.settings_id = self.settings_id + 1
    logger.dbg("AutoScroll: deprecateLastTask ", self.settings_id)
end

function AutoScroll:_start()
    if self:_enabled() then
        logger.dbg("AutoScroll: start at ", os.time())
        self.last_action_sec = os.time()
        self:_schedule(self.settings_id)

        local InfoMessage = require("ui/widget/infomessage")
        UIManager:show(InfoMessage:new{
            text = T(_("Autoscroll is now active and will automatically turn the page every %1 seconds."), self.auto_scroll_sec),
            timeout = 3,
        })
    end
end

function AutoScroll:init()
    UIManager.event_hook:registerWidget("InputEvent", self)
    self.auto_scroll_sec = self.settings
    self.ui.menu:registerToMainMenu(self)
    self:_deprecateLastTask()
    self:_start()
end

function AutoScroll:onInputEvent()
    logger.dbg("AutoScroll: onInputEvent")
    self.last_action_sec = os.time()
end

-- We do not want auto scroll procedure to waste battery during suspend. So let's unschedule it
-- when suspending and restart it after resume.
function AutoScroll:onSuspend()
    logger.dbg("AutoScroll: onSuspend")
    self:_deprecateLastTask()
end

function AutoScroll:onResume()
    logger.dbg("AutoScroll: onResume")
    self:_start()
end

function AutoScroll:addToMainMenu(menu_items)
    menu_items.autoscroll = {
        text_func = function() return self:_enabled() and T(_("Autoscroll (%1 s)"), self.auto_scroll_sec)
            or _("Autoscroll") end,
        checked_func = function() return self:_enabled() end,
        callback = function()
            local Screen = Device.screen
            local SpinWidget = require("ui/widget/spinwidget")
            local curr_items = G_reader_settings:readSetting("auto_scroll_timeout_seconds") or 30
            local autoscroll_spin = SpinWidget:new {
                width = Screen:getWidth() * 0.6,
                value = curr_items,
                value_min = 0,
                value_max = 240,
                value_hold_step = 5,
                ok_text = _("Set timeout"),
                cancel_text = _("Disable"),
                title_text = _("Timeout in seconds"),
                cancel_callback = function()
                    self.enabled = false
                    G_reader_settings:flipFalse("auto_scroll_enabled")
                    self:_deprecateLastTask()
                end,
                callback = function(autoscroll_spin)
                    self.auto_scroll_sec = autoscroll_spin.value
                    G_reader_settings:saveSetting("auto_scroll_timeout_seconds", autoscroll_spin.value)
                    self.enabled = true
                    G_reader_settings:flipTrue("auto_scroll_enabled")
                    self:_deprecateLastTask()
                    self:_start()
                end,
            }
            UIManager:show(autoscroll_spin)
        end,
    }
end

return AutoScroll
