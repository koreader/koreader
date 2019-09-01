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
    autoscroll_sec = G_reader_settings:readSetting("autoscroll_timeout_seconds") or 0,
    autoscroll_distance = G_reader_settings:readSetting("autoscroll_distance") or 1,
    enabled = G_reader_settings:isTrue("autoscroll_enabled"),
    settings_id = 0,
    last_action_sec = os.time(),
}

function AutoScroll:_enabled()
    return self.enabled and self.autoscroll_sec > 0
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

    local delay = self.last_action_sec + self.autoscroll_sec - os.time()

    if delay <= 0 then
        logger.dbg("AutoScroll: go to next page")
        self.ui:handleEvent(Event:new("GotoViewRel", self.autoscroll_distance))
        logger.dbg("AutoScroll: schedule at ", os.time() + self.autoscroll_sec)
        UIManager:scheduleIn(self.autoscroll_sec, function() self:_schedule(settings_id) end)
    else
        logger.dbg("AutoScroll: schedule at ", os.time() + delay)
        UIManager:scheduleIn(delay, function() self:_schedule(settings_id) end)
    end
end

function AutoScroll:_deprecateLastTask()
    PluginShare.pause_auto_suspend = false
    self.settings_id = self.settings_id + 1
    logger.dbg("AutoScroll: deprecateLastTask ", self.settings_id)
end

function AutoScroll:_start()
    if self:_enabled() then
        logger.dbg("AutoScroll: start at ", os.time())
        PluginShare.pause_auto_suspend = true
        self.last_action_sec = os.time()
        self:_schedule(self.settings_id)

        local InfoMessage = require("ui/widget/infomessage")
        UIManager:show(InfoMessage:new{
            text = T(_("Autoscroll is now active and will automatically scroll the page by %1 every %2 seconds."),
                self.autoscroll_distance,
                self.autoscroll_sec),
            timeout = 3,
        })
    end
end

function AutoScroll:init()
    UIManager.event_hook:registerWidget("InputEvent", self)
    self.autoscroll_sec = self.settings
    self.ui.menu:registerToMainMenu(self)
    self:_deprecateLastTask()
    self:_start()
end

function AutoScroll:onCloseDocument()
    logger.dbg("AutoScroll: onCloseDocument")
    self:_deprecateLastTask()
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

function AutoScroll:onTopWidget(widget)
    logger.dbg("AutoScroll: onTopWidget", widget)
    if widget ~= "ReaderUI" then
        self:_deprecateLastTask()
    else
        self:_start()
    end
end

function AutoScroll:addToMainMenu(menu_items)
    menu_items.autoscroll = {
        text_func = function() return self:_enabled() and T(_("Autoscroll (%1 s)"), self.autoscroll_sec)
            or _("Autoscroll") end,
        checked_func = function() return self:_enabled() end,
        callback = function(menu)
            local Screen = Device.screen
            local SpinWidget = require("ui/widget/spinwidget")
            local curr_items = G_reader_settings:readSetting("autoscroll_timeout_seconds") or 30
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
                    G_reader_settings:flipFalse("autoscroll_enabled")
                    self:_deprecateLastTask()
                    menu:updateItems()
                end,
                callback = function(autoscroll_spin)
                    self.autoscroll_sec = autoscroll_spin.value
                    G_reader_settings:saveSetting("autoscroll_timeout_seconds", autoscroll_spin.value)
                    self.enabled = true
                    G_reader_settings:flipTrue("autoscroll_enabled")
                    self:_deprecateLastTask()
                    self:_start()
                    menu:updateItems()
                end,
            }
            UIManager:show(autoscroll_spin)
        end,
        hold_callback = function(menu)
            local Screen = Device.screen
            local SpinWidget = require("ui/widget/spinwidget")
            local curr_items = G_reader_settings:readSetting("autoscroll_distance") or 1
            local autoscroll_spin = SpinWidget:new {
                width = Screen:getWidth() * 0.6,
                value = curr_items,
                value_min = -20,
                value_max = 20,
                precision = "%.2f",
                value_step = .1,
                value_hold_step = .5,
                ok_text = _("Set distance"),
                title_text = _("Scroll distance"),
                callback = function(autoscroll_spin)
                    self.autoscroll_distance = autoscroll_spin.value
                    G_reader_settings:saveSetting("autoscroll_distance", autoscroll_spin.value)
                    if self.enabled then
                        self:_deprecateLastTask()
                        self:_start()
                    end
                    menu:updateItems()
                end,
            }
            UIManager:show(autoscroll_spin)
        end,
    }
end

return AutoScroll
