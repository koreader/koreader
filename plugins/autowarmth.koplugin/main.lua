--[[--
Plugin for setting screen warmth based on the sun position and/or a time schedule

@module koplugin.autowarmth
--]]--

local CheckButton = require("ui/widget/checkbutton")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local DateTimeWidget = require("ui/widget/datetimewidget")
local DoubleSpinWidget = require("ui/widget/doublespinwidget")
local DeviceListener = require("device/devicelistener")
local Dispatcher = require("dispatcher")
local Event = require("ui/event")
local FFIUtil = require("ffi/util")
local Font = require("ui/font")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Math = require("optmath")
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
local datetime = require("datetime")

local activate_sun = 1
local activate_schedule = 2
local activate_closer_noon = 3
local activate_closer_midnight = 4

local midnight_index = 11

local device_max_warmth = Device:hasNaturalLight() and Powerd.fl_warmth_max or 100
local device_warmth_fit_scale = device_max_warmth * (1/100)

local function frac(x)
    return x - math.floor(x)
end

local AutoWarmth = WidgetContainer:extend{
    name = "autowarmth",
    sched_times_s = nil, -- array
    sched_warmths = nil, -- array

    -- Static member that shall survive reloading of the plugin but not a restart
    fl_user_toggle = false, -- true/false if someone (AutoWarmth, gesture ...) has toggled the frontlight
    fl_turned_off = false, -- the frontlight toggle state
}

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
    self.fl_off_during_day_offset_s = G_reader_settings:readSetting("autowarmth_fl_off_during_day_offset_s", 0)
    if self.easy_mode then
        self.fl_off_during_day_offset_s = 0
    end

    self.control_warmth = G_reader_settings:nilOrTrue("autowarmth_control_warmth")
    self.control_nightmode = G_reader_settings:nilOrTrue("autowarmth_control_nightmode")
    self.hide_nightmode_warning = G_reader_settings:isTrue("autowarmth_hide_nightmode_warning")
    if not Device:hasNaturalLight() then
        self.control_nightmode = true
    elseif not self.control_warmth and not self.control_nightmode then
        logger.dbg("AutoWarmth: autowarmth_control_warmth and autowarmth_control_nightmode are both false, set them to true")
        self.control_warmth = true
        self.control_nightmode = true
    end

    -- Fix entries not in ascending order (only happens by manual editing of settings.reader.lua)
    local i = 1

    -- Find first not disabled entry. (`<` is OK here.)
    while i < midnight_index and not self.scheduler_times[i] do
        i = i + 1
    end
    while i < midnight_index do
        local j = i + 1
        -- Find next not disabled entry
        while j <= midnight_index and not self.scheduler_times[j] do
            j = j + 1
        end
        -- Fix the found the next not disabled entry if necessary.
        if j <= midnight_index and self.scheduler_times[j] and
            self.scheduler_times[i] > self.scheduler_times[j] then

            self.scheduler_times[j] = self.scheduler_times[i]
            logger.warn("AutoWarmth: scheduling times fixed.")
        end
        i = j
    end

    -- schedule recalculation shortly after midnight
    self:scheduleMidnightUpdate()
end

function AutoWarmth:onDispatcherRegisterActions()
    Dispatcher:registerAction("show_ephemeris",
        {category="none", event="ShowEphemeris", title=_("Show ephemeris"), general=true})
    Dispatcher:registerAction("auto_warmth_off",
        {category="none", event="AutoWarmthOff", title=_("Auto warmth off"), screen=true})
    Dispatcher:registerAction("auto_warmth_activate_sun",
        {category="none", event="AutoWarmthMode", arg=activate_sun, title=_("Auto warmth use sun position"), screen=true})
    Dispatcher:registerAction("auto_warmth_activate_schedule",
        {category="none", event="AutoWarmthMode", arg=activate_schedule, title=_("Auto warmth use schedule"), screen=true})
    Dispatcher:registerAction("auto_warmth_activate_closer_midnight",
        {category="none", event="AutoWarmthMode", arg=activate_closer_midnight, title=_("Auto warmth use closer midnight"), screen=true})
    Dispatcher:registerAction("auto_warmth_activate_closer_noon",
        {category="none", event="AutoWarmthMode", arg=activate_closer_noon, title=_("Auto warmth use closer noon"), screen=true})

    Dispatcher:registerAction("auto_warmth_cycle_trough",
        {category="none", event="AutoWarmthMode", title=_("Auto warmth cycle through modes"), screen=true})
