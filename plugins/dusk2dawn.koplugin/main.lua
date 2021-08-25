--[[--
@module koplugin.dusk2dawn

Plugin for setting screen warmth based on the sun position and/or a time schedule
]]

local Device = require("device")

if not Device:hasNaturalLight() then
    return { disabled = true }
end

local ConfirmBox = require("ui/widget/confirmbox")
local DoubleSpinWidget = require("/ui/widget/doublespinwidget")
local FFIUtil = require("ffi/util")
local InfoMessage = require("ui/widget/infomessage")
local Font = require("ui/font")
local SpinWidget = require("ui/widget/spinwidget")
local SunTime = require("suntime")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local T = FFIUtil.template

local activate_sun = 1
local activate_schedule = 2
local activate_closer_noon = 3
local activate_closer_midnight =4

local Dusk2Dawn = WidgetContainer:new{
    name = "dusk2dawn",
    activate = G_reader_settings:readSetting("dusk2dawn_activate") or 0,
    location = G_reader_settings:readSetting("dusk2dawn_location") or "Geysir",
    latitude = G_reader_settings:readSetting("dusk2dawn_latitude") or 64.31, --great Geysir in Iceland
    longitude = G_reader_settings:readSetting("dusk2dawn_longitude") or -20.30,
    timezone = G_reader_settings:readSetting("dusk2dawn_timezone") or 0,
    scheduler_times = G_reader_settings:readSetting("dusk2dawn_scheduler_times") or
        {0.0, 5.5, 6.0, 6.5, 7.0, 13.0, 21.5, 22.0, 22.5, 23.0, 24.0},
    warmth =   G_reader_settings:readSetting("dusk2dawn_warmth")
        or { 90, 90, 80, 60, 20, 20, 20, 60, 80, 90, 90},
    sched_times = {},
    sched_funcs = {}, -- necessary for unschedule, function, warmth
    sched_index = 1,
}

-- get timezone offset in hours (including dst)
function Dusk2Dawn:getTimezoneOffset()
    local utcdate   = os.date("!*t")
    local localdate = os.date("*t")
    return os.difftime(os.time(localdate), os.time(utcdate))/3600
end

function Dusk2Dawn:init()
    self.ui.menu:registerToMainMenu(self)

    -- schedule recalculation shortly afer midnight
    self:scheduleMidnightUpdate()
end

function Dusk2Dawn:onResume()
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
function Dusk2Dawn:setWarmth(val)
    Device.powerd:setWarmth(val)
end

function Dusk2Dawn:scheduleMidnightUpdate()
    -- first unschedule all old functions
    UIManager:unschedule(self.scheduleMidnightUpdate) -- when called from menu or resume

    local toRad = math.pi / 180
    SunTime:setPosition(self.location, self.latitude * toRad, self.longitude * toRad,
        self.timezone)
    SunTime:setAdvanced()
    SunTime:setDate() -- today
    SunTime:calculateTimes()

    self.sched_index = 0
    self.sched_funcs = {}
    self.sched_times = {}

    local function prepareSchedule(times, index1, index2)
        local time1 = times[index1]
        if not time1 then return end -- to near to the pole; sun does not set/rise

        local time = SunTime:getTimeInSec(time1)
        self.sched_times[self.sched_index] = time
        self.sched_funcs[self.sched_index] = {Dusk2Dawn.setWarmth, Dusk2Dawn,
            self.warmth[index1]}
        self.sched_index = self.sched_index + 1

        local time2 = times[index2]
        if not time2 then return end-- to near to the pole
        local warmth_diff = self.warmth[index2] - self.warmth[index1]
        if warmth_diff ~= 0 then
            local time_diff = SunTime:getTimeInSec(time2) - time
            local delta_t = time_diff / math.abs(warmth_diff) -- can be inf, no problem
            local delta_w =  warmth_diff > 0 and 1 or -1
            for i = 1, math.abs(warmth_diff)-1 do
                local next_warmth = self.warmth[index1] + delta_w * i
                -- only apply warmth for steps the hardware has (e.g. Tolino has 0-10 hw steps
                -- which map to warmth 0, 10, 20, 30 ... 100)
                if SunTime:frac(next_warmth / 100 * Device.powerd.fl_warmth_max) == 0 then
                    self.sched_times[self.sched_index] = time + delta_t * i
                    self.sched_funcs[self.sched_index] = {self.setWarmth, self,
                        math.floor(self.warmth[index1] + delta_w * i)}
                    self.sched_index = self.sched_index + 1
                end
            end
        end
    end

    if self.activate == activate_sun then
        self.current_times = {unpack(SunTime.times)}
    elseif self.activate == activate_schedule then
        self.current_times = {unpack(self.scheduler_times)}
    else
        self.current_times = {unpack(SunTime.times)}
        if self.activate == activate_closer_noon then
            for i = 1, #self.current_times do
                if math.abs(self.current_times[i] - 12) > math.abs(self.scheduler_times[i]-12) then
                    self.current_times[i] = self.scheduler_times[i]
                end
            end
        else -- activate_closer_midnight
            for i = 1, #self.current_times do
                if math.abs(self.current_times[i] - 12) < math.abs(self.scheduler_times[i]-12) then
                    self.current_times[i] = self.scheduler_times[i]
                end
            end
        end
    end

    -- here are dragons
    for i = 1, #self.current_times-1 do
       prepareSchedule(self.current_times, i, i+1)
    end

    local now = SunTime:getTimeInSec()

    -- reschedule 5sec after midnight
    UIManager:scheduleIn(24*3600 + 5 - now, self.scheduleMidnightUpdate, self )

    self:scheduleWarmthChanges(now)
