--[[--
Plugin for setting screen warmth based on the sun position and/or a time schedule

@module koplugin.autowarmth
--]]--

local Device = require("device")

local ConfirmBox = require("ui/widget/confirmbox")
local DateTimeWidget = require("ui/widget/datetimewidget")
local DoubleSpinWidget = require("/ui/widget/doublespinwidget")
local DeviceListener = require("device/devicelistener")
local Dispatcher = require("dispatcher")
local FFIUtil = require("ffi/util")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Font = require("ui/font")
local Notification = require("ui/widget/notification")
local SpinWidget = require("ui/widget/spinwidget")
local SunTime = require("suntime")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local T = FFIUtil.template
local Screen = require("device").screen
local util = require("util")

local activate_sun = 1
local activate_schedule = 2
local activate_closer_noon = 3
local activate_closer_midnight = 4

local midnight_index = 11

local device_max_warmth = Device:hasNaturalLight() and Device.powerd.fl_warmth_max or 100
local device_warmth_fit_scale = device_max_warmth / 100

local function frac(x)
    return x - math.floor(x)
end

local AutoWarmth = WidgetContainer:new{
    name = "autowarmth",
    sched_times = {},
    sched_funcs = {}, -- necessary for unschedule, function, warmth
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
    self.scheduler_times = G_reader_settings:readSetting("autowarmth_scheduler_times") or
        {0.0, 5.5, 6.0, 6.5, 7.0, 13.0, 21.5, 22.0, 22.5, 23.0, 24.0}
    self.warmth =   G_reader_settings:readSetting("autowarmth_warmth")
        or { 90, 90, 80, 60, 20, 20, 20, 60, 80, 90, 90}

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

function AutoWarmth:onResume()
    if self.activate == 0 then return end

    local resume_date = os.date("*t")

    -- check if resume and suspend are done on the same day
    if resume_date.day == SunTime.date.day and resume_date.month == SunTime.date.month
        and resume_date.year == SunTime.date.year then
        local now = SunTime:getTimeInSec(resume_date)
        self:scheduleWarmthChanges(now)
    else
        self:scheduleMidnightUpdate() -- resume is on the other day, do all calcs again
    end
end

-- wrapper for unscheduling, so that only our setWarmth gets unscheduled
function AutoWarmth.setWarmth(val)
    if val then
        if val > 100 then
            DeviceListener:onSetNightMode(true)
        else
            DeviceListener:onSetNightMode(false)
        end
        if Device:hasNaturalLight() then
            val = math.min(val, 100)
            Device.powerd:setWarmth(val)
        end
    end
end

function AutoWarmth:scheduleMidnightUpdate()
    -- first unschedule all old functions
    UIManager:unschedule(self.scheduleMidnightUpdate) -- when called from menu or resume

    SunTime:setPosition(self.location, self.latitude, self.longitude,
        self.timezone, self.altitude, true)
    SunTime:setAdvanced()
    SunTime:setDate() -- today
    SunTime:calculateTimes()

    self.sched_times = {}
    self.sched_funcs = {}

    local function prepareSchedule(times, index1, index2)
        local time1 = times[index1]
        if not time1 then return end

        local time = SunTime:getTimeInSec(time1)
        table.insert(self.sched_times, time)
        table.insert(self.sched_funcs, {AutoWarmth.setWarmth, self.warmth[index1]})

        local time2 = times[index2]
        if not time2 then return end -- to near to the pole
        local warmth_diff = math.min(self.warmth[index2], 100) - math.min(self.warmth[index1], 100)
        if warmth_diff ~= 0 then
            local time_diff = SunTime:getTimeInSec(time2) - time
            local delta_t = time_diff / math.abs(warmth_diff) -- can be inf, no problem
            local delta_w =  warmth_diff > 0 and 1 or -1
            for i = 1, math.abs(warmth_diff)-1 do
                local next_warmth = math.min(self.warmth[index1], 100) + delta_w * i
                -- only apply warmth for steps the hardware has (e.g. Tolino has 0-10 hw steps
                -- which map to warmth 0, 10, 20, 30 ... 100)
                if frac(next_warmth * device_warmth_fit_scale) == 0 then
                    table.insert(self.sched_times, time + delta_t * i)
                    table.insert(self.sched_funcs, {self.setWarmth,
                        math.floor(math.min(self.warmth[index1], 100) + delta_w * i)})
                end
            end
        end
    end

    if self.activate == activate_sun then
        self.current_times = {unpack(SunTime.times, 1, midnight_index)}
    elseif self.activate == activate_schedule then
        self.current_times = {unpack(self.scheduler_times, 1, midnight_index)}
    else
        self.current_times = {unpack(SunTime.times, 1, midnight_index)}
        if self.activate == activate_closer_noon then
            for i = 1, midnight_index do
                if not self.current_times[i] then
                    self.current_times[i] = self.scheduler_times[i]
                elseif self.scheduler_times[i] and
                    math.abs(self.current_times[i]%24 - 12) > math.abs(self.scheduler_times[i]%24 - 12) then
                    self.current_times[i] = self.scheduler_times[i]
                end
            end
        else -- activate_closer_midnight
            for i = 1, midnight_index do
                if not self.current_times[i] then
                    self.current_times[i] = self.scheduler_times[i]
                elseif self.scheduler_times[i] and
                    math.abs(self.current_times[i]%24 - 12) < math.abs(self.scheduler_times[i]%24 - 12) then
                    self.current_times[i] = self.scheduler_times[i]
                end
            end
        end
    end

    if self.easy_mode then
        self.current_times[1] = nil
        self.current_times[2] = nil
        self.current_times[3] = nil
        self.current_times[6] = nil
        self.current_times[9] = nil
        self.current_times[10] = nil
        self.current_times[11] = nil
    end

    -- here are dragons
    local i = 1
    -- find first valid entry
    while not self.current_times[i] and i <= midnight_index do
        i = i + 1
    end
    local next
    while i <= midnight_index do
        next = i + 1
        -- find next valid entry
        while not self.current_times[next] and next <= midnight_index do
            next = next + 1
        end
        prepareSchedule(self.current_times, i, next)
        i = next
    end

    local now = SunTime:getTimeInSec()

    -- reschedule 5sec after midnight
    UIManager:scheduleIn(24*3600 + 5 - now, self.scheduleMidnightUpdate, self )

    self:scheduleWarmthChanges(now)
end

function AutoWarmth:scheduleWarmthChanges(time)
    for i = 1, #self.sched_funcs do -- loop not essential, as unschedule unschedules all functions at once
        if not UIManager:unschedule(self.sched_funcs[i][1]) then
            break
        end
    end

    UIManager:unschedule(AutoWarmth.setWarmth) -- to be safe, if there are no scheduled entries

    if self.activate == 0 then return end
    if #self.sched_funcs == 0 then return end

    -- `actual_warmth` is the value which should be applied now.
    -- `next_warmth` is valid `delay_time` seconds after now for resume on some devices (KA1)
    -- Most of the times this will be the same as `actual_warmth`.
    -- We need both, as we could have a very rapid change in warmth (depending on user settings)
    -- or by chance a change in warmth very shortly after (a few ms) resume time.
    local delay_time = 1.5
    -- Use the last warmth value, so that we have a valid value when resuming after 24:00 but
    -- before true midnight. OK, this value is actually not quite the right one, as it is calculated
    -- for the current day (and not the previous one), but this is for a corner case
    -- and the error is small.
    local actual_warmth = self.sched_funcs[#self.sched_funcs][2]
    local next_warmth = actual_warmth
    for i = 1, #self.sched_funcs do
        if self.sched_times[i] <= time then
            actual_warmth = self.sched_funcs[i][2] or actual_warmth
        else
            UIManager:scheduleIn(self.sched_times[i] - time,
                self.sched_funcs[i][1], self.sched_funcs[i][2])
        end
        if self.sched_times[i] <= time + delay_time then
            next_warmth = self.sched_funcs[i][2] or next_warmth
        end
    end
    -- update current warmth immediately
    self.setWarmth(actual_warmth)

    -- On some strange devices like KA1 the above doesn't work right after a resume so
    -- schedule setting of another valid warmth (=`next_warmth`) again (one time).
    -- On sane devices this schedule does no harm.
    -- see https://github.com/koreader/koreader/issues/8363
    UIManager:scheduleIn(delay_time, self.setWarmth, next_warmth)
end

function AutoWarmth:hoursToClock(hours)
    if hours then
        hours = hours % 24 * 3600 + 0.01 -- round up, due to reduced precision in settings.reader.lua
    end
    return util.secondsToClock(hours, self.easy_mode)
end

function AutoWarmth:addToMainMenu(menu_items)
    menu_items.autowarmth = {
        text = Device:hasNaturalLight() and _("Auto warmth and night mode")
            or _("Auto night mode"),
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
            text = Device:hasNaturalLight() and _("About auto warmth and night mode")
                or _("About auto night mode"),
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
                touchmenu_instance.item_table = self:getSubMenuItems()
                touchmenu_instance:updateItems()
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
            text = Device:hasNaturalLight() and _("Warmth and night mode settings")
                or _("Night mode settings"),
            sub_item_table = self:getWarmthMenu(),
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
                if self.activate ~= activator then
                    self.activate = activator
                else
                    self.activate = 0
                end
                G_reader_settings:saveSetting("autowarmth_activate", self.activate)
                self:scheduleMidnightUpdate()
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
                                if touchmenu_instance then touchmenu_instance:updateItems() end
                            end,
                        },
                    }}
                }
            UIManager:show(location_name_dialog)
            location_name_dialog:onShowKeyboard()
        end,
        keep_menu_open = true,
    },
    {
        text_func = function()
            return T(_("Coordinates: (%1, %2)"), self.latitude, self.longitude)
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
                callback = function(lat, long)
                    self.latitude = lat
                    self.longitude = long
                    self.timezone = self:getTimezoneOffset() -- use timezone of device
                    G_reader_settings:saveSetting("autowarmth_latitude", self.latitude)
                    G_reader_settings:saveSetting("autowarmth_longitude", self.longitude)
                    G_reader_settings:saveSetting("autowarmth_timezone", self.timezone)
                    self:scheduleMidnightUpdate()
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end,
            }
            UIManager:show(location_widget)
        end,
        keep_menu_open = true,
    },
    {
        text_func = function()
            return T(_("Altitude: %1m"), self.altitude)
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
                ok_text = _("Set"),
                callback = function(spin)
                    self.altitude = spin.value
                    G_reader_settings:saveSetting("autowarmth_altitude", self.altitude)
                    self:scheduleMidnightUpdate()
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end,
                extra_text = _("Default"),
                extra_callback = function()
                    self.altitude = 200
                    G_reader_settings:saveSetting("autowarmth_altitude", self.altitude)
                    self:scheduleMidnightUpdate()
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end,
            })
        end,
        keep_menu_open = true,
    }}