end

function AutoWarmth:onShowEphemeris()
    self:showTimesInfo(_("Information about the sun in"), true, activate_sun, false)
end

function AutoWarmth:onAutoWarmthOff()
    self:onAutoWarmthMode(0)
end

 -- select one mode of autowarmth directly
function AutoWarmth:onAutoWarmthMode(forced_method)
    if forced_method then
        self.activate = Math.clamp(forced_method, 0, activate_closer_midnight)
    else
        if self.activate > 0 then
            self.activate = self.activate - 1
        else
            self.activate = activate_closer_midnight
        end
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

function AutoWarmth:_onResume()
    logger.dbg("AutoWarmth: onResume", AutoWarmth.fl_turned_off, AutoWarmth.fl_user_toggle)

    local resume_date = os.date("*t")

    if self.fl_off_during_day then
        -- We handle the frontlight state ourself.
        Powerd.fl_was_on = false
    end

    -- check if resume and suspend are done on the same day
    if resume_date.day == SunTime.date.day and resume_date.month == SunTime.date.month
        and resume_date.year == SunTime.date.year then

        local now_s = SunTime:getTimeInSec(resume_date)
        self.sched_warmth_index = self.sched_warmth_index - 1 -- scheduleNextWarmth will check this
        self:scheduleNextWarmthChange(true)
        self:scheduleToggleFrontlight(now_s) -- reset user toggles at sun set or sun rise
        if AutoWarmth.fl_user_toggle then
            self:setFrontlight(not AutoWarmth.fl_turned_off, true) -- keep user toggle state
        else
            self:toggleFrontlight(now_s) -- no user toggle
        end
        -- Reschedule 1sec after midnight
        UIManager:scheduleIn(24*3600 + 1 - now_s, self.scheduleMidnightUpdate, self)
    else
        self:scheduleMidnightUpdate(true) -- resume is on the other day, do all calcs again
    end
end

function AutoWarmth:_onSuspend()
    logger.dbg("AutoWarmth: onSuspend")
    UIManager:unschedule(self.scheduleMidnightUpdate)
    UIManager:unschedule(self.setWarmth)
    UIManager:unschedule(self.setFrontlight)
    UIManager:unschedule(self.scheduleNextWarmthChange)
end

function AutoWarmth:_onToggleNightMode()
    logger.dbg("AutoWarmth: onToggleNightMode")
    if not self.hide_nightmode_warning then
        local RadioButtonWidget = require("ui/widget/radiobuttonwidget")
        local radio_buttons = {
            {{
                text = _("Show this warning again"),
                provider = function() end
            }},
            {{
                text = _("Hide the warning until the next book is opened"),
                provider = function()
                    self.hide_nightmode_warning = true
                end,
            }},
            {{
                text = _("Hide this warning permanently"),
                provider = function()
                    self.hide_nightmode_warning = true
                    G_reader_settings:makeTrue("autowarmth_hide_nightmode_warning")
                end,
            }},
            {{
                text = _("Disable AutoWarmth's nightmode control"),
                provider = function()
                    self.control_nightmode = false
                    G_reader_settings:makeFalse("autowarmth_control_nightmode")
                    self:scheduleMidnightUpdate(true)
                end,
            }},
        }
        UIManager:show(RadioButtonWidget:new{
            title_text = _("Night mode changed"),
            info_text = _("The AutoWarmth plugin might change it again."),
            width_factor = 0.9,
            radio_buttons = radio_buttons,
            callback = function(radio)
                radio.provider()
            end,
        })
    end
end

function AutoWarmth:_onToggleFrontlight()
    logger.dbg("AutoWarmth: onToggleFrontlight")
    AutoWarmth.fl_user_toggle = true
    AutoWarmth.fl_turned_off = not AutoWarmth.fl_turned_off
