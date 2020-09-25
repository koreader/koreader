local DataStorage = require("datastorage")
local InfoMessage = require("ui/widget/infomessage")
local LuaSettings = require("luasettings")
local TimeWidget = require("ui/widget/timewidget")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local util = require("util")
local _ = require("gettext")
local N_ = _.ngettext
local T = require("ffi/util").template

local ReadTimer = WidgetContainer:new{
    name = "readtimer",
    time = 0,  -- The expected time of alarm if enabled, or 0.
    eyesaver = {
        -- 20 minutes:
        display_interval = 3600 / 3,
        display_time_clock = '', -- The expected time display if enabled, or ''
        enabled = false,
        settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/eyesaver_options.lua"),
        display_timestamp = 0,
        timed_display_callback = nil,
    },
}

function ReadTimer:init()
    self.alarm_callback = function()
        if self.time == 0 then return end -- How could this happen?
        self.time = 0
        UIManager:show(InfoMessage:new{
            text = T(_("Read timer alarm\nTime's up. It's %1 now."), os.date("%c")),
        })
    end
    self:initEyeSaver()
    self.ui.menu:registerToMainMenu(self)
end

function ReadTimer:initEyeSaver()
    self.eyesaver.display_time_clock = self.eyesaver.settings:readSetting("eyesaver_display_time_clock") or ""
    self.eyesaver.display_timestamp = self.eyesaver.settings:readSetting("eyesaver_timestamp") or 0
    self.eyesaver.enabled = self.eyesaver.settings:readSetting("eyesaver_enabled") or false

    self.eyesaver.timed_display_callback = function()
        if not self.eyesaver.enabled or not self:eyeSaverMessageScheduled() then
            return
        end -- How could this happen?

        self:eyeSaverShowMessage()
        self:eyeSaverScheduleTimeCompute()
        -- schedule the next display of a eyesaver message:
        self:eyeSaverSchedule()
    end

    if self.eyesaver.enabled and not self:eyeSaverMessageScheduled() then
        self:eyeSaverScheduleTimeCompute()
        -- schedule the next display of a eyesaver message:
        self:eyeSaverSchedule()
    end
end

function ReadTimer:scheduled()
    return self.time ~= 0
end

function ReadTimer:remainingMinutes()
    if self:scheduled() then
        return os.difftime(self.time, os.time()) / 60
    else
        return math.huge
    end
end

function ReadTimer:remainingTime()
    if self:scheduled() then
        local remain_time = os.difftime(self.time, os.time()) / 60
        local remain_hours = math.floor(remain_time / 60)
        local remain_minutes = math.floor(remain_time - 60 * remain_hours)
        return remain_hours, remain_minutes
    end
end

function ReadTimer:unschedule()
    if self:scheduled() then
        UIManager:unschedule(self.alarm_callback)
        self.time = 0
    end
end

function ReadTimer:eyeSaverScheduleTimeCompute()
    self.eyesaver.display_timestamp = os.time() + self.eyesaver.display_interval
    self.eyesaver.display_time_clock = os.date(_("%H:%M"), self.eyesaver.display_timestamp)
    self:eyeSaverSaveSettings()
end

function ReadTimer:eyeSaverSchedule()
    if not self.eyesaver.enabled then
        return
    end
    if not self:eyeSaverMessageScheduled() then
        self:eyeSaverScheduleTimeCompute()
    end
    UIManager:scheduleIn(self.eyesaver.display_interval, self.eyesaver.timed_display_callback)
end

-- when time for displaying the message was in a period in which the ereader "slept", adapt the new display time to be 20 minutes in the future again:
function ReadTimer:eyeSaverScheduleAdapt()
    if not self.eyesaver.enabled then
        return
    end
    if self.eyesaver.display_timestamp and self:eyeSaverMessageScheduled() and self.eyesaver.display_timestamp < os.time() then
        self:eyeSaverUnschedule();
        self:eyeSaverScheduleTimeCompute()
        self:eyeSaverSchedule();
    end
end

function ReadTimer:eyeSaverUnschedule()
    if self:eyeSaverMessageScheduled() then
        UIManager:unschedule(self.eyesaver.timed_display_callback)
    end
    self:eyeSaverResetTimer()
end

function ReadTimer:eyeSaverMessageScheduled()
    return self.eyesaver.display_timestamp > 0
end

function ReadTimer:eyeSaverResetTimer()
    self.eyesaver.display_timestamp = 0
    self.eyesaver.display_time_clock = ''
    self:eyeSaverSaveSettings()
end

function ReadTimer:eyeSaverSaveSettings()
    self.eyesaver.settings:saveSetting("eyesaver_timestamp", self.eyesaver.display_timestamp)
    self.eyesaver.settings:saveSetting("eyesaver_display_time_clock", self.eyesaver.display_time_clock)
    self.eyesaver.settings:flush()
end

function ReadTimer:eyeSaverToggleMessages()
    self.eyesaver.enabled = not self.eyesaver.enabled
    if self.eyesaver.enabled then
        self.eyesaver.settings:saveSetting("eyesaver_enabled", true)
        if not self:eyeSaverMessageScheduled() then
            self:eyeSaverSchedule()
        end
    else
        self:eyeSaverUnschedule()
        self.eyesaver.settings:saveSetting("eyesaver_enabled", false)
    end
