local Device = require("device")
local Event = require("ui/event")
local PluginShare = require("pluginshare")
local TimeVal = require("ui/timeval")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local _ = require("gettext")
local T = require("ffi/util").template

local AutoTurn = WidgetContainer:new{
    name = "autoturn",
    is_doc_only = true,
    autoturn_sec = 0,
    autoturn_distance = 1,
    enabled = false,
    last_action_tv = TimeVal.zero,
    task = nil,
}

function AutoTurn:_enabled()
    return self.enabled and self.autoturn_sec > 0
end

function AutoTurn:_schedule()
    if not self:_enabled() then
        logger.dbg("AutoTurn:_schedule is disabled")
        return
    end

    local delay = self.last_action_tv + TimeVal:new{ sec = self.autoturn_sec, usec = 0 } - UIManager:getTime()
    delay = delay:tonumber()

    if delay <= 0 then
        if UIManager:getTopWidget() == "ReaderUI" then
            logger.dbg("AutoTurn: go to next page")
            self.ui:handleEvent(Event:new("GotoViewRel", self.autoturn_distance))
        end
        logger.dbg("AutoTurn: schedule in", self.autoturn_sec)
        UIManager:scheduleIn(self.autoturn_sec, self.task)
    else
        logger.dbg("AutoTurn: schedule in", delay)
        UIManager:scheduleIn(delay, self.task)
    end
end

function AutoTurn:_unschedule()
    PluginShare.pause_auto_suspend = false
    if self.task then
        logger.dbg("AutoTurn: unschedule")
        UIManager:unschedule(self.task)
    end
end

function AutoTurn:_start()
    if self:_enabled() then
        local now_tv = UIManager:getTime()
        logger.dbg("AutoTurn: start at", now_tv:tonumber())
        PluginShare.pause_auto_suspend = true
        self.last_action_tv = now_tv
        self:_schedule()

        local text
        if self.autoturn_distance == 1 then
            text = T(_("Autoturn is now active and will automatically turn the page every %1 seconds."),
                self.autoturn_sec)
        else
            text = T(_("Autoturn is now active and will automatically scroll %1 % of the page every %2 seconds."),
                self.autoturn_distance * 100,
                self.autoturn_sec)
        end

        local InfoMessage = require("ui/widget/infomessage")
        UIManager:show(InfoMessage:new{
            text = text,
            timeout = 3,
        })
    end
end

function AutoTurn:init()
    UIManager.event_hook:registerWidget("InputEvent", self)
    self.autoturn_sec = G_reader_settings:readSetting("autoturn_timeout_seconds") or 0
    self.autoturn_distance = G_reader_settings:readSetting("autoturn_distance") or 1
    self.enabled = G_reader_settings:isTrue("autoturn_enabled")
    self.ui.menu:registerToMainMenu(self)
    self.task = function()
        self:_schedule()
    end
    self:_start()
end

function AutoTurn:onCloseWidget()
    logger.dbg("AutoTurn: onCloseWidget")
    self:_unschedule()
    self.task = nil
end

function AutoTurn:onCloseDocument()
    logger.dbg("AutoTurn: onCloseDocument")
    self:_unschedule()
end

function AutoTurn:onInputEvent()
    logger.dbg("AutoTurn: onInputEvent")
    self.last_action_tv = UIManager:getTime()
end

-- We do not want autoturn to turn pages during the suspend process.
-- Unschedule it and restart after resume.
function AutoTurn:onSuspend()
    logger.dbg("AutoTurn: onSuspend")
    self:_unschedule()
end

function AutoTurn:onResume()
    logger.dbg("AutoTurn: onResume")
    self:_start()
end

function AutoTurn:addToMainMenu(menu_items)
    menu_items.autoturn = {
        sorting_hint = "navi",
        text_func = function() return self:_enabled() and T(_("Autoturn (%1 s)"), self.autoturn_sec)
            or _("Autoturn") end,
        checked_func = function() return self:_enabled() end,
        callback = function(menu)
            local Screen = Device.screen
            local SpinWidget = require("ui/widget/spinwidget")
            local curr_items = G_reader_settings:readSetting("autoturn_timeout_seconds") or 30
            local autoturn_spin = SpinWidget:new {
                width = math.floor(Screen:getWidth() * 0.6),
                value = curr_items,
                value_min = 0,
                value_max = 240,
                value_hold_step = 5,
                ok_text = _("Set timeout"),
                cancel_text = _("Disable"),
                title_text = _("Timeout in seconds"),
                cancel_callback = function()
                    self.enabled = false
                    G_reader_settings:makeFalse("autoturn_enabled")
                    self:_unschedule()
                    menu:updateItems()
                end,
                callback = function(autoturn_spin)
                    self.autoturn_sec = autoturn_spin.value
                    G_reader_settings:saveSetting("autoturn_timeout_seconds", autoturn_spin.value)
                    self.enabled = true
                    G_reader_settings:makeTrue("autoturn_enabled")
                    self:_unschedule()
                    self:_start()
                    menu:updateItems()
                end,
            }
            UIManager:show(autoturn_spin)
        end,
        hold_callback = function(menu)
            local Screen = Device.screen
            local SpinWidget = require("ui/widget/spinwidget")
            local curr_items = G_reader_settings:readSetting("autoturn_distance") or 1
            local autoturn_spin = SpinWidget:new {
                width = math.floor(Screen:getWidth() * 0.6),
                value = curr_items,
                value_min = -20,
                value_max = 20,
                precision = "%.2f",
                value_step = .1,
                value_hold_step = .5,
                ok_text = _("Set distance"),
                title_text = _("Scrolling distance"),
                callback = function(autoturn_spin)
                    self.autoturn_distance = autoturn_spin.value
                    G_reader_settings:saveSetting("autoturn_distance", autoturn_spin.value)
                    if self.enabled then
                        self:_unschedule()
                        self:_start()
                    end
                    menu:updateItems()
                end,
            }
            UIManager:show(autoturn_spin)
        end,
    }
end

return AutoTurn