end

function AutoWarmth:setEventHandlers()
    self.onResume = self._onResume
    self.onSuspend = self._onSuspend
    if self.control_nightmode then
        self.onToggleNightMode = self._onToggleNightMode
        self.onSetNightMode = self._onToggleNightMode
    else
        self.onToggleNightMode = nil
        self.onSetNightMode = nil
    end
    if self.fl_off_during_day then
        self.onToggleFrontlight = self._onToggleFrontlight
    end
end

function AutoWarmth:clearEventHandlers()
    self.onResume = nil
    self.onSuspend = nil
    self.onToggleNightMode = nil
    self.onSetNightMode = nil
    self.onToggleFrontlight = nil
end

-- from_resume ... true if called from onResume
function AutoWarmth:scheduleMidnightUpdate(from_resume)
    logger.dbg("AutoWarmth: scheduleMidnightUpdate")
    -- first unschedule all old functions
    UIManager:unschedule(self.scheduleMidnightUpdate)
    UIManager:unschedule(self.setWarmth)
    UIManager:unschedule(self.setFrontlight)

    -- Calculate current timezone of device, which might change due to daylight saving.
    local timezone = SunTime:getTimezoneOffset()
    if timezone ~= self.timezone then
        G_reader_settings:saveSetting("autowarmth_timezone", self.timezone)
        self.timezone = timezone
    end

    SunTime:setPosition(self.location, self.latitude, self.longitude, self.timezone, self.altitude, true)
    SunTime:setAdvanced()
    SunTime:setDate() -- today
    SunTime:calculateTimes() -- calculates times in hours

    self.sched_times_s = {}
    self.sched_warmths = {}

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
        self.current_times_h[1] = nil   -- Solar midnight prev. day
        self.current_times_h[2] = nil   -- Astronomical dawn
        self.current_times_h[3] = nil   -- Nautical dawn
        -- self.current_times_h[6] = nil   -- Solar noon
        self.current_times_h[9] = nil   -- Nautical dusk
        self.current_times_h[10] = nil  -- Astronomical dusk
        self.current_times_h[11] = nil  -- Solar midnight
    end

    -- here are dragons
    local prev_index = 1
    -- find first valid entry (~= nil)
    while not self.current_times_h[prev_index] and prev_index <= midnight_index do
        prev_index = prev_index + 1
    end
    local next_index
    while prev_index <= midnight_index do
        next_index = prev_index + 1
        -- find next valid entry (~= nil)
        while not self.current_times_h[next_index] and next_index <= midnight_index do
            next_index = next_index + 1
        end
        -- now we have two valid indices: prev_index and next_index
        prepareSchedule(self.current_times_h, prev_index, next_index)
        -- move on prev_index to the next valid entry
        prev_index = next_index
    end

    local now_s = SunTime:getTimeInSec()

    -- Reschedule 1sec after midnight
    UIManager:scheduleIn(24*3600 + 1 - now_s, self.scheduleMidnightUpdate, self)

    -- set event handlers
    if self.activate ~= 0 then
        self:setEventHandlers()
        -- Schedule the first warmth change
        self.sched_warmth_index = 1
        self:scheduleNextWarmthChange(from_resume)
        self:scheduleToggleFrontlight(now_s) -- reset user toggles at sun set or sun rise
        self:toggleFrontlight(now_s)
    else
        self:clearEventHandlers()
    end
end

function AutoWarmth:scheduleToggleFrontlight(now_s)
    logger.dbg("AutoWarmth: scheduleToggleFrontlight")

    UIManager:unschedule(self.setFrontlight)

    if not self.fl_off_during_day then
        return
    end
    -- Reset user fl toggles at sunset or sunrise with offset, as `scheduleNextWarmthChange` gets called only
    -- on scheduled warmth changes.
    local ss = self.current_times_h[7]
    local sunset_in_s =  ss and (ss * 3600 - self.fl_off_during_day_offset_s - now_s) or -1
    if sunset_in_s >= 0 then -- first check if we are before sunset
        UIManager:scheduleIn(sunset_in_s, self.setFrontlight, self, true, false)
    end
    local sr = self.current_times_h[5]
    local sunrise_in_s = sr and (sr * 3600 + self.fl_off_during_day_offset_s - now_s) or -1
    if sunrise_in_s >= 0 then -- second check if we are before sunrise
        UIManager:scheduleIn(sunrise_in_s, self.setFrontlight, self, false, false)
    end
