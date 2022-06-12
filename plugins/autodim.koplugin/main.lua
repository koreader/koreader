--[[--
Plugin for automatic dimming of the frontlight after an idle period.

@module koplugin.autodim
--]]--

local Device = require("device")
local Event = require("ui/event")
local FFIUtil = require("ffi/util")
local SpinWidget = require("ui/widget/spinwidget")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local TrapWidget = require("ui/widget/trapwidget")
local time = require("ui/time")
local util = require("util")
local _ = require("gettext")
local C_ = _.pgettext
local T = FFIUtil.template

local DEFAULT_AUTODIM_STARTTIME_M = 5
local DEFAULT_AUTODIM_DURATION_S = 5
local DEFAULT_AUTODIM_FRACTION = 20
local AUTODIM_EVENT_FREQUENCY = 2 -- in Hz; Frequenzy for FrontlightChangedEvent on E-Ink devices

local AutoDim = WidgetContainer:new{ name = "autodim" }

function AutoDim:init()
    self.autodim_starttime_m = G_reader_settings:readSetting("autodim_starttime_minutes", -1)
    self.autodim_duration_s = G_reader_settings:readSetting("autodim_duration_seconds", DEFAULT_AUTODIM_DURATION_S)
    self.autodim_fraction = G_reader_settings:readSetting("autodim_fraction", DEFAULT_AUTODIM_FRACTION)

    self.last_action_time = UIManager:getElapsedTimeSinceBoot()

    self.ui.menu:registerToMainMenu(self)
    UIManager.event_hook:registerWidget("InputEvent", self)

    self:_schedule_autodim_task()
    self.isCurrentlyDimming = false -- true during or after the dimming ramp
    self.trap_widget = nil

    self.top_widget_before_dim = nil
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
                    T(_("Idle time for dimmer: %1"),
                        util.secondsToClockDuration("modern", self.autodim_starttime_m * 60, false, true, false, true))
                end,
                checked_func = function() return self.autodim_starttime_m > 0 end,
                callback = function(touchmenu_instance)
                    local idle_dialog = SpinWidget:new{
                        title_text = _("Automatic dimmer idle time"),
                        info_text = _("Start the dimmer after the designated period of inactivity."),
                        value = self.autodim_starttime_m >=0 and self.autodim_starttime_m or 0.5,
                        default_value = DEFAULT_AUTODIM_STARTTIME_M,
                        value_min = 0.5,
                        value_max = 60,
                        value_step = 0.5,
                        value_hold_step = 5,
                        unit = C_("Time", "min"),
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
                    return T(_("Dimmer duration: %1"),
                        util.secondsToClockDuration("modern", self.autodim_duration_s, false, true, false, true))
                end,
                enabled_func = function() return self.autodim_starttime_m > 0 end,
                callback = function(touchmenu_instance)
                    local dimmer_dialog = SpinWidget:new{
                        title_text = _("Automatic dimmer duration"),
                        info_text = _("Delay to reach the lowest brightness."),
                        value = self.autodim_duration_s,
                        default_value = DEFAULT_AUTODIM_DURATION_S,
                        value_min = 0,
                        value_max = 300,
                        value_step = 1,
                        value_hold_step = 10,
                        precision = "%1d",
                        unit = C_("Time", "s"),
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
                    return T(_("Dim to %1 % of the regular brightness"), self.autodim_fraction)
                end,
                enabled_func = function() return self.autodim_starttime_m > 0 end,
                callback = function(touchmenu_instance)
                    local percentage_dialog = SpinWidget:new{
                        title_text = _("Dim to percentage"),
                        info_text = _("The lowest brightness as a percentage of the regular brightness."),
                        value = self.autodim_fraction,
                        value_default = DEFAULT_AUTODIM_FRACTION,
                        value_min = 0,
                        value_max = 100,
                        value_hold_step = 10,
                        unit = "%",
                        callback = function(spin)
                            self.autodim_fraction = spin.value
                            G_reader_settings:saveSetting("autodim_fraction", spin.value)
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

function AutoDim:restoreFrontlight()
    Device.powerd:setIntensity(self.autodim_save_fl)
    self:updateFooter(true)
    self:_unschedule_ramp_task()
    self:_schedule_autodim_task()
end

function AutoDim:onInputEvent()
    self.last_action_time = UIManager:getElapsedTimeSinceBoot()
end

function AutoDim:_unschedule_autodim_task()
    if self.isCurrentlyDimming then
        UIManager:unschedule(self.ramp_task)
        self.isCurrentlyDimming = false
    end
end

function AutoDim:onResume()
    self.last_action_time = UIManager:getElapsedTimeSinceBoot()
    if self.isCurrentlyDimming then
        if self.trap_widget then
            UIManager:close(self.trap_widget)
            self.trap_widget = nil
            self.widget_before_dim = nil
        end
        UIManager:scheduleIn(1, function()
            Device.powerd:setIntensity(self.autodim_save_fl)
            self:updateFooter(true)
        end)
        self.isCurrentlyDimming = false
    end
    self:_schedule_autodim_task()
end

function AutoDim:onSuspend()
    if self.isCurrentlyDimming then
        self:_unschedule_autodim_task()
        self:_unschedule_ramp_task()
        self.isCurrentlyDimming = true -- message to self:onResume to go on with restoring
    end
end

function AutoDim:updateFooter(clear)
    -- update footer only if it is not covered by another widget
    if self.top_widget_before_dim == "ReaderUI" or
        (self.top_widget_before_dim ~= "ConfigDialog" and self.top_widget_before_dim ~= "ScreenSaver"
        and self.top_widget_before_dim ~= "VirtualKeyboard") then

        UIManager:broadcastEvent(Event:new("UpdateFooter", self.view and self.view.footer_visible or false))
    end
    if clear then
        self.top_widget_before_dim = nil
    end
end

function AutoDim:autodim_task()
    if self.isCurrentlyDimming then return end

    local now = UIManager:getElapsedTimeSinceBoot()
    local idle_duration = now - self.last_action_time
    local check_delay = time.s(self.autodim_starttime_m * 60) - idle_duration
    if check_delay <= 0 then
        self.trap_widget = TrapWidget:new{
            dismiss_callback = function()
                self:restoreFrontlight()
                self.trap_widget = nil
            end
        }

        -- This is the active widget before showing self.trap_widget
        self.top_widget_before_dim = UIManager:getTopWidget()

        UIManager:show(self.trap_widget) -- suppress taps during dimming

        self.autodim_save_fl = Device.powerd:frontlightIntensity()
        self.autodim_end_fl = math.floor(self.autodim_save_fl * self.autodim_fraction / 100 + 0.5)
        -- Clamp `self.autodim_end_fl` to 1 if `self.autodim_fraction` ~= 0
        if self.autodim_fraction ~= 0 and self.autodim_end_fl == 0 then
            self.autodim_end_fl = 1
        end
        local fl_diff = self.autodim_save_fl - self.autodim_end_fl
        -- calculate time until the next decrease step
        self.autodim_step_time_s = math.max(self.autodim_duration_s / fl_diff, 0.001)
        self.ramp_event_countdown_startvalue = Device:hasEinkScreen() and
            math.floor((1/AUTODIM_EVENT_FREQUENCY) / self.autodim_step_time_s + 0.5) or 0
        self.ramp_event_countdown = self.ramp_event_countdown_startvalue

        self:ramp_task() -- which schedules itself
        -- Don't schedule `autodim_task` here, as this is done in `trap_widget.dismiss_callback` or in `onResume`
    else
        self:_schedule_autodim_task(time.to_s(check_delay))
    end
end

function AutoDim:ramp_task()
    self.isCurrentlyDimming = true -- this will disable rescheduling of the `autodim_task`
    local fl_level = Device.powerd:frontlightIntensity()
    if fl_level > self.autodim_end_fl then
        Device.powerd:setIntensity(fl_level - 1)
        self.ramp_event_countdown = self.ramp_event_countdown - 1
        if self.ramp_event_countdown <= 0 then
            -- Update footer on every self.ramp_event_countdown call
            self:updateFooter()
            self.ramp_event_countdown = self.ramp_event_countdown_startvalue
        end
        self:_schedule_ramp_task() -- Reschedule only if not ready
        -- `isCurrentlyDimming` stays true, to flag we have a dimmed FL.
    end
    if fl_level == self.autodim_end_fl and self.ramp_event_countdown_startvalue > 0 then
        -- Update footer at the end of the ramp.
        self:updateFooter()
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
