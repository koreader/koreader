local CheckButton = require("ui/widget/checkbutton")
local ConfirmBox = require("ui/widget/confirmbox")
local DateTimeWidget = require("ui/widget/datetimewidget")
local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local datetime = require("datetime")
local time = require("ui/time")
local _ = require("gettext")
local T = require("ffi/util").template

local ReadTimer = WidgetContainer:extend{
    name = "readtimer",
    time = 0,  -- The expected time of alarm if enabled, or 0.
    last_interval_time = 0,
}

function ReadTimer:init()
    self.timer_symbol = "\u{23F2}"  -- ⏲ timer symbol
    self.timer_letter = "T"

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

    self.additional_header_content_func = function()
        if self:scheduled() then
            local hours, minutes, dummy = self:remainingTime(1)
            local timer_info = string.format("%02d:%02d", hours, minutes)
            return self.timer_symbol .. timer_info
        end
        return
    end

    self.additional_footer_content_func = function()
        if self:scheduled() then
            local item_prefix = self.ui.view.footer.settings.item_prefix
            local hours, minutes, dummy = self:remainingTime(1)
            local timer_info = string.format("%02d:%02d", hours, minutes)

            if item_prefix == "icons" then
                return self.timer_symbol .. " " .. timer_info
            elseif item_prefix == "compact_items" then
                return self.timer_symbol .. timer_info
            else
                return self.timer_letter .. ": " .. timer_info
            end
        end
        return
    end

    self.show_value_in_header = G_reader_settings:readSetting("readtimer_show_value_in_header")
    self.show_value_in_footer = G_reader_settings:readSetting("readtimer_show_value_in_footer")

    if self.show_value_in_header then
        self:addAdditionalHeaderContent()
    end

    if self.show_value_in_footer then
        self:addAdditionalFooterContent()
    end

    self.ui.menu:registerToMainMenu(self)
end

function ReadTimer:update_status_bars(seconds)
    if self.show_value_in_header then
        UIManager:broadcastEvent(Event:new("UpdateHeader"))
    end
    if self.show_value_in_footer then
        UIManager:broadcastEvent(Event:new("RefreshAdditionalContent"))
    end
    -- if seconds schedule 1ms later
    if seconds and seconds >= 0 then
        UIManager:scheduleIn(math.max(math.floor(seconds)%60, 0.001), self.update_status_bars, self)
    elseif seconds and seconds < 0 and self:scheduled() then
        UIManager:scheduleIn(math.max(math.floor(self:remaining())%60, 0.001), self.update_status_bars, self)
    else
        UIManager:scheduleIn(60, self.update_status_bars, self)
    end
end

function ReadTimer:scheduled()
    return self.time ~= 0
end

function ReadTimer:remaining()
    if self:scheduled() then
        -- Resolution: time.now() subsecond, os.time() two seconds
        local remaining_s = time.to_s(self.time - time.now())
        if remaining_s > 0 then
            return remaining_s
        else
            return 0
        end
    else
        return math.huge
    end
end

-- can round
function ReadTimer:remainingTime(round)
    if self:scheduled() then
        local remainder = self:remaining()
        if round then
            if round < 0 then -- round down
                remainder = remainder - 59
            elseif round == 0 then
                remainder = remainder + 30
            else -- round up
                remainder = remainder + 59
            end
            remainder = math.floor(remainder * (1/60)) * 60
        end

        local hours = math.floor(remainder * (1/3600))
        local minutes = math.floor(remainder % 3600 * (1/60))
        local seconds = math.floor(remainder % 60)
        return hours, minutes, seconds
    end
end

function ReadTimer:addAdditionalHeaderContent()
    if self.ui.crelistener then
        self.ui.crelistener:addAdditionalHeaderContent(self.additional_header_content_func)
        self:update_status_bars(-1)
    end
end
function ReadTimer:addAdditionalFooterContent()
    if self.ui.view then
        self.ui.view.footer:addAdditionalFooterContent(self.additional_footer_content_func)
        self:update_status_bars(-1)
    end