end

-- turns frontlight on or off and notice AutoDim on turning it off
-- enable ... true to enable frontlight, false/nil to disable it
function AutoWarmth:setFrontlight(enable, keep_user_toggle)
    logger.dbg("AutoWarmth: setFrontlight", enable, keep_user_toggle)
    if not keep_user_toggle then
        AutoWarmth.fl_user_toggle = false
    end
    if not self.fl_off_during_day then
        return
    end

    UIManager:scheduleIn(0.01, function()
        if enable then
            Powerd:turnOnFrontlight()
            AutoWarmth.fl_turned_off = false
        else
            Powerd:turnOffFrontlight()
            AutoWarmth.fl_turned_off = true
            UIManager:broadcastEvent(Event:new("FrontlightTurnedOff")) -- used e.g. in AutoDim
        end
    end)
end

-- toggles Frontlight on or off, depending on `now_s`
function AutoWarmth:toggleFrontlight(now_s)
    logger.dbg("AutoWarmth: toggleFrontlight", now_s)

    if not self.fl_off_during_day then
        return
    end

    now_s = now_s or SunTime:getTimeInSec()
    local sr = self.current_times_h[5]
    local ss = self.current_times_h[7]
    local sunrise_in_s = sr and (sr * 3600 + self.fl_off_during_day_offset_s - now_s) or 0
    local sunset_in_s = sr and (ss * 3600 - self.fl_off_during_day_offset_s - now_s) or 0

    self:setFrontlight(sunrise_in_s > 0 or sunset_in_s < 0)
end

-- schedules the next warmth change
-- search_pos ... start searching from that index
-- from_resume ... true if first call after resume
function AutoWarmth:scheduleNextWarmthChange(from_resume)
    logger.dbg("AutoWarmth: scheduleNextWarmthChange")
    UIManager:unschedule(self.scheduleNextWarmthChange)

    if self.activate == 0 or #self.sched_warmths == 0 then
        return
    end

    if self.sched_warmth_index < 1 then
        self.sched_warmth_index = 1
    end

    -- `warmth_now` is the value which should be applied now.
    -- `warmth_in_1p5_s` is valid `1.5` seconds after now for resume on some devices (KA1)
    -- Most of the times this will be the same as `warmth_now`.
    -- We need both, as we could have a very rapid change in warmth (depending on user settings)
    -- or by chance a change in warmth very shortly after (a few ms) resume time.
    -- Use the last (== solar midnight) warmth value, so that we have a valid value when resuming
    -- before 24:00:00 but after true midnight. OK, this value is actually not quite the right one,
    -- as it is calculated for the current day (and not the previous one), but this is for a corner case
    -- and the error is small.
    local warmth_now = self.sched_warmths[self.sched_warmth_index]
    local warmth_in_1p5_s = warmth_now
    local now_s = SunTime:getTimeInSec()
    while self.sched_warmth_index <= #self.sched_warmths do
        if self.sched_times_s[self.sched_warmth_index] > now_s then
            break
        end

        -- update warmth_now
        warmth_now = self.sched_warmths[self.sched_warmth_index]
        local j = self.sched_warmth_index
        if from_resume then
            -- update warmth_in_1p5_s
            while j <= #self.sched_warmths and self.sched_times_s[j] <= now_s + 1.5 do
                -- Most times only one iteration through this loop
                warmth_in_1p5_s = self.sched_warmths[j]
                j = j + 1
            end
        end
        -- It might be possible that self.sched_warmth_index gets > #self.sched_warmths
        self.sched_warmth_index = self.sched_warmth_index + 1
    end

    -- update current warmth immediately
    self:setWarmth(warmth_now, from_resume) -- force warmth, when from_resume

    if self.sched_warmth_index <= #self.sched_warmths then -- and only then, schedule next warmth change
        local next_sched_time_s = self.sched_times_s[self.sched_warmth_index] - now_s
        UIManager:scheduleIn(next_sched_time_s, self.scheduleNextWarmthChange, self, false) -- no force warmth
    end

    if from_resume then
        -- On some strange devices like KA1 setWarmth doesn't work right after a resume so
        -- schedule setting of another valid warmth (=`warmth_in_1p5_s`) again (one time) in 1.5s.
        -- On sane devices this schedule does no harm.
        -- see https://github.com/koreader/koreader/issues/8363
        UIManager:scheduleIn(1.5, self.setWarmth, self, warmth_in_1p5_s, true) -- force warmth one time
    end