end

function Dusk2Dawn:scheduleWarmthChanges(now)
    for i = 1, #self.sched_funcs do -- loop not essential, as unschedule unschedules all functions at once
        if not UIManager:unschedule(self.sched_funcs[i][1]) then
            break
        end
    end

    local actual_warmth = self.warmth[1]
    for i = 1, #self.sched_funcs do
        if self.sched_times[i] > now then
            UIManager:scheduleIn( self.sched_times[i] - now,
                self.sched_funcs[i][1], self.sched_funcs[i][2], self.sched_funcs[i][3])
        else
            actual_warmth = self.sched_funcs[i][3]
        end
    end
    -- update current warmth directly
    self:setWarmth(actual_warmth)
end

function Dusk2Dawn:addToMainMenu(menu_items)
    menu_items.dusk2dawn = {
        text = _("Dusk till dawn"),
        sorting_hint = "screen",
        checked_func = function() return self.activate ~= 0 end,
        sub_item_table_func = function()
            return self:getSubMenuItems()
        end,
    }
end

function Dusk2Dawn:getActivateMenu()
    local function getActivateMenuEntry(text, activator)
        return {
            text = text,
            checked_func = function() return self.activate == activator end,
            callback = function()
                if self.activate ~= activator then
                    self.activate = activator
                else
                    self.activate = 0
                end
                G_reader_settings:saveSetting("dusk2dawn_activate", self.activate)
                self:scheduleMidnightUpdate()
            end,
        }
    end

    return {
        getActivateMenuEntry( _("Sun position"), activate_sun),
        getActivateMenuEntry( _("Time schedule"), activate_schedule),
        getActivateMenuEntry( _("Whatever is closer to noon"), activate_closer_noon),
        getActivateMenuEntry( _("Whatever is closer to midnight"), activate_closer_midnight),
    }
end

