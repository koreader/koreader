--[[--
Plugin for automatic dimming of the frontlight after an idle period.

@module koplugin.autodim
--]]--

local Device = require("device")
local Event = require("ui/event")
local FFIUtil = require("ffi/util")
local SpinWidget = require("ui/widget/spinwidget")
local TimeVal = require("ui/timeval")   -- this will have to be changed to "ui/time", also the _tv will become _time
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local T = FFIUtil.template

local DEFAULT_AUTODIM_STARTTIME_M = 5
local DEFAULT_AUTODIM_DURATION_S = 20
local DEFAULT_AUTODIM_ENDPERCENTAGE = 20
local AUTODIM_EVENT_FREQUENCY = 2 -- in Hz; Frequenzy for FrontlightChangedEvent on E-Ink devices

local AutoDim = WidgetContainer:new{
    name = "autodim",
}

function AutoDim:init()
    self.autodim_starttime_m = G_reader_settings:readSetting("autodim_starttime_minutes", -1)
    self.autodim_duration_s = G_reader_settings:readSetting("autodim_duration_seconds", DEFAULT_AUTODIM_DURATION_S)
    self.autodim_endpercentage = G_reader_settings:readSetting("autodim_endpercentage", DEFAULT_AUTODIM_ENDPERCENTAGE)

    self.last_action_tv = UIManager:getElapsedTimeSinceBoot()

    self.ui.menu:registerToMainMenu(self)
    UIManager.event_hook:registerWidget("InputEvent", self)

    self:_schedule_autodim_task()
    self.isCurrentlyDimming = false -- true during or after the dimming ramp
end

function AutoDim:addToMainMenu(menu_items)
    menu_items.autodim = self:getAutodimMenu()
end

function AutoDim:getAutodimMenu()
    return {
        text = _("Automatic dimmer"),
        checked_func = function() return self.autodim_starttime_m > 0 end,
        sub_item_table = {
            {
                text_func = function()
                    return self.autodim_starttime_m <= 0 and _("Idle time for dimmer") or
                    T(_("Idle time for dimmer: %1 minutes"), self.autodim_starttime_m)
                end,
                checked_func = function() return self.autodim_starttime_m > 0 end,
                callback = function(touchmenu_instance)
                    local idle_dialog = SpinWidget:new{
                        title_text = _("Automatic dimmer idle time"),
                        info_text = _("Start the dimmer after the designated period of inactivity. Time is in minutes."),
                        value = self.autodim_starttime_m >=0 and self.autodim_starttime_m or 0.5,
                        default_value = DEFAULT_AUTODIM_STARTTIME_M,
                        value_min = 0.1,
                        value_max = 60,
                        value_step = 0.5,
                        value_hold_step = 5,
                        precision = "%0.1f",
                        ok_always_enabled = true,
                        callback = function(spin)
                            if not spin then return end
                            self.autodim_starttime_m = spin.value
                            G_reader_settings:saveSetting("autodim_starttime_minutes", spin.value)
                            self:_schedule_autodim_task()
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end,
                        extra_text = _("Disable"),
                        extra_callback = function()
                            self.autodim_starttime_m = -1
                            G_reader_settings:saveSetting("autodim_starttime_minutes", -1)
                            self:_schedule_autodim_task()
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end,
                    }
                    UIManager:show(idle_dialog)
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end,
                keep_menu_open = true,
            },
            {
                text_func = function()
                    return T(_("Dimmer duration: %1 seconds"), self.autodim_duration_s)
                end,
                enabled_func = function() return self.autodim_starttime_m > 0 end,
                callback = function(touchmenu_instance)
                    local dimmer_dialog = SpinWidget:new{
                        title_text = _("Automatic dimmer duration"),
                        info_text = _("Enter the duration until reaching the final brightness. Time is in seconds."),
                        value = self.autodim_duration_s,
                        default_value = DEFAULT_AUTODIM_DURATION_S,
                        value_min = 0,
                        value_max = 300,
                        value_step = 1,
                        value_hold_step = 10,
                        callback = function(spin)
                            if not spin then return end
                            self.autodim_duration_s = spin.value
                            G_reader_settings:saveSetting("autodim_duration_seconds", spin.value)
                            self:_schedule_autodim_task()
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end,
                    }
                    UIManager:show(dimmer_dialog)
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end,
                keep_menu_open = true,
            },
            {
                text_func = function()
                    return T(_("Dim to: %1%"), self.autodim_endpercentage)
                end,
                enabled_func = function() return self.autodim_starttime_m > 0 end,
                callback = function(touchmenu_instance)
                    local percentage_dialog = SpinWidget:new{
                        title_text = _("Dimming percentage"),
                        info_text = _("A percentage of the normal brightness."),
                        value = self.autodim_endpercentage,
                        value_default = DEFAULT_AUTODIM_ENDPERCENTAGE,
                        value_min = 0,
                        value_max = 100,
                        value_hold_step = 10,
                        callback = function(spin)
                            self.autodim_endpercentage = spin.value
                            G_reader_settings:saveSetting("autodim_endpercentage", spin.value)
                            self:_schedule_autodim_task()
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end,
                    }
                    UIManager:show(percentage_dialog)
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end,
                keep_menu_open = true,
            },
        }
    }