end

function ReadTimer:eyeSaverShowMessage()
    UIManager:show(InfoMessage:new {
        text = _("Look 20 seconds into the distance.\n\nAfter this period the current message will disappear…"),
        timeout = 20
    })
end

-- when resuming, reset the timer to 20 minutes delay from waking:
function ReadTimer:onResume()
    self:eyeSaverScheduleAdapt()
end

function ReadTimer:onSuspend()
    self:eyeSaverUnschedule()
end

function ReadTimer:onCloseWidget()
    self:eyeSaverResetTimer()
end

function ReadTimer:addToMainMenu(menu_items)
    menu_items.read_timer = {
        text_func = function()
            if self:scheduled() then
                return T(_("Read timer (%1m)"),
                    string.format("%.2f", self:remainingMinutes()))
            else
                return _("Read timer")
            end
        end,
        checked_func = function()
            return self:scheduled()
        end,
        sub_item_table = {
            {
                text = _("Time"),
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local now_t = os.date("*t")
                    local curr_hour = now_t.hour
                    local curr_min = now_t.min
                    local curr_sec_from_midnight = curr_hour*3600 + curr_min*60
                    local time_widget = TimeWidget:new{
                        hour = curr_hour,
                        min = curr_min,
                        ok_text = _("Set timer"),
                        title_text =  _("Set reader timer"),
                        callback = function(time)
                            touchmenu_instance:closeMenu()
                            self:unschedule()
                            local timer_sec_from_mignight = time.hour*3600 + time.min*60
                            local seconds
                            if timer_sec_from_mignight > curr_sec_from_midnight then
                                seconds = timer_sec_from_mignight - curr_sec_from_midnight
                            else
                                seconds = 24*3600 - (curr_sec_from_midnight - timer_sec_from_mignight)
                            end
                            if seconds > 0 and seconds < 18*3600 then
                                self.time = os.time() + seconds
                                UIManager:scheduleIn(seconds, self.alarm_callback)
                                local hr_str = ""
                                local min_str = ""
                                local hr = math.floor(seconds/3600)
                                if hr > 0 then
                                    hr_str = T(N_("1 hour", "%1 hours", hr), hr)
                                end
                                local min = math.floor((seconds%3600)/60)
                                if min > 0 then
                                    min_str = T(N_("1 minute", "%1 minutes", min), min)
                                    if hr_str ~= "" then
                                        hr_str = hr_str .. " "
                                    end
                                end
                                UIManager:show(InfoMessage:new{
                                    text = T(_("Timer set to: %1:%2.\n\nThat's %3%4 from now."),
                                        string.format("%02d", time.hour), string.format("%02d", time.min),
                                        hr_str, min_str),
                                    timeout = 5,
                                })
                            --current time or time > 18h
                            elseif seconds == 0 or seconds >= 18*3600 then
                                UIManager:show(InfoMessage:new{
                                    text = _("Timer could not be set. You have selected current time or time in past"),
                                    timeout = 5,
                                })
                            end
                        end
                    }
                    UIManager:show(time_widget)
                end,
            },
            {
                text = _("Minutes from now"),
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
                    local time_widget = TimeWidget:new{
                        hour = remain_hours or 0,
                        min = remain_minutes or 0,
                        hour_max = 17,
                        ok_text = _("Set timer"),
                        title_text =  _("Set reader timer from now (hours:minutes)"),
                        callback = function(time)
                            touchmenu_instance:closeMenu()
                            self:unschedule()
                            local seconds = time.hour * 3600 + time.min * 60
                            if seconds > 0 then
                                self.time = os.time() + seconds
                                UIManager:scheduleIn(seconds, self.alarm_callback)
                                local hr_str = ""
                                local min_str = ""
                                local hr = time.hour
                                if hr > 0 then
                                    hr_str = T(N_("1 hour", "%1 hours", hr), hr)
                                end
                                local min = time.min
                                if min > 0 then
                                    min_str = T(N_("1 minute", "%1 minutes", min), min)
                                    if hr_str ~= "" then
                                        hr_str = hr_str .. " "
                                    end
                                end
                                UIManager:show(InfoMessage:new{
                                    text = T(_("Timer set for %1%2."), hr_str, min_str),
                                    timeout = 5,
                                })
                                remain_time = {hr, min}
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
                    self:unschedule()
                    touchmenu_instance:updateItems()
                end,
            },
            {
                text_func = function()
                    local time_info_txt = util.secondsToHour(self.eyesaver.display_timestamp, G_reader_settings:nilOrTrue("twelve_hour_clock"))
                    return self.eyesaver.enabled and string.format(_("EyeSaver messages - next display %s"), time_info_txt) or _("EyeSaver messages")
                end,
                checked_func = function()
                    return self.eyesaver.enabled
                end,
                callback = function()
                    self:eyeSaverToggleMessages()
                end,
            },
        },
    }
end

return ReadTimer
