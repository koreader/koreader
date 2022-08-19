--[[--
Plugin for setting screen warmth based on the sun position and/or a time schedule

@module koplugin.autowarmth
--]]--

local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local DateTimeWidget = require("ui/widget/datetimewidget")
local DoubleSpinWidget = require("/ui/widget/doublespinwidget")
local DeviceListener = require("device/devicelistener")
local Dispatcher = require("dispatcher")
local Event = require("ui/event")
local FFIUtil = require("ffi/util")
local Font = require("ui/font")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Notification = require("ui/widget/notification")
local SpinWidget = require("ui/widget/spinwidget")
local SunTime = require("suntime")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local _ = require("gettext")
local C_ = _.pgettext
local Powerd = Device.powerd
local T = FFIUtil.template
local Screen = require("device").screen
local util = require("util")

local activate_sun = 1
local activate_schedule = 2
local activate_closer_noon = 3
local activate_closer_midnight = 4

local midnight_index = 11

local device_max_warmth = Device:hasNaturalLight() and Powerd.fl_warmth_max or 100
local device_warmth_fit_scale = device_max_warmth / 100

local function frac(x)
    return x - math.floor(x)
end

local AutoWarmth = WidgetContainer:new{
    name = "autowarmth",
    sched_times_s = {},
    sched_warmths = {},
    fl_turned_off = nil -- true/false if autowarmth has toggled the frontlight
}

-- get timezone offset in hours (including dst)
function AutoWarmth:getTimezoneOffset()
    local utcdate   = os.date("!*t")
    local localdate = os.date("*t")
    return os.difftime(os.time(localdate), os.time(utcdate))/3600
end

function AutoWarmth:init()
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)

    self.easy_mode = G_reader_settings:nilOrTrue("autowarmth_easy_mode")
    self.activate = G_reader_settings:readSetting("autowarmth_activate") or 0
    self.location = G_reader_settings:readSetting("autowarmth_location") or "Geysir"
    self.latitude = G_reader_settings:readSetting("autowarmth_latitude") or 64.31 --great Geysir in Iceland
    self.longitude = G_reader_settings:readSetting("autowarmth_longitude") or -20.30
    self.altitude = G_reader_settings:readSetting("autowarmth_altitude") or 200
    self.timezone = G_reader_settings:readSetting("autowarmth_timezone") or 0
    self.scheduler_times = G_reader_settings:readSetting("autowarmth_scheduler_times")
        or {0.0, 5.5, 6.0, 6.5, 7.0, 13.0, 21.5, 22.0, 22.5, 23.0, 24.0}
    self.warmth = G_reader_settings:readSetting("autowarmth_warmth")
        or { 90, 90, 80, 60, 20, 20, 20, 60, 80, 90, 90}
    self.fl_off_during_day = G_reader_settings:readSetting("autowarmth_fl_off_during_day")

    -- schedule recalculation shortly afer midnight
    self:scheduleMidnightUpdate()
end

function AutoWarmth:onDispatcherRegisterActions()
    Dispatcher:registerAction("show_ephemeris",
        {category="none", event="ShowEphemeris", title=_("Show ephemeris"), general=true})
    Dispatcher:registerAction("auto_warmth_off",
        {category="none", event="AutoWarmthOff", title=_("Auto warmth off"), screen=true})
    Dispatcher:registerAction("auto_warmth_cycle_trough",
        {category="none", event="AutoWarmthMode", title=_("Auto warmth cycle through modes"), screen=true})
end

function AutoWarmth:onShowEphemeris()
    self:showTimesInfo(_("Information about the sun in"), true, activate_sun, false)
end

function AutoWarmth:onAutoWarmthOff()
    self.activate = 0
    G_reader_settings:saveSetting("autowarmth_activate", self.activate)
    Notification:notify(_("Auto warmth turned off"))
    self:scheduleMidnightUpdate()
end

function AutoWarmth:onAutoWarmthMode()
    if self.activate > 0 then
        self.activate = self.activate - 1
    else
        self.activate = activate_closer_midnight
    end
    local notify_text
    if self.activate == 0 then
        notify_text = _("Auto warmth turned off")
    elseif self.activate == activate_sun then
        notify_text = _("Auto warmth use sun position")
    elseif self.activate == activate_schedule then
        notify_text = _("Auto warmth use schedule")
    elseif self.activate == activate_closer_midnight then
        notify_text = _("Auto warmth use whatever is closer to midnight")
    elseif self.activate == activate_closer_noon then
        notify_text = _("Auto warmth use whatever is closer to noon")
    end
    G_reader_settings:saveSetting("autowarmth_activate", self.activate)
    Notification:notify(notify_text)
    self:scheduleMidnightUpdate()