end

-- Set warmth and schedule the next warmth change
function AutoWarmth:setWarmth(val, force_warmth)
    -- A value > 100 means to set night mode and set warmth to maximum.
    -- We use an offset of 1000 to "flag", that night mode is on.
    if val then
        if self.control_nightmode then
            DeviceListener:onSetNightMode(val > 100)
        end

        if self.control_warmth and Device:hasNaturalLight() then
            val = math.min(val, 100) -- "mask" night mode
            Powerd:setWarmth(val, force_warmth)
        end
    end
end

function AutoWarmth:hoursToClock(hours)
    if hours then
        hours = hours % 24 * 3600 + 0.01 -- round up, due to reduced precision in settings.reader.lua
    end
    return datetime.secondsToClock(hours, self.easy_mode)
end

function AutoWarmth:addToMainMenu(menu_items)
    menu_items.autowarmth = {
        text = Device:hasNaturalLight() and _("Auto warmth and night mode") or _("Auto night mode"),
        checked_func = function() return self.activate ~= 0 end,
        sub_item_table = self:getSubMenuItems(),
    }
end

local function tidy_menu(menu, request)
    for i = #menu, 1, -1 do
        if menu[i].mode ~=nil then
            if menu[i].mode ~= request then
                table.remove(menu, i)
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
            check_callback_updates_menu = true,
            callback = function(touchmenu_instance)
                self.easy_mode = not self.easy_mode
                G_reader_settings:saveSetting("autowarmth_easy_mode", self.easy_mode)
                if self.easy_mode then
                    self.fl_off_during_day_offset_s = 0 -- don't store that value
                else
                    self.fl_off_during_day_offset_s =
                        G_reader_settings:readSetting("autowarmth_fl_off_during_day_offset_s", 0)
                end
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
                return self.activate ~= activate_sun and self.activate ~= 0
            end,
            sub_item_table = self:getScheduleMenu(),
        },
        {
            enabled_func = function()
                return self.activate ~= 0
            end,
            text = Device:hasNaturalLight() and _("Warmth and night mode settings") or _("Night mode settings"),
            sub_item_table_func = function() return self:getWarmthMenu() end,
        },
        self:getFlOffDuringDayMenu(),
        {
            text = _("Enable night mode warning"),
            checked_func = function()
                return not self.hide_nightmode_warning
            end,
            callback = function()
                self.hide_nightmode_warning = not self.hide_nightmode_warning
                G_reader_settings:saveSetting("autowarmth_hide_nightmode_warning", self.hide_nightmode_warning)
            end,
            separator = true,
        },
        self:getTimesMenu(_("Currently active parameters")),
        self:getTimesMenu(_("Sun position information for"), true, activate_sun),
        self:getTimesMenu(_("Fixed schedule information"), false, activate_schedule),
    }
end