function Dusk2Dawn:getWarmthMenu()
    local function getWarmthMenuEntry(text, num)
        return {
            text_func = function()
                return T(_"%1 (%2%)", text, self.warmth[num])
            end,
            callback = function(touchmenu_instance)
                UIManager:show(SpinWidget:new{
                    width = math.floor(Device.screen:getWidth() * 0.6),
                    title_text = text,
                    value = self.warmth[num],
                    value_min = 0,
                    value_max = 100,
                    wrap = false,
                    value_step = math.floor(100 / Device.powerd.fl_warmth_max),
                    value_hold_step = 10,
                    ok_text = _("Set"),
                    callback = function(spin)
                        self.warmth[num] = spin.value
                        self.warmth[#self.warmth - num + 1] = spin.value
                        G_reader_settings:saveSetting("dusk2dawn_warmth", self.warmth)
                        self:scheduleMidnightUpdate()
                        if touchmenu_instance then touchmenu_instance:updateItems() end
                    end
                })
            end,
            keep_menu_open = true,
        }
    end

    return {
        {
            text = _("Set warmth for:"),
            enabled_func = function() return false end,
        },
        getWarmthMenuEntry(_("High noon"), 6),
        getWarmthMenuEntry(_("Daytime"), 5),
        getWarmthMenuEntry(_("Darkest time of civil dawn"), 4),
        getWarmthMenuEntry(_("Darkest time of nautical dawn"), 3),
        getWarmthMenuEntry(_("Darkest time of astronomical dawn"), 2),
        getWarmthMenuEntry(_("Midnight"), 1),
    }
end

function Dusk2Dawn:getScheduleMenu()
    local function getScheduleMenuEntry(text, num)
        return {
            text_func = function()
                return T(_"%1  (%2)", text, SunTime:formatTime(self.scheduler_times[num]))
            end,
            callback = function(touchmenu_instance)
                UIManager:show(DoubleSpinWidget:new{
                    title_text = _("Set time"),
    --                    info_text = _("")
                    left_text = _("HH"),
                    left_value = math.floor(self.scheduler_times[num]),
                    left_default = 0,
                    left_min = 0,
                    left_max = 23,
                    left_step = 1,
                    left_hold_step = 3,
                    left_wrap = true,
                    right_text = _("MM"),
                    right_value = math.floor(self.scheduler_times[num]/60),
                    right_default = 0,
                    right_min = 0,
                    right_max = 59,
                    right_step = 1,
                    right_hold_step = 5,
                    right_wrap = true,
                    callback = function(left, right)
                        local new_time = left + right / 60
                        local function store_times()
                            self.scheduler_times[num] = new_time
                            if num == 1 then
                                self.scheduler_times[11] = self.scheduler_times[1]
                            end
                            G_reader_settings:saveSetting("dusk2dawn_scheduler_times",
                                self.scheduler_times)
                            self:scheduleMidnightUpdate()
                            touchmenu_instance:updateItems()
                        end

                        if num > 1 and new_time < self.scheduler_times[num - 1] then
                            UIManager:show(ConfirmBox:new{
                                text =  _("This time conflicts with the previous time.\nShall the previous time be adjusted?"),
                                ok_callback = function()
                                    for i = num-1, 1, -1 do
                                        if new_time < self.scheduler_times[i] then
                                            self.scheduler_times[i] = new_time
                                        else
                                            break
                                        end
                                    end
                                    store_times()
                                end,
                            })
                        elseif num < 10 and new_time > self.scheduler_times[num + 1] then
                            UIManager:show(ConfirmBox:new{
                                text =  _("This time conflicts with the subsequent time.\nShall the subsequent time be adjusted?"),
                                ok_callback = function()
                                    for i = num + 1, 10  do
                                        if new_time > self.scheduler_times[i] then
                                            self.scheduler_times[i] = new_time
                                        else
                                            break
                                        end
                                    end
                                    store_times()
                                end,
                            })
                        else
                            store_times()
                        end
                    end,
                })
            end,
            keep_menu_open = true,
        }
    end

    return {
        getScheduleMenuEntry(_("Midnight"), 1),
        getScheduleMenuEntry(_("Astronomical sunrise"), 2),
        getScheduleMenuEntry(_("Nautical sunrise"), 3),
        getScheduleMenuEntry(_("Civil sunrise"), 4),
        getScheduleMenuEntry(_("Sunrise"), 5),
        getScheduleMenuEntry(_("High noon"), 6),
        getScheduleMenuEntry(_("Sunset"), 7),
        getScheduleMenuEntry(_("Civil sunset"), 8),
        getScheduleMenuEntry(_("Nautical sunset"), 9),
        getScheduleMenuEntry(_("Astronomical sunset"), 10),
    }
end

local about_text = _([[Set the frontlight warmth based on a time schedule or the sun's position.

There are three types of twilight:
• Civil: You can read a newspaper.
• Nautical: You can see the first stars.
• Astronomical: It is really dark.

Certain warmth-values can be set for every kind of twilight and sunrise, noon, sunset and midnight.
The screen warmth is continuously adjusted to the current time.

To use the sun's position, the geographical location must be entered. The calculations are very precise (deviation less than two minutes).]])
function Dusk2Dawn:getSubMenuItems()
    return {
        {
            text = _("About dusk till dawn"),
            callback = function()
                UIManager:show(InfoMessage:new{
                    text = about_text,
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
            text = _("Location"),
            enabled_func = function() return self.activate ~= activate_schedule end,
            callback = function(touchmenu_instance)
                local location_widget = DoubleSpinWidget:new{
                    title_text = _("Set location"),
                    info_text = _("Enter decimal degrees, northern hemisphere and eastern length are '+'."),
                    left_text = _("Latitude"),
                    left_value = self.latitude,
                    left_default = 0,
                    left_min = -90,
                    left_max = 90,
                    left_step = 0.1,
                    precision = "%0.2f",
                    left_hold_step = 5,
                    right_text = _("Longitude"),
                    right_value = self.longitude,
                    right_default = 0,
                    right_min = -180,
                    right_max = 180,
                    right_step = 0.1,
                    right_hold_step = 5,
                    callback = function(lat, long)
                        self.latitude = lat
                        self.longitude = long
                        self.timezone = self:getTimezoneOffset() -- use timezone of device
                        G_reader_settings:saveSetting("dusk2dawn_latitude", self.latitude)
                        G_reader_settings:saveSetting("dusk2dawn_longitude", self.longitude)
                        G_reader_settings:saveSetting("dusk2dawn_timezone", self.timezone)
                        self:scheduleMidnightUpdate()
                        touchmenu_instance:updateItems()
                    end,
                }
                UIManager:show(location_widget)
            end,
            keep_menu_open = true,
        },
        {
            text = _("Schedule"),
            enabled_func = function() return self.activate ~= activate_sun end,
            sub_item_table = self:getScheduleMenu(),
            keep_menu_open = true,
        },
        {
            text = _("Warmths"),
            sub_item_table = self:getWarmthMenu(),
            keep_menu_open = true,
            separator = true,
        },
        self:getTimesMenu(_("Current parameters")),
        self:getTimesMenu(_("Sun parameters"), activate_sun),
        self:getTimesMenu(_("Schedule parameters"), activate_schedule),
    }
end

function Dusk2Dawn:showTimesInfo(title, activator)
    local times
    if not activator then
        times = self.current_times
    elseif activator == activate_sun then
        times = SunTime.times
    elseif activator == activate_schedule then
        times = self.scheduler_times
    end

    local function info_line(t, num)
        return SunTime:formatTime(t[num]) .. " (💡 " .. self.warmth[num] ..")"
    end

    UIManager:show(InfoMessage:new{
        face = Font:getFace("scfont"),
--        show_icon = false,
        text = title .. ":\n" ..
            _("\nMidnight        ") .. info_line(times, 1) ..
            _("\n  Dawn") ..
            _("\n    Astronomic: ") .. info_line(times, 2) ..
            _("\n    Nautical:   ") .. info_line(times, 3) ..
            _("\n    Civil:      ") .. info_line(times, 4) ..
            _("\n  Dawn") ..
            _("\nSunrise:        ") .. info_line(times, 5) ..
            _("\n\nHigh noon:      ") .. info_line(times, 6) ..
            _("\n\nSunset:         ") .. info_line(times, 7) ..
            _("\n  Dusk") ..
            _("\n    Civil:      ") .. info_line(times, 8) ..
            _("\n    Nautical:   ") .. info_line(times, 9) ..
            _("\n    Astronomic: ") .. info_line(times, 10) ..
            _("\n  Dusk") ..
            _("\nMidnight        ") .. info_line(times, 11) ..
            "\n",
    })
end

function Dusk2Dawn:getTimesMenu(title, activator)
    return {
        text = title,
        callback = function()
            self:showTimesInfo(title, activator)
        end,
        keep_menu_open = true,
    }
end

return Dusk2Dawn