end

function AutoWarmth:leavePowerSavingState(from_resume)
    logger.dbg("AutoWarmth: onResume/onLeaveStandby")
    local resume_date = os.date("*t")

    -- check if resume and suspend are done on the same day
    if resume_date.day == SunTime.date.day and resume_date.month == SunTime.date.month
        and resume_date.year == SunTime.date.year then
        local now_s = SunTime:getTimeInSec(resume_date)
        self:scheduleNextWarmthChange(now_s, self.sched_warmth_index > 1 and self.sched_warmth_index - 1 or 1, from_resume)
        -- Reschedule 1sec after midnight
        UIManager:scheduleIn(24*3600 + 1 - now_s, self.scheduleMidnightUpdate, self)
    else
        self:scheduleMidnightUpdate(from_resume) -- resume is on the other day, do all calcs again
    end
end

function AutoWarmth:_onResume()
    self:leavePowerSavingState(true)
end

function AutoWarmth:_onLeaveStandby()
    self:leavePowerSavingState(false)
end

function AutoWarmth:_onSuspend()
    UIManager:unschedule(self.scheduleMidnightUpdate)
    UIManager:unschedule(self.setWarmth)
end

AutoWarmth._onEnterStandby = AutoWarmth._onSuspend

function AutoWarmth:setEventHandlers()
    self.onResume = self._onResume
    self.onSuspend = self._onSuspend
    self.onEnterStandby = self._onEnterStandby
    self.onLeaveStandby = self._onLeaveStandby
end

function AutoWarmth:clearEventHandlers()
    self.onResume = nil
    self.onSuspend = nil
    self.onEnterStandby = nil
    self.onLeaveStandby = nil
end