end

function ReadTimer:removeAdditionalHeaderContent()
    if self.ui.crelistener then
        self.ui.crelistener:removeAdditionalHeaderContent(self.additional_header_content_func)
        self:update_status_bars(-1)
        UIManager:broadcastEvent(Event:new("UpdateHeader"))
    end
end

function ReadTimer:removeAdditionalFooterContent()
    if self.ui.view then
        self.ui.view.footer:removeAdditionalFooterContent(self.additional_footer_content_func)
        self:update_status_bars(-1)
        UIManager:broadcastEvent(Event:new("UpdateFooter", true))
    end
end

function ReadTimer:unschedule()
    if self:scheduled() then
        UIManager:unschedule(self.alarm_callback)
        self.time = 0
    end
    UIManager:unschedule(self.update_status_bars, self)
end

function ReadTimer:rescheduleIn(seconds)
    -- Resolution: time.now() subsecond, os.time() two seconds
    self.time = time.now() + time.s(seconds)
    UIManager:scheduleIn(seconds, self.alarm_callback)
    if self.show_value_in_header or self.show_value_in_footer then
        self:update_status_bars(seconds)
    end
end

function ReadTimer:addCheckboxes(widget)
    local checkbox_header = CheckButton:new{
        text = _("Show timer in alt status bar"),
        checked = self.show_value_in_header,
        parent = widget,
        callback = function()
            self.show_value_in_header = not self.show_value_in_header
            G_reader_settings:saveSetting("readtimer_show_value_in_header", self.show_value_in_header)
            if self.show_value_in_header then
                self:addAdditionalHeaderContent()
            else
                self:removeAdditionalHeaderContent()
            end
        end,
    }
    local checkbox_footer = CheckButton:new{
        text = _("Show timer in status bar"),
        checked = self.show_value_in_footer,
        parent = widget,
        callback = function()
            self.show_value_in_footer = not self.show_value_in_footer
            G_reader_settings:saveSetting("readtimer_show_value_in_footer", self.show_value_in_footer)
            if self.show_value_in_footer then
                self:addAdditionalFooterContent()
            else
                self:removeAdditionalFooterContent()
            end
        end,
    }
    widget:addWidget(checkbox_header)
    widget:addWidget(checkbox_footer)
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
                        callback = function(alarm_time)
                            self.last_interval_time = 0
                            self:unschedule()
                            local then_t = now_t
                            then_t.hour = alarm_time.hour
                            then_t.min = alarm_time.min
                            then_t.sec = 0
                            local seconds = os.difftime(os.time(then_t), os.time())
                            if seconds > 0 then
                                self:rescheduleIn(seconds)
                                local user_duration_format = G_reader_settings:readSetting("duration_format")
                                UIManager:show(InfoMessage:new{
                                    -- @translators %1:%2 is a clock time (HH:MM), %3 is a duration
                                    text = T(_("Timer set for %1:%2.\n\nThat's %3 from now."),
                                        string.format("%02d", alarm_time.hour), string.format("%02d", alarm_time.min),
                                        datetime.secondsToClockDuration(user_duration_format, seconds, false)),
                                    timeout = 5,
                                })
                                if touchmenu_instance then touchmenu_instance:updateItems() end
                            else
                                UIManager:show(InfoMessage:new{
                                    text = _("Timer could not be set. The selected time is in the past."),
                                    timeout = 5,
                                })
                            end
                        end
                    }
                    self:addCheckboxes(time_widget)
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
                        callback = function(timer_time)
                            self:unschedule()
                            local seconds = timer_time.hour * 3600 + timer_time.min * 60
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
                                remain_time = {timer_time.hour, timer_time.min}
                                G_reader_settings:saveSetting("reader_timer_remain_time", remain_time)
                                if touchmenu_instance then touchmenu_instance:updateItems() end
                            end
                        end
                    }

                    self:addCheckboxes(time_widget)
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