end

-- Schedules the first idle task, the consecutive ones are scheduled by the `autodim_task` itself.
-- `seconds` the initial scheduling delay of the first task
function AutoDim:_schedule_autodim_task(seconds)
    UIManager:unschedule(self.autodim_task)
    if self.autodim_starttime_m < 0 then
        return
    end

    seconds = seconds or self.autodim_starttime_m * 60
    UIManager:scheduleIn(seconds, self.autodim_task, self)
end

function AutoDim:onInputEvent()
    self.last_action_tv = UIManager:getElapsedTimeSinceBoot()

    if self.isCurrentlyDimming then
        Device.powerd:setIntensity(self.autodim_save_fl)

        self:_unschedule_ramp_task()
        self:_schedule_autodim_task()

        UIManager:discardEvents(1) -- stop discarding events
    end
end

function AutoDim:_unschedule_autodim_task()
    if self.isCurrentlyDimming then
        UIManager:unschedule(self.ramp_task)
        self.isCurrentlyDimming = false
    end
end

function AutoDim:onResume()
    if self.isCurrentlyDimming then
        Device.powerd:setIntensity(self.autodim_save_fl)
        self:_schedule_autodim_task()
        UIManager:discardEvents(1) -- stop discarding events
    end
end

function AutoDim:onSuspend()
    if self.isCurrentlyDimming then
        self:_unschedule_autodim_task()
        self:_unschedule_ramp_task()
        UIManager:discardEvents(1) -- stop discarding events
        self.isCurrentlyDimming = true -- message to self:onResume to go on with restoring
    end
end

function AutoDim:autodim_task()
    if self.isCurrentlyDimming then return end

    local now = UIManager:getElapsedTimeSinceBoot()
    local idle_duration =  now - self.last_action_tv
    local check_delay = TimeVal:new{ sec = self.autodim_starttime_m * 60} - idle_duration
    if check_delay:tonumber() <= 0 then
        self.autodim_save_fl = Device.powerd:frontlightIntensity()
        self.autodim_end_fl = math.floor(self.autodim_save_fl * self.autodim_endpercentage / 100 + 0.5)
        local fl_diff = self.autodim_save_fl - self.autodim_end_fl
        -- calculate time until the next decrease step
        self.autodim_step_time_s = math.max(self.autodim_duration_s / fl_diff, 0.001)
        self.ramp_event_countdown_startvalue = Device:hasEinkScreen() and
            math.floor((1/AUTODIM_EVENT_FREQUENCY) / self.autodim_step_time_s + 0.5) or 0
        self.ramp_event_countdown = self.ramp_event_countdown_startvalue

        UIManager:discardEvents(math.huge)
        self:ramp_task() -- which schedules itself
        -- Don't schedule `autodim_task` here, as this is done on the next `onInputEvent`
    else
        self:_schedule_autodim_task(check_delay:tonumber())
    end
end

function AutoDim:ramp_task()
    self.isCurrentlyDimming = true -- this will disable rescheduling of the `autodim_task`
    local fl_level = Device.powerd:frontlightIntensity()
    if fl_level > self.autodim_end_fl then
        Device.powerd:setIntensity(fl_level - 1, Device:hasEinkScreen()) -- don't generate event if eink-screen is present
        self.ramp_event_countdown = self.ramp_event_countdown - 1
        if Device:hasEinkScreen() and self.ramp_event_countdown <= 0 then
            -- generate event on every self.ramp_event_countdown calls
            UIManager:broadcastEvent(Event:new("FrontlightStateChanged"))
            self.ramp_event_countdown = self.ramp_event_countdown_startvalue
        end
        self:_schedule_ramp_task() -- Reschedule only if not ready
        -- `isCurrentlyDimming` stays true, to flag we have a dimmed FL.
    end
    if Device:hasEinkScreen() and fl_level == self.autodim_end_fl then
        -- generate event on the end of the ramp
        UIManager:broadcastEvent(Event:new("FrontlightStateChanged"))
    end
end

function AutoDim:_schedule_ramp_task()
    UIManager:scheduleIn(self.autodim_step_time_s, self.ramp_task, self)
end

function AutoDim:_unschedule_ramp_task()
    if self.isCurrentlyDimming then
        UIManager:unschedule(self.ramp_task)
        self.isCurrentlyDimming = false
    end
end

return AutoDim