-- from_resume ... true if called from onResume
function AutoWarmth:scheduleMidnightUpdate(from_resume)
    logger.dbg("AutoWarmth: scheduleMidnightUpdate")
    -- first unschedule all old functions
    UIManager:unschedule(self.scheduleMidnightUpdate)
    UIManager:unschedule(AutoWarmth.setWarmth)

    SunTime:setPosition(self.location, self.latitude, self.longitude, self.timezone, self.altitude, true)
    SunTime:setAdvanced()
    SunTime:setDate() -- today
    SunTime:calculateTimes() -- calculates times in hours

    self.sched_times_s = {}
    self.sched_warmths = {}
    self.fl_turned_off = nil

    local function prepareSchedule(times_h, index1, index2)
        local time1_h = times_h[index1]
        if not time1_h then return end

        local time1_s = SunTime:getTimeInSec(time1_h)
        self.sched_times_s[#self.sched_times_s + 1] = time1_s
        self.sched_warmths[#self.sched_warmths + 1] = self.warmth[index1]

        local time2_h = times_h[index2]
        if not time2_h then return end -- to near to the pole
        local warmth_diff = math.min(self.warmth[index2], 100) - math.min(self.warmth[index1], 100)
        local time_diff_s = SunTime:getTimeInSec(time2_h) - time1_s
        if warmth_diff ~= 0 and time_diff_s > 0 then
            local delta_t = time_diff_s / math.abs(warmth_diff) -- cannot be inf, no problem
            local delta_w = warmth_diff > 0 and 1 or -1
            for i = 1, math.abs(warmth_diff) - 1 do
                local next_warmth = math.min(self.warmth[index1], 100) + delta_w * i
                -- only apply warmth for steps the hardware has (e.g. Tolino has 0-10 hw steps
                -- which map to warmth 0, 10, 20, 30 ... 100)
                if frac(next_warmth * device_warmth_fit_scale) == 0 then
                    table.insert(self.sched_times_s, time1_s + delta_t * i)
                    table.insert(self.sched_warmths, next_warmth)
                end
            end
        end
    end

    if self.activate == activate_sun then
        self.current_times_h = {unpack(SunTime.times, 1, midnight_index)}
    elseif self.activate == activate_schedule then
        self.current_times_h = {unpack(self.scheduler_times, 1, midnight_index)}
    else
        self.current_times_h = {unpack(SunTime.times, 1, midnight_index)}
        if self.activate == activate_closer_noon then
            for i = 1, midnight_index do
                if not self.current_times_h[i] then
                    self.current_times_h[i] = self.scheduler_times[i]
                elseif self.scheduler_times[i] and
                    math.abs(self.current_times_h[i]%24 - 12) > math.abs(self.scheduler_times[i]%24 - 12) then
                    self.current_times_h[i] = self.scheduler_times[i]
                end
            end
        else -- activate_closer_midnight
            for i = 1, midnight_index do
                if not self.current_times_h[i] then
                    self.current_times_h[i] = self.scheduler_times[i]
                elseif self.scheduler_times[i] and
                    math.abs(self.current_times_h[i]%24 - 12) < math.abs(self.scheduler_times[i]%24 - 12) then
                    self.current_times_h[i] = self.scheduler_times[i]
                end
            end
        end
    end

    if self.easy_mode then
        self.current_times_h[1] = nil
        self.current_times_h[2] = nil
        self.current_times_h[3] = nil
        self.current_times_h[6] = nil
        self.current_times_h[9] = nil
        self.current_times_h[10] = nil
        self.current_times_h[11] = nil
    end

    -- here are dragons
    local i = 1
    -- find first valid entry
    while not self.current_times_h[i] and i <= midnight_index do
        i = i + 1
    end
    local next
    while i <= midnight_index do
        next = i + 1
        -- find next valid entry
        while not self.current_times_h[next] and next <= midnight_index do
            next = next + 1
        end
        prepareSchedule(self.current_times_h, i, next)
        i = next
    end

    local now_s = SunTime:getTimeInSec()

    -- Reschedule 1sec after midnight
    UIManager:scheduleIn(24*3600 + 1 - now_s, self.scheduleMidnightUpdate, self)

    -- set event handlers
    if self.activate ~= 0 then
        -- Schedule the first warmth change
        self:scheduleNextWarmthChange(now_s, 1, from_resume)
        self:setEventHandlers()
    else
        self:clearEventHandlers()
    end
end

-- schedules the next warmth change
-- search_pos ... start searching from that index
-- from_resume ... true if first call after resume
function AutoWarmth:scheduleNextWarmthChange(time_s, search_pos, from_resume)
    logger.dbg("AutoWarmth: scheduleNextWarmthChange")
    UIManager:unschedule(AutoWarmth.setWarmth)

    if self.activate == 0 or #self.sched_warmths == 0 or search_pos > #self.sched_warmths then
        return
    end

    self.sched_warmth_index = search_pos or 1

    -- `actual_warmth` is the value which should be applied now.
    -- `next_warmth` is valid `delay_s` seconds after now for resume on some devices (KA1)
    -- Most of the times this will be the same as `actual_warmth`.
    -- We need both, as we could have a very rapid change in warmth (depending on user settings)
    -- or by chance a change in warmth very shortly after (a few ms) resume time.
    local delay_s = 1.5
    -- Use the last warmth value, so that we have a valid value when resuming after 24:00 but
    -- before true midnight. OK, this value is actually not quite the right one, as it is calculated
    -- for the current day (and not the previous one), but this is for a corner case
    -- and the error is small.
    local actual_warmth = self.sched_warmths[self.sched_warmth_index or #self.sched_warmths]
    local next_warmth = actual_warmth
    for i = self.sched_warmth_index, #self.sched_warmths do
        if self.sched_times_s[i] <= time_s then
            actual_warmth = self.sched_warmths[i]
            local j = i
            while from_resume and j <= #self.sched_warmths and self.sched_times_s[j] <= time_s + delay_s do
                -- Most times only one iteration through this loop
                next_warmth = self.sched_warmths[j]
                j = j + 1
            end
        else
            self.sched_warmth_index = i
            break
        end
    end
    -- update current warmth immediately
    self:setWarmth(actual_warmth, false) -- no setWarmth rescheduling, don't force warmth
    if self.sched_warmth_index <= #self.sched_warmths then
        local next_sched_time_s = self.sched_times_s[self.sched_warmth_index] - time_s
        if next_sched_time_s > 0 then
            -- This setWarmth will call scheduleNextWarmthChange which will schedule setWarmth again.
            UIManager:scheduleIn(next_sched_time_s, self.setWarmth, self, self.sched_warmths[self.sched_warmth_index], true)
        elseif self.sched_warmth_index < #self.sched_warmths then
            -- If this really happens under strange conditions, wait until the next full minute to
            -- minimize wakeups from standby.
            UIManager:scheduleIn(61 - tonumber(os.date("%S")),
                self.setWarmth, self, self.sched_warmths[self.sched_warmth_index], true)
        else
            logger.dbg("AutoWarmth: schedule is over, waiting for midnight update")
        end
    end

    if from_resume then
        -- On some strange devices like KA1 setWarmth doesn't work right after a resume so
        -- schedule setting of another valid warmth (=`next_warmth`) again (one time).
        -- On sane devices this schedule does no harm.
        -- see https://github.com/koreader/koreader/issues/8363
        UIManager:scheduleIn(delay_s, self.setWarmth, self, next_warmth, false) -- no setWarmth rescheduling, force warmth
    end

    -- Check if AutoWarmth shall toggle frontlight daytime and twilight
    if self.fl_off_during_day then
        if time_s >= self.current_times_h[5]*3600 and time_s < self.current_times_h[7]*3600 then
            -- during daytime (depending on choosens activation: SunTime, fixed Schedule, closer...
            -- turn on frontlight off once, user can override this selection by a gesture
            if Powerd:isFrontlightOn() then
                if self.fl_turned_off ~= true then -- can be false or nil
                    Powerd:turnOffFrontlight()
                    UIManager:broadcastEvent(Event:new("FrontlightTurnedOff"))
                end
            end
            self.fl_turned_off = true
        else
            -- outside of selected daytime, turn on frontlight once, user can override this selection by a gesture
            if Powerd:isFrontlightOff() then
                if self.fl_turned_off ~= false then -- can be true or nil
                    Powerd:turnOnFrontlight()
                end
            end
            self.fl_turned_off = false
        end
    end
end

-- Set warmth and schedule the next warmth change
function AutoWarmth:setWarmth(val, schedule_next, force_warmth)
    if val then
        DeviceListener:onSetNightMode(val > 100)

        if Device:hasNaturalLight() then
            val = math.min(val, 100) -- "mask" night mode
            Powerd:setWarmth(val, force_warmth)
        end
    end
    if schedule_next then
        local now_s = SunTime:getTimeInSec()
        self:scheduleNextWarmthChange(now_s, self.sched_warmth_index, false)
    end
end

function AutoWarmth:hoursToClock(hours)
    if hours then
        hours = hours % 24 * 3600 + 0.01 -- round up, due to reduced precision in settings.reader.lua
    end
    return util.secondsToClock(hours, self.easy_mode)
end

function AutoWarmth:addToMainMenu(menu_items)
    menu_items.autowarmth = {
        text = Device:hasNaturalLight() and _("Auto warmth and night mode") or _("Auto night mode"),
        checked_func = function() return self.activate ~= 0 end,
        sub_item_table_func = function()
            return self:getSubMenuItems()
        end,
    }
end

local function tidy_menu(menu, request)
    for i = #menu, 1, -1 do
        if menu[i].mode ~=nil then
            if menu[i].mode ~= request then
                table.remove(menu,i)
            else
                menu[i].mode = nil
            end
        end
    end
    return menu
end

function AutoWarmth:updateItems(touchmenu_instance)
    touchmenu_instance:updateItems()
    UIManager:broadcastEvent(Event:new("UpdateFooter", self.view and self.view.footer_visible or false))
end

local about_text = _([[Set the frontlight warmth (if available) and night mode based on a time schedule or the sun's position.

There are three types of twilight:

• Civil: You can read a newspaper
• Nautical: You can see the first stars
• Astronomical: It is really dark

Custom warmth values can be set for every kind of twilight and sunrise, noon, sunset and midnight.
The screen warmth is continuously adjusted to the current time.

To use the sun's position, a geographical location must be entered. The calculations are very precise, with a deviation less than minute and a half.]])
function AutoWarmth:getSubMenuItems()
    return {
        {
            text = Device:hasNaturalLight() and _("About auto warmth and night mode") or _("About auto night mode"),
            callback = function()
                UIManager:show(InfoMessage:new{
                    text = about_text,
                    width = math.floor(Screen:getWidth() * 0.9),
                })
            end,
            keep_menu_open = true,
            separator = true,
        },
        {
            text = _("Activate"),
            checked_func = function()
                return self.activate ~= 0
            end,
            sub_item_table = self:getActivateMenu(),
        },
        {
            text = _("Expert mode"),
            checked_func = function()
                return not self.easy_mode
            end,
            help_text = _("In the expert mode, different types of twilight can be used in addition to civil twilight."),
            callback = function(touchmenu_instance)
                self.easy_mode = not self.easy_mode
                G_reader_settings:saveSetting("autowarmth_easy_mode", self.easy_mode)
                self:scheduleMidnightUpdate()
                if touchmenu_instance then
                    touchmenu_instance.item_table = self:getSubMenuItems()
                    self:updateItems(touchmenu_instance)
                end
            end,
            keep_menu_open = true,
        },
        {
            text = _("Location settings"),
            sub_item_table = self:getLocationMenu(),
        },
        {
            text = _("Fixed schedule settings"),
            enabled_func = function()
                return self.activate ~= activate_sun and self.activate ~=0
            end,
            sub_item_table = self:getScheduleMenu(),
        },
        {
            enabled_func = function()
                return self.activate ~=0
            end,
            text = Device:hasNaturalLight() and _("Warmth and night mode settings") or _("Night mode settings"),
            sub_item_table = self:getWarmthMenu(),
        },
        {
            checked_func = function()
                return self.fl_off_during_day
            end,
            text = _("Frontlight off during the day"),
            callback = function(touchmenu_instance)
                self.fl_off_during_day = not self.fl_off_during_day
                G_reader_settings:saveSetting("autowarmth_fl_off_during_day", self.fl_off_during_day)

                self:scheduleMidnightUpdate()
                -- Turn the fl on during day if necessary;
                -- no need to turn it off as this is done trough `scheduleMidnightUpdate()`
                if not self.fl_off_during_day and Powerd:isFrontlightOff() then
                    Powerd:turnOnFrontlight()
                end

                if touchmenu_instance then
                    self:updateItems(touchmenu_instance)
                end
            end,
            keep_menu_open = true,
            separator = true,
        },
        self:getTimesMenu(_("Currently active parameters")),
        self:getTimesMenu(_("Sun position information for"), true, activate_sun),
        self:getTimesMenu(_("Fixed schedule information"), false, activate_schedule),
    }
end

function AutoWarmth:getActivateMenu()
    local function getActivateMenuEntry(text, help_text, activator)
        return {
            text = text,
            help_text = help_text,
            checked_func = function() return self.activate == activator end,
            callback = function()
                self.activate = self.activate ~= activator and activator or 0
                G_reader_settings:saveSetting("autowarmth_activate", self.activate)
                self:scheduleMidnightUpdate()
                UIManager:broadcastEvent(Event:new("UpdateFooter", self.view and self.view.footer_visible or false))
            end,
        }
    end

    return {
        getActivateMenuEntry(_("According to the sun's position"),
            _("Only use the times calculated from the position of the sun."),
            activate_sun),
        getActivateMenuEntry(_("According to the fixed schedule"),
            _("Only use the times from the fixed schedule."),
            activate_schedule),
        getActivateMenuEntry(_("Whatever is closer to noon"),
            _("Use the times from the sun position or schedule that are closer to noon."),
            activate_closer_noon),
        getActivateMenuEntry(_("Whatever is closer to midnight"),
            _("Use the times from the sun position or schedule that are closer to midnight."),
            activate_closer_midnight),
    }
end

function AutoWarmth:getLocationMenu()
    return {{
        text_func = function()
            if self.location ~= "" then
                return T(_("Location: %1"), self.location)
            else
                return _("Location")
            end
        end,
        callback = function(touchmenu_instance)
            local location_name_dialog
            location_name_dialog = InputDialog:new{
                title = _("Location name"),
                input = self.location,
                buttons = {
                    {
                        {
                            text = _("Cancel"),
                            id = "close",
                            callback = function()
                                UIManager:close(location_name_dialog)
                            end,
                        },
                        {
                            text = _("OK"),
                            callback = function()
                                self.location = location_name_dialog:getInputText()
                                G_reader_settings:saveSetting("autowarmth_location",
                                    self.location)
                                UIManager:close(location_name_dialog)
                                if touchmenu_instance then self:updateItems(touchmenu_instance) end
                            end,
                        },
                    }
                },
            }
            UIManager:show(location_name_dialog)
            location_name_dialog:onShowKeyboard()
        end,
        keep_menu_open = true,
    },
    {
        text_func = function()
            return T(_("Coordinates: (%1°, %2°)"), self.latitude, self.longitude)
        end,
        callback = function(touchmenu_instance)
            local location_widget = DoubleSpinWidget:new{
                title_text = _("Set location"),
                info_text = _("Enter decimal degrees, northern hemisphere and eastern length are '+'."),
                left_text = _("Latitude"),
                left_value = self.latitude,
                left_min = -90,
                left_max = 90,
                left_step = 0.1,
                left_hold_step = 5,
                left_precision = "%0.2f",
                right_text = _("Longitude"),
                right_value = self.longitude,
                right_min = -180,
                right_max = 180,
                right_step = 0.1,
                right_hold_step = 5,
                right_precision = "%0.2f",
                unit = "°",
                callback = function(lat, long)
                    self.latitude = lat
                    self.longitude = long
                    self.timezone = self:getTimezoneOffset() -- use timezone of device
                    G_reader_settings:saveSetting("autowarmth_latitude", self.latitude)
                    G_reader_settings:saveSetting("autowarmth_longitude", self.longitude)
                    G_reader_settings:saveSetting("autowarmth_timezone", self.timezone)
                    self:scheduleMidnightUpdate()
                    if touchmenu_instance then self:updateItems(touchmenu_instance) end
                end,
            }
            UIManager:show(location_widget)
        end,
        keep_menu_open = true,
    },
    {
        text_func = function()
            return T(_("Altitude: %1 m"), self.altitude)
        end,
        callback = function(touchmenu_instance)
            UIManager:show(SpinWidget:new{
                title_text = _("Altitude"),
                info_text = _("Enter the altitude in meters above sea level."),
                value = self.altitude,
                value_min = -100,
                value_max = 15000, -- intercontinental flight
                wrap = false,
                value_step = 10,
                value_hold_step = 100,
                unit = C_("Length", "m"),
                ok_text = _("Set"),
                callback = function(spin)
                    self.altitude = spin.value
                    G_reader_settings:saveSetting("autowarmth_altitude", self.altitude)
                    self:scheduleMidnightUpdate()
                    if touchmenu_instance then self:updateItems(touchmenu_instance) end
                end,
                extra_text = _("Default"),
                extra_callback = function()
                    self.altitude = 200
                    G_reader_settings:saveSetting("autowarmth_altitude", self.altitude)
                    self:scheduleMidnightUpdate()
                    if touchmenu_instance then self:updateItems(touchmenu_instance) end
                end,
            })
        end,
        keep_menu_open = true,
    }}
end

function AutoWarmth:getScheduleMenu()
    local function store_times(touchmenu_instance, new_time, num)
        self.scheduler_times[num] = new_time
        G_reader_settings:saveSetting("autowarmth_scheduler_times", self.scheduler_times)
        self:scheduleMidnightUpdate()
        if touchmenu_instance then self:updateItems(touchmenu_instance) end
    end
    -- mode == nil ... show alway
    --      == true ... easy mode
    --      == false ... expert mode
    local function getScheduleMenuEntry(text, num, mode)
        return {
            mode = mode,
            text_func = function()
                return T(_"%1: %2", text,
                    self:hoursToClock(self.scheduler_times[num]))
            end,
            checked_func = function()
                return self.scheduler_times[num] ~= nil
            end,
            callback = function(touchmenu_instance)
                local hh = 12
                local mm = 0
                if self.scheduler_times[num] then
                    hh = math.floor(self.scheduler_times[num])
                    mm = math.floor(frac(self.scheduler_times[num]) * 60 + 0.5)
                end
                UIManager:show(DateTimeWidget:new{
                    title_text = _("Set time"),
                    info_text = _("Enter time in hours and minutes."),
                    hour = hh,
                    hour_min = -1,
                    hour_max = 24,
                    min = mm,
                    ok_text = _("Set time"),
                    callback = function(time)
                        local new_time = time.hour + time.min / 60
                        local function get_valid_time(n, dir)
                            for i = n+dir, dir > 0 and midnight_index or 1, dir do
                                if self.scheduler_times[i] then
                                    return self.scheduler_times[i]
                                end
                            end
                            return dir > 0 and 0 or 26
                        end
                        if num > 1 and new_time < get_valid_time(num, -1) then
                            UIManager:show(ConfirmBox:new{
                                text = _("This time is before the previous time.\nAdjust the previous time?"),
                                ok_callback = function()
                                    for i = num - 1, 1, -1 do
                                        if self.scheduler_times[i] then
                                            if new_time < self.scheduler_times[i] then
                                                self.scheduler_times[i] = new_time
                                            else
                                                break
                                            end
                                        end
                                    end
                                    store_times(touchmenu_instance, new_time, num)
                                end,
                            })
                        elseif num < 10 and new_time > get_valid_time(num, 1) then
                            UIManager:show(ConfirmBox:new{
                                text = _("This time is after the subsequent time.\nAdjust the subsequent time?"),
                                ok_callback = function()
                                    for i = num + 1, midnight_index - 1 do
                                        if self.scheduler_times[i] then
                                            if new_time > self.scheduler_times[i] then
                                                self.scheduler_times[i] = new_time
                                            else
                                                break
                                            end
                                        end
                                    end
                                    store_times(touchmenu_instance, new_time, num)
                                end,
                            })
                        else
                            store_times(touchmenu_instance, new_time, num)
                        end
                    end,
                    extra_text = _("Invalidate"),
                    extra_callback = function()
                        store_times(touchmenu_instance, nil, num)
                    end,
                })
            end,
            keep_menu_open = true,
        }
    end

    local retval = {
        getScheduleMenuEntry(_("Solar midnight (previous day)"), 1, false),
        getScheduleMenuEntry(_("Astronomical dawn"), 2, false),
        getScheduleMenuEntry(_("Nautical dawn"), 3, false),
        getScheduleMenuEntry(_("Civil dawn"), 4),
        getScheduleMenuEntry(_("Sunrise"), 5),
        getScheduleMenuEntry(_("Solar noon"), 6, false),
        getScheduleMenuEntry(_("Sunset"), 7),
        getScheduleMenuEntry(_("Civil dusk"), 8),
        getScheduleMenuEntry(_("Nautical dusk"), 9, false),
        getScheduleMenuEntry(_("Astronomical dusk"), 10, false),
        getScheduleMenuEntry(_("Solar midnight"), 11, false),
    }

    return tidy_menu(retval, self.easy_mode)
end

function AutoWarmth:getWarmthMenu()
    -- mode == nil ... show alway
    --      == true ... easy mode
    --      == false ... expert mode
    local function getWarmthMenuEntry(text, num, mode)
        return {
            mode = mode,
            text_func = function()
                if Device:hasNaturalLight() then
                    if self.warmth[num] <= 100 then
                        return T(_("%1: %2 %"), text, self.warmth[num])
                    else
                        return T(_("%1: 100 % + ☾"), text)
                    end
                else
                    if self.warmth[num] <= 100 then
                        return T(_("%1: ☼"), text)
                    else
                        return T(_("%1: ☾"), text)
                    end
                end
            end,
            callback = function(touchmenu_instance)
                if Device:hasNaturalLight() then
                    UIManager:show(SpinWidget:new{
                        title_text = text,
                        info_text = _("Enter percentage of warmth."),
                        value = self.warmth[num],
                        value_min = 0,
                        value_max = 100,
                        wrap = false,
                        value_step = math.floor(100 / device_max_warmth),
                        value_hold_step = 10,
                        unit = "%",
                        ok_text = _("Set"),
                        callback = function(spin)
                            self.warmth[num] = spin.value
                            self.warmth[#self.warmth - num + 1] = spin.value
                            G_reader_settings:saveSetting("autowarmth_warmth", self.warmth)
                            self:scheduleMidnightUpdate()
                            if touchmenu_instance then self:updateItems(touchmenu_instance) end
                        end,
                        extra_text = _("Use night mode"),
                        extra_callback = function()
                            self.warmth[num] = 110
                            self.warmth[#self.warmth - num + 1] = 110
                            G_reader_settings:saveSetting("autowarmth_warmth", self.warmth)
                            self:scheduleMidnightUpdate()
                            if touchmenu_instance then self:updateItems(touchmenu_instance) end
                        end,
                    })
                else
                    UIManager:show(ConfirmBox:new{
                        text = _("Nightmode"),
                        ok_text = _("Set"),
                        ok_callback = function()
                            self.warmth[num] = 110
                            self.warmth[#self.warmth - num + 1] = 110
                            G_reader_settings:saveSetting("autowarmth_warmth", self.warmth)
                            self:scheduleMidnightUpdate()
                            if touchmenu_instance then self:updateItems(touchmenu_instance) end
                        end,
                        cancel_text = _("Unset"),
                        cancel_callback = function()
                            self.warmth[num] = 0
                            self.warmth[#self.warmth - num + 1] = 0
                            G_reader_settings:saveSetting("autowarmth_warmth", self.warmth)
                            self:scheduleMidnightUpdate()
                            if touchmenu_instance then self:updateItems(touchmenu_instance) end
                        end,
                        other_buttons = {{
                            {
                                text = _("Cancel"),
                            }
                        }},
                    })
                end
            end,

            keep_menu_open = true,
        }
    end

    local retval = {
        {
            text = Device:hasNaturalLight() and _("Set warmth and night mode for:") or _("Set night mode for:"),
            enabled_func = function() return false end,
        },
        getWarmthMenuEntry(_("Solar noon"), 6, false),
        getWarmthMenuEntry(_("Sunset and sunrise"), 5),
        getWarmthMenuEntry(_("Darkest time of civil twilight"), 4),
        getWarmthMenuEntry(_("Darkest time of nautical twilight"), 3, false),
        getWarmthMenuEntry(_("Darkest time of astronomical twilight"), 2, false),
        getWarmthMenuEntry(_("Solar midnight"), 1, false),
    }

    return tidy_menu(retval, self.easy_mode)
end

-- title
-- location: add a location string
-- activator: nil               .. current_times_h,
--            activate_sun      .. sun times
--            activate_schedule .. scheduler times
-- request_easy: true if easy_mode should be used
function AutoWarmth:showTimesInfo(title, location, activator, request_easy)
    local times
    if not activator then
        times = self.current_times_h
    elseif activator == activate_sun then
        times = SunTime.times
    elseif activator == activate_schedule then
        times = self.scheduler_times
    end

    -- text to show
    -- t .. times
    -- num .. index in times
    local function info_line(indent, text, t, num, face, easy)
        -- get width of space
        local unit = " "
        local tmp = TextWidget:new{
            text = unit,
            face = face,
        }
        local space_w = tmp:getSize().w

        -- get width of text
        unit = text
        tmp = TextWidget:new{
            text = unit,
            face = face,
        }
        local text_w = tmp:getSize().w
        tmp:free()

        -- width of text in spaces
        local str_len = math.floor(text_w / space_w + 0.5)

        local tab_width = 18 - indent
        local retval = string.rep(" ", indent) .. text .. string.rep(" ", tab_width - str_len)
            .. self:hoursToClock(t[num])
        if easy then
            if t[num] and self.current_times_h[num] and self.current_times_h[num] ~= t[num] then
                return text .. "\n"
            else
                return ""
            end
        end

        if not t[num] then -- entry deactivated
            return retval .. "\n"
        elseif Device:hasNaturalLight() then
            if self.current_times_h[num] == t[num] then
                if self.warmth[num] <= 100 then
                    return retval .. " (💡" .. self.warmth[num] .."%)\n"
                else
                    return retval .. " (💡100% + ☾)\n"
                end
            else
                return retval .. "\n"
            end
        else
            if self.current_times_h[num] == t[num] then
                if self.warmth[num] <= 100 then
                    return retval .. " (☼)\n"
                else
                    return retval .. " (☾)\n"
                end
            else
                return retval .. "\n"
            end
        end
    end

    local location_string = ""
    if location then
        location_string = " " .. self:getLocationString()
    end

    local function add_line(text, easy)
        return easy and "" or ("  " .. text .. "\n")
    end

    local face = Font:getFace("scfont")
    UIManager:show(InfoMessage:new{
        face = face,
        width = math.floor(Screen:getWidth() * (self.easy_mode and 0.75 or 0.90)),
        text = title .. location_string .. ":\n\n" ..
            info_line(0, _("Solar midnight:"), times, 1, face, request_easy) ..
            add_line(_("Dawn"), request_easy) ..
            info_line(4, _("Astronomic:"), times, 2, face, request_easy) ..
            info_line(4, _("Nautical:"), times, 3, face, request_easy)..
            info_line(request_easy and 0 or 4,
                request_easy and _("Twilight:") or _("Civil:"), times, 4, face) ..
            add_line(_("Dawn"), request_easy) ..
            info_line(0, _("Sunrise:"), times, 5, face) ..
            "\n" ..
            info_line(0, _("Solar noon:"), times, 6, face, request_easy) ..
            add_line("", request_easy) ..
            info_line(0, _("Sunset:"), times, 7, face) ..
            add_line(_("Dusk"), request_easy) ..
            info_line(request_easy and 0 or 4,
                request_easy and _("Twilight:") or _("Civil:"), times, 8, face) ..
            info_line(4, _("Nautical:"), times, 9, face, request_easy) ..
            info_line(4, _("Astronomic:"), times, 10, face, request_easy) ..
            add_line(_("Dusk"), request_easy) ..
            info_line(0, _("Solar midnight:"), times, midnight_index, face, request_easy)
    })
end

-- title
-- location: add a location string
-- activator: nil               .. current_times_h,
--            activate_sun      .. sun times
--            activate_schedule .. scheduler times
function AutoWarmth:getTimesMenu(title, location, activator)
    return {
        enabled_func = function()
            -- always show sun position times so you can see ephemeris
            return self.activate ~= 0 and (self.activate ~= activate_sun or activator == nil)
                or activator == activate_sun
        end,
        text_func = function()
            if location then
                return title .. " " .. self:getLocationString()
            end
            return title
        end,
        callback = function()
            self:showTimesInfo(title, location, activator, self.easy_mode)
        end,
        keep_menu_open = true,
    }
end

function AutoWarmth:getLocationString()
    if self.location ~= "" then
        return self.location
    else
        return string.format("(%.2f°,%.2f°)", self.latitude, self.longitude)
    end
end

return AutoWarmth