function AutoWarmth:getFlOffDuringDayMenu()
    return {
        checked_func = function()
            return self.fl_off_during_day
        end,
        text_func = function()
            if self.fl_off_during_day and  self.fl_off_during_day_offset_s ~= 0 and not self.easy_mode then
                return T(_("Frontlight off during day: %1 min offset"), math.floor(self.fl_off_during_day_offset_s/60))
            else
                return _("Frontlight off during day")
            end
        end,
        check_callback_updates_menu = true,
        callback = function(touchmenu_instance)
            if self.easy_mode then
                self.fl_off_during_day = not self.fl_off_during_day
                G_reader_settings:saveSetting("autowarmth_fl_off_during_day", self.fl_off_during_day)
                self:scheduleMidnightUpdate()
                self:toggleFrontlight()
            else
                -- hard limit offset to 15 min after sunset and 30 mins before sunset; sunrise vice versa
                UIManager:show(SpinWidget:new{
                    title_text = _("Offset for frontlight off"),
                    info_text = _[[At this time the frontlight will be turned
  • off after sunrise and
  • on before sunset.]],
                    ok_always_enabled = true,
                    -- read the saved setting, as this gets overwritten by toggling easy_mode
                    value = G_reader_settings:readSetting("autowarmth_fl_off_during_day_offset_s", 0) * (1/60),
                    value_min = -15,
                    value_max = 30,
                    wrap = false,
                    value_step = 5,
                    value_hold_step = 10,
                    unit = "min",
                    ok_text = _("Set"),
                    callback = function(spin)
                        self.fl_off_during_day_offset_s = spin.value * 60
                        G_reader_settings:saveSetting("autowarmth_fl_off_during_day_offset_s",
                            self.fl_off_during_day_offset_s)
                        self.fl_off_during_day = true
                        G_reader_settings:saveSetting("autowarmth_fl_off_during_day", true)
                        self:scheduleMidnightUpdate()
                        self:toggleFrontlight()
                        if touchmenu_instance then self:updateItems(touchmenu_instance) end
                    end,
                    extra_text = _("Disable"),
                    extra_callback = function()
                        self.fl_off_during_day = nil
                        G_reader_settings:saveSetting("autowarmth_fl_off_during_day", nil)
                        self:scheduleMidnightUpdate()
                        self:toggleFrontlight()
                        if touchmenu_instance then self:updateItems(touchmenu_instance) end
                    end,
                })
            end

            if touchmenu_instance then
                self:updateItems(touchmenu_instance)
            end
        end,
        hold_callback = function()
            UIManager:show(InfoMessage:new{
                text = _([[This feature turns your front light on at sunset and off at sunrise according to the “Current Active Parameters” in this plugin.

You can override this change by manually turning the front light on/off. At the next sunrise/sunset, AutoWarmth will toggle again if needed.

For cloudy autumn days, the switch-on/off time can be shifted by an offset.]]),
            })
        end,
        keep_menu_open = true,
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
                    self.timezone = SunTime:getTimezoneOffset() -- use timezone of device
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
    -- mode == nil ... show always
    --      == true ... easy mode
    --      == false ... expert mode
    local function getScheduleMenuEntry(text, num, mode)
        return {
            mode = mode,
            text_func = function()
                return T(_("%1: %2"), text,
                    self:hoursToClock(self.scheduler_times[num]))
            end,
            checked_func = function()
                return self.scheduler_times[num] ~= nil
            end,
            check_callback_updates_menu = true,
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
                        local new_time = time.hour + time.min * (1/60)
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
                        elseif num < midnight_index and new_time > get_valid_time(num, 1) then
                            UIManager:show(ConfirmBox:new{
                                text = _("This time is after the subsequent time.\nAdjust the subsequent time?"),
                                ok_callback = function()
                                    for i = num + 1, midnight_index do
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
    -- mode == nil ... show always
    --      == true ... easy mode
    --      == false ... expert mode
    local function getWarmthMenuEntry(text, num, mode)
        return {
            mode = mode,
            text_func = function()
                if Device:hasNaturalLight() and self.control_warmth then
                    if self.control_nightmode then
                        if self.warmth[num] <= 100 then
                            return T(_("%1: %2 %"), text, self.warmth[num])
                        else
                            return T(_("%1: 100 % + ☾"), text)
                        end
                    else
                        if self.warmth[num] <= 100 then
                            return T(_("%1: %2 %"), text, self.warmth[num])
                        else
                            return T(_("%1: %2 %"), text, math.max(self.warmth[num] - 1000, 0))
                        end
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
                if Device:hasNaturalLight() and self.control_warmth then
                    local warmth_spinner = SpinWidget:new{
                        title_text = text,
                        info_text = _("Enter percentage of warmth."),
                        value = self.warmth[num] <= 100 and self.warmth[num] or math.max(self.warmth[num] - 1000, 0), -- mask nightmode
                        value_min = 0,
                        value_max = 100,
                        wrap = false,
                        value_step = math.floor(100 / device_max_warmth),
                        value_hold_step = 10,
                        unit = "%",
                        ok_text = _("Set"),
                        ok_always_enabled = true,
                        callback = function(spin)
                            self.warmth[num] = spin.value
                            if self.control_nightmode and self.night_mode_check_box.checked then
                                if self.warmth[num] <= 100 then
                                    self.warmth[num] = self.warmth[num] + 1000 -- add night mode
                                end
                            else
                                if self.warmth[num] > 100 then
                                    self.warmth[num] = math.max(self.warmth[num] - 1000, 0) -- delete night mode
                                end
                            end
                            self.warmth[#self.warmth - num + 1] = self.warmth[num]
                            G_reader_settings:saveSetting("autowarmth_warmth", self.warmth)
                            self:scheduleMidnightUpdate()
                            if touchmenu_instance then self:updateItems(touchmenu_instance) end
                        end,
                    }

                    if self.control_nightmode then
                        self.night_mode_check_box = CheckButton:new{
                            text = _("Night mode"),
                            checked = self.warmth[num] > 100,
                            parent = warmth_spinner,
                        }
                        warmth_spinner:addWidget(self.night_mode_check_box)
                    end
                    UIManager:show(warmth_spinner)
                else
                    UIManager:show(ConfirmBox:new{
                        text = _("Night mode"),
                        ok_text = _("Turn on"),
                        ok_callback = function()
                            if self.warmth[num] <= 100 then
                                self.warmth[num] = self.warmth[num] + 1000
                                self.warmth[#self.warmth - num + 1] = self.warmth[num]
                                G_reader_settings:saveSetting("autowarmth_warmth", self.warmth)
                                self:scheduleMidnightUpdate()
                                if touchmenu_instance then self:updateItems(touchmenu_instance) end
                            end
                        end,
                        cancel_text = _("Turn off"),
                        cancel_callback = function()
                            if self.warmth[num] > 100 then
                                self.warmth[num] = math.max(self.warmth[num] - 1000, 0) -- delete night mode
                                self.warmth[#self.warmth - num + 1] = self.warmth[num]
                                G_reader_settings:saveSetting("autowarmth_warmth", self.warmth)
                                self:scheduleMidnightUpdate()
                                if touchmenu_instance then self:updateItems(touchmenu_instance) end
                            end
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
            text_func = function()
                if Device:hasNaturalLight() then
                    return T(_("Control: %1%2%3"), self.control_warmth and _("warmth") or "",
                            self.control_warmth and self.control_nightmode and T(" %1 ", _("and")) or "",
                            self.control_nightmode and _("night mode") or "")
                else
                    return _("Control: night mode")
                end
            end,
            checked_func = function()
                if Device:hasNaturalLight() then
                    return self.control_nightmode or self.control_warmth
                else
                    return self.control_nightmode
                end
            end,
            hold_callback = function()
                if Device:hasNaturalLight() then
                    UIManager:show(InfoMessage:new{
                        text = _("Tapping here chooses between the different AutoWarmth modes: 'warmth only', 'warmth and night mode', 'night mode only'."),
                    })
                else
                    UIManager:show(InfoMessage:new{
                        text = _("Your device supports 'night mode' control only."),
                    })
                end
            end,
            check_callback_updates_menu = true,
            callback = function(touchmenu_instance)
                if Device:hasNaturalLight() then
                    if self.control_warmth and self.control_nightmode then
                        self.control_warmth = true
                        self.control_nightmode = false
                        G_reader_settings:makeTrue("autowarmth_control_warmth")
                        G_reader_settings:makeFalse("autowarmth_control_nightmode")
                    elseif self.control_warmth and not self.control_nightmode then
                        self.control_warmth = false
                        self.control_nightmode = true
                        G_reader_settings:makeFalse("autowarmth_control_warmth")
                        G_reader_settings:makeTrue("autowarmth_control_nightmode")
                    else
                        self.control_warmth = true
                        self.control_nightmode = true
                        G_reader_settings:makeTrue("autowarmth_control_warmth")
                        G_reader_settings:makeTrue("autowarmth_control_nightmode")
                    end
                else
                    self.control_nightmode = not self.control_nightmode
                    G_reader_settings:toggle("autowarmth_control_nightmode")
                end
                self:scheduleMidnightUpdate()
                if touchmenu_instance then self:updateItems(touchmenu_instance) end
            end,
            keep_menu_open = true,
            separator = true,
        },
        {
            text = Device:hasNaturalLight() and _("Set warmth and night mode for:") or _("Set night mode for:"),
            enabled = false,
        },
        getWarmthMenuEntry(_("Solar noon"), 6),
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
    local function info_line(indent, text, time, num, face, easy)
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
            .. self:hoursToClock(time)
        if easy then
            if time and num and self.current_times_h[num] and self.current_times_h[num] ~= time then
                return text .. "\n"
            else
                return ""
            end
        end

        if not time then -- entry deactivated
            return retval .. "\n"
        elseif Device:hasNaturalLight() and self.control_warmth then
            if self.current_times_h[num] == time then
                if self.warmth[num] <= 100 then
                    return retval .. " (💡" .. self.warmth[num] .. "%)\n"
                else
                    return retval .. " (💡100%" .. (self.control_nightmode and " + ☾" or "") .. ")\n"
                end
            else
                return retval .. "\n"
            end
        else
            if self.current_times_h[num] == time then
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

    local function add_line(indent, text, easy)
        return easy and "" or (string.rep(" ", indent) .. text .. "\n")
    end

    local face = Font:getFace("scfont")
    UIManager:show(InfoMessage:new{
        face = face,
        width = math.floor(Screen:getWidth() * (self.easy_mode and 0.85 or 0.90)),
        text = title .. location_string .. ":\n\n" ..
            info_line(0, _("Solar midnight:"), times[1], 1, face, request_easy) ..
            add_line(2, _("Dawn"), request_easy) ..
            info_line(4, _("Astronomic:"), times[2], 2, face, request_easy) ..
            info_line(4, _("Nautical:"), times[3], 3, face, request_easy)..
            info_line(request_easy and 0 or 4,
                request_easy and _("Twilight:") or _("Civil:"), times[4], 4, face) ..
            add_line(2, _("Dawn"), request_easy) ..
            info_line(0, _("Sunrise:"), times[5], 5, face) ..
            "\n" ..
            info_line(0, _("Solar noon:"), times[6], 6, face) ..
            "\n" ..
            info_line(0, _("Sunset:"), times[7], 7, face) ..
            add_line(2, _("Dusk"), request_easy) ..
            info_line(request_easy and 0 or 4,
                request_easy and _("Twilight:") or _("Civil:"), times[8], 8, face) ..
            info_line(4, _("Nautical:"), times[9], 9, face, request_easy) ..
            info_line(4, _("Astronomic:"), times[10], 10, face, request_easy) ..
            add_line(2, _("Dusk"), request_easy) ..
            info_line(0, _("Solar midnight:"), times[midnight_index], midnight_index, face, request_easy) ..
            -- add fl toggle
            add_line(0, "", not self.fl_off_during_day) ..
            add_line(0, _("Toggle frontlight off between"), not self.fl_off_during_day) ..
            add_line(4, T(_("%1 and %2"),
                times[5] and self:hoursToClock(times[5] + self.fl_off_during_day_offset_s * (1/3600)) or "",
                times[7] and self:hoursToClock(times[7] - self.fl_off_during_day_offset_s * (1/3600)) or ""),
                    not self.fl_off_during_day),
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
