local DateTimeWidget = require("ui/widget/datetimewidget")
local InfoMessage = require("ui/widget/infomessage")
local ConfirmBox = require("ui/widget/confirmbox")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local datetime = require("datetime")
local _ = require("gettext")
local T = require("ffi/util").template

local ReadTimer = WidgetContainer:extend{
    name = "readtimer",
    time = 0,  -- The expected time of alarm if enabled, or 0.
    last_interval_time = 0,
}

function ReadTimer:init()
    self.alarm_callback = function()
        -- Don't do anything if we were unscheduled
        if self.time == 0 then return end

        self.time = 0
        local tip_text = _("Time is up")
        local confirm_box
        -- only interval support repeat
        if self.last_interval_time > 0 then
            logger.dbg("can_repeat, show confirm_box")
            confirm_box = ConfirmBox:new{
                text = tip_text,
                ok_text = _("Repeat"),
                ok_callback = function()
                    logger.dbg("Schedule a new time:", self.last_interval_time)
                    UIManager:close(confirm_box)
                    self:rescheduleIn(self.last_interval_time)
                end,
                cancel_text = _("Done"),
                cancel_callback = function ()
                    self.last_interval_time = 0
                end,
            }
            UIManager:show(confirm_box)
        else
            logger.dbg("can`t_repeat, show infomessage")
            UIManager:show(InfoMessage:new{
                    text = tip_text,
            })
        end
    end
    self.ui.menu:registerToMainMenu(self)
end

function ReadTimer:scheduled()
    return self.time ~= 0
end

function ReadTimer:remaining()
    if self:scheduled() then
        local td = os.difftime(self.time, os.time())
        if td > 0 then
            return td
        else
            return 0
        end
    else
        return math.huge
    end
end

function ReadTimer:remainingTime()
    if self:scheduled() then
        local remainder = self:remaining()
        local hours = math.floor(remainder * (1/3600))
        local minutes = math.floor(remainder % 3600 * (1/60))
        local seconds = math.floor(remainder % 60)
        return hours, minutes, seconds
    end
end

function ReadTimer:unschedule()
    if self:scheduled() then
        UIManager:unschedule(self.alarm_callback)
        self.time = 0
    end
end

function ReadTimer:rescheduleIn(seconds)
    self.time = os.time() + seconds
    UIManager:scheduleIn(seconds, self.alarm_callback)
end

function ReadTimer:addToMainMenu(menu_items)
    menu_items.read_timer = {
        text_func = function()
            if self:scheduled() then
                local user_duration_format = G_reader_settings:readSetting("duration_format")
                return T(_("Read timer (%1)"),
                    datetime.secondsToClockDuration(user_duration_format, self:remaining(), false))
            else
                return _("Read timer")
            end
        end,
        checked_func = function()
            return self:scheduled()
        end,
        sub_item_table = {
            {
                text = _("Set time"),
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local now_t = os.date("*t")
                    local curr_hour = now_t.hour
                    local curr_min = now_t.min
                    local time_widget = DateTimeWidget:new{
                        hour = curr_hour,
                        min = curr_min,
                        ok_text = _("Set alarm"),
                        title_text =  _("New alarm"),
                        info_text = _("Enter a time in hours and minutes."),
                        callback = function(time)
                            self.last_interval_time = 0
                            touchmenu_instance:closeMenu()
                            self:unschedule()
                            local then_t = now_t
                            then_t.hour = time.hour
                            then_t.min = time.min
                            then_t.sec = 0
                            local seconds = os.difftime(os.time(then_t), os.time())
                            if seconds > 0 then
                                self:rescheduleIn(seconds)
                                local user_duration_format = G_reader_settings:readSetting("duration_format")
                                UIManager:show(InfoMessage:new{
                                    -- @translators %1:%2 is a clock time (HH:MM), %3 is a duration
                                    text = T(_("Timer set for %1:%2.\n\nThat's %3 from now."),
                                        string.format("%02d", time.hour), string.format("%02d", time.min),
                                        datetime.secondsToClockDuration(user_duration_format, seconds, false)),
                                    timeout = 5,
                                })
                            else
                                UIManager:show(InfoMessage:new{
                                    text = _("Timer could not be set. The selected time is in the past."),
                                    timeout = 5,
                                })
                            end
                        end
                    }
                    UIManager:show(time_widget)
                end,
            },
            {
                text = _("Set interval"),
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local remain_time = {}
                    local remain_hours, remain_minutes = self:remainingTime()
                    if not remain_hours and not remain_minutes then
                        remain_time = G_reader_settings:readSetting("reader_timer_remain_time")
                        if remain_time then
                            remain_hours = remain_time[1]
                            remain_minutes = remain_time[2]
                        end
                    end
                    local time_widget = DateTimeWidget:new{
                        hour = remain_hours or 0,
                        min = remain_minutes or 0,
                        hour_max = 17,
                        ok_text = _("Set timer"),
                        title_text =  _("Set reader timer"),
                        info_text = _("Enter a time in hours and minutes."),
                        callback = function(time)
                            touchmenu_instance:closeMenu()
                            self:unschedule()
                            local seconds = time.hour * 3600 + time.min * 60
                            if seconds > 0 then
                                self.last_interval_time = seconds
                                self:rescheduleIn(seconds)
                                local user_duration_format = G_reader_settings:readSetting("duration_format")
                                UIManager:show(InfoMessage:new{
                                    -- @translators This is a duration
                                    text = T(_("Timer will expire in %1."),
                                             datetime.secondsToClockDuration(user_duration_format, seconds, true)),
                                    timeout = 5,
                                })
                                remain_time = {time.hour, time.min}
                                G_reader_settings:saveSetting("reader_timer_remain_time", remain_time)
                            end
                        end
                    }
                    UIManager:show(time_widget)
                end,
            },
            {
                text = _("Stop timer"),
                keep_menu_open = true,
                enabled_func = function()
                    return self:scheduled()
                end,
                callback = function(touchmenu_instance)
                    self.last_interval_time = 0
                    self:unschedule()
                    touchmenu_instance:updateItems()
                end,
            },
        },
    }
end

-- The UI ticks on a MONOTONIC time domain, while this plugin deals with REAL wall clock time.
function ReadTimer:onResume()
    if self:scheduled() then
        logger.dbg("ReadTimer: onResume with an active timer")
        local remainder = self:remaining()

        if remainder == 0 then
            -- Make sure we fire the alarm right away if it expired during suspend...
            self:alarm_callback()
            self:unschedule()
        else
            -- ...and that we re-schedule the timer against the REAL time if it's still ticking.
            logger.dbg("ReadTimer: Rescheduling in", remainder, "seconds")
            self:unschedule()
            self:rescheduleIn(remainder)
        end

    end
end

return ReadTimer