end

function AutoWarmth:getScheduleMenu()
    local function store_times(touchmenu_instance, new_time, num)
        self.scheduler_times[num] = new_time
        if num == 1 then
            if new_time then
                self.scheduler_times[midnight_index]
                    = new_time + 24 -- next day
            else
                self.scheduler_times[midnight_index] = nil
            end
        end
        G_reader_settings:saveSetting("autowarmth_scheduler_times",
            self.scheduler_times)
        self:scheduleMidnightUpdate()
        if touchmenu_instance then touchmenu_instance:updateItems() end
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
                    is_date = false,
                    hour = hh,
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
                                text =  _("This time is before the previous time.\nAdjust the previous time?"),
                                ok_callback = function()
                                    for i = num-1, 1, -1 do
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
                                text =  _("This time is after the subsequent time.\nAdjust the subsequent time?"),
                                ok_callback = function()
                                    for i = num + 1, midnight_index - 1  do
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
        getScheduleMenuEntry(_("Solar midnight"), 1, false ),
        getScheduleMenuEntry(_("Astronomical dawn"), 2, false),
        getScheduleMenuEntry(_("Nautical dawn"), 3, false),
        getScheduleMenuEntry(_("Civil dawn"), 4),
        getScheduleMenuEntry(_("Sunrise"), 5),
        getScheduleMenuEntry(_("Solar noon"), 6, false),
        getScheduleMenuEntry(_("Sunset"), 7),
        getScheduleMenuEntry(_("Civil dusk"), 8),
        getScheduleMenuEntry(_("Nautical dusk"), 9, false),
        getScheduleMenuEntry(_("Astronomical dusk"), 10, false),
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
                        return T(_("%1: %2%"), text, self.warmth[num])
                    else
                        return T(_("%1: 100% + ☾"), text)
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
                        ok_text = _("Set"),
                        callback = function(spin)
                            self.warmth[num] = spin.value
                            self.warmth[#self.warmth - num + 1] = spin.value
                            G_reader_settings:saveSetting("autowarmth_warmth", self.warmth)
                            self:scheduleMidnightUpdate()
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end,
                        extra_text = _("Use night mode"),
                        extra_callback = function()
                            self.warmth[num] = 110
                            self.warmth[#self.warmth - num + 1] = 110
                            G_reader_settings:saveSetting("autowarmth_warmth", self.warmth)
                            self:scheduleMidnightUpdate()
                            if touchmenu_instance then touchmenu_instance:updateItems() end
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
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end,
                        cancel_text = _("Unset"),
                        cancel_callback = function()
                            self.warmth[num] = 0
                            self.warmth[#self.warmth - num + 1] = 0
                            G_reader_settings:saveSetting("autowarmth_warmth", self.warmth)
                            self:scheduleMidnightUpdate()
                            if touchmenu_instance then touchmenu_instance:updateItems() end
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
            text = Device:hasNaturalLight() and _("Set warmth and night mode for:")
                or _("Set night mode for:"),
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
-- activator: nil               .. current_times,
--            activate_sun      .. sun times
--            activate_schedule .. scheduler times
-- request_easy: true if easy_mode should be used
function AutoWarmth:showTimesInfo(title, location, activator, request_easy)
    local times
    if not activator then
        times = self.current_times
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
            if t[num] and self.current_times[num] and self.current_times[num] ~= t[num] then
                return text .. "\n"
            else
                return ""
            end
        end

        if not t[num] then -- entry deactivated
            return retval .. "\n"
        elseif Device:hasNaturalLight() then
            if self.current_times[num] == t[num] then
                if self.warmth[num] <= 100 then
                    return retval .. " (💡" .. self.warmth[num] .."%)\n"
                else
                    return retval .. " (💡100% + ☾)\n"
                end
            else
                return retval .. "\n"
            end
        else
            if self.current_times[num] == t[num] then
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
-- activator: nil               .. current_times,
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
        return "(" .. self.latitude .. "," .. self.longitude .. ")"
    end
end

return AutoWarmth
