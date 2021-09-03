--[[--
@module koplugin.autowarmth

Plugin for setting screen warmth based on the sun position and/or a time schedule
]]

local Device = require("device")

local ConfirmBox = require("ui/widget/confirmbox")
local DoubleSpinWidget = require("/ui/widget/doublespinwidget")
local DeviceListener = require("device/devicelistener")
local FFIUtil = require("ffi/util")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Font = require("ui/font")
local SpinWidget = require("ui/widget/spinwidget")
local SunTime = require("suntime")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local T = FFIUtil.template
local Screen = require("device").screen
local util = require("util")

local activate_sun = 1
local activate_schedule = 2
local activate_closer_noon = 3
local activate_closer_midnight =4

local midnight_index = 11

local device_max_warmth = Device:hasNaturalLight() and Device.powerd.fl_warmth_max or 100

local function frac(x)
    return x - math.floor(x)
end

local AutoWarmth = WidgetContainer:new{
    name = "autowarmth",
    easy_mode = G_reader_settings:isTrue("autowarmth_easy_mode") or false,
    activate = G_reader_settings:readSetting("autowarmth_activate") or 0,
    location = G_reader_settings:readSetting("autowarmth_location") or "Geysir",
    latitude = G_reader_settings:readSetting("autowarmth_latitude") or 64.31, --great Geysir in Iceland
    longitude = G_reader_settings:readSetting("autowarmth_longitude") or -20.30,
    timezone = G_reader_settings:readSetting("autowarmth_timezone") or 0,
    scheduler_times = G_reader_settings:readSetting("autowarmth_scheduler_times") or
        {0.0, 5.5, 6.0, 6.5, 7.0, 13.0, 21.5, 22.0, 22.5, 23.0, 24.0},
    warmth =   G_reader_settings:readSetting("autowarmth_warmth")
        or { 90, 90, 80, 60, 20, 20, 20, 60, 80, 90, 90},
    sched_times = {},
    sched_funcs = {}, -- necessary for unschedule, function, warmth
    sched_index = 1,
}

-- get timezone offset in hours (including dst)
function AutoWarmth:getTimezoneOffset()
    local utcdate   = os.date("!*t")
    local localdate = os.date("*t")
    return os.difftime(os.time(localdate), os.time(utcdate))/3600
end

function AutoWarmth:init()
    self.ui.menu:registerToMainMenu(self)

    -- schedule recalculation shortly afer midnight
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
    if val and val > 100 then
        DeviceListener:onSetNightMode(true)
    else
        DeviceListener:onSetNightMode(false)
    end
    if val and Device:hasNaturalLight() then
        val = val <= 100 and val or 100
        Device.powerd:setWarmth(val)
    end
end

function AutoWarmth:scheduleMidnightUpdate()
    -- first unschedule all old functions
    UIManager:unschedule(self.scheduleMidnightUpdate) -- when called from menu or resume

    local toRad = math.pi / 180
    SunTime:setPosition(self.location, self.latitude * toRad, self.longitude * toRad,
        self.timezone)
    SunTime:setAdvanced()
    SunTime:setDate() -- today
    SunTime:calculateTimes()

    self.sched_funcs = {}
    self.sched_times = {}

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
                local fit_scale = 1
                if Device:hasNaturalLight() then
                    fit_scale = next_warmth / 100 * device_max_warmth
                end
                if frac(next_warmth / fit_scale) == 0 then
                    table.insert(self.sched_times, time + delta_t * i)
                    table.insert(self.sched_funcs, {self.setWarmth,
                        math.floor(math.min(self.warmth[index1], 100) + delta_w * i)})
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
            for i = 1, midnight_index do
                if not self.current_times[i] then
                    self.current_times[i] = self.scheduler_times[i]
                elseif self.scheduler_times[i] and
                    math.abs(self.current_times[i] - 12) > math.abs(self.scheduler_times[i] - 12) then
                    self.current_times[i] = self.scheduler_times[i]
                end
            end
        else -- activate_closer_midnight
            for i = 1, midnight_index do
                if not self.current_times[i] then
                    self.current_times[i] = self.scheduler_times[i]
                elseif self.scheduler_times[i] and
                    math.abs(self.current_times[i] - 12) < math.abs(self.scheduler_times[i] - 12) then
                    self.current_times[i] = self.scheduler_times[i]
                end
            end
        end
        -- corner case, if some entries are unused
        table.sort(self.current_times, function(a,b) return a < b end)
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

function AutoWarmth:scheduleWarmthChanges(now)
    for i = 1, #self.sched_funcs do -- loop not essential, as unschedule unschedules all functions at once
        if not UIManager:unschedule(self.sched_funcs[i][1]) then
            break
        end
    end

    local actual_warmth
    for i = 1, #self.sched_funcs do
        if self.sched_times[i] > now then
            UIManager:scheduleIn( self.sched_times[i] - now,
                self.sched_funcs[i][1], self.sched_funcs[i][2])
        else
            actual_warmth = self.sched_funcs[i][2] or actual_warmth
        end
    end
    -- update current warmth directly
    self.setWarmth(actual_warmth)
end

function AutoWarmth:hoursToClock(hours, withoutSeconds)
    if hours then
        hours = hours % 24 * 3600 + 0.01 -- round up, due to reduced precision in settings.reader.lua
    end
    return util.secondsToClock(hours, withoutSeconds)
end

function AutoWarmth:addToMainMenu(menu_items)
    menu_items.autowarmth = {
        text = _("Auto-warmth"),
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

local about_text = _([[Set the frontlight warmth and night mode based on a time schedule or the sun's position.

There are three types of twilight:
• Civil: You can read a newspaper.
• Nautical: You can see the first stars.
• Astronomical: It is really dark.

Certain warmth-values can be set for every kind of twilight and sunrise, noon, sunset and midnight.
The screen warmth is continuously adjusted to the current time.

To use the sun's position, the geographical location must be entered. The calculations are very precise (deviation less than two minutes).]])
function AutoWarmth:getSubMenuItems()
    return {
        {
            text = _("About auto-warmth"),
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
            text = _("Easy mode"),
            checked_func = function()
                return self.easy_mode
            end,
            help_text = _("Easy mode disables all entries except: civil dawn, sun rise, sun set and covil dusk."),
            callback = function(touchmenu_instance)
                local info_text
                if not self.easy_mode then
                    info_text = _("Reduce entries in auto-warmth schedule?")
                else
                    info_text = _("Expand entries in auto-warmth schedule?")
                end
                UIManager:show(ConfirmBox:new{
                    text = info_text,
                    ok_callback = function()
                        self.easy_mode = not self.easy_mode
                        G_reader_settings:saveSetting("autowarmth_easy_mode", self.easy_mode)
                        self:scheduleMidnightUpdate()
                        -- closing menu is necessary for refreshing the menu structure
                        if touchmenu_instance then touchmenu_instance:closeMenu() end
                    end,
                })
            end,
            keep_menu_open = true,
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
            sub_item_table = self:getLocationMenu(),
        },
        {
            text = _("Schedule"),
            enabled_func = function() return self.activate ~= activate_sun end,
            sub_item_table = self:getScheduleMenu(),
        },
        {
            text = _("Warmths"),
            sub_item_table = self:getWarmthMenu(),
            separator = true,
        },
        self:getTimesMenu(_("Active auto-warmth parameters")),
        self:getTimesMenu(_("Infos about the sun in"), true, activate_sun),
        self:getTimesMenu(_("Infos about the schedule"), false, activate_schedule),
    }
end

function AutoWarmth:getActivateMenu()
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
                G_reader_settings:saveSetting("autowarmth_activate", self.activate)
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
    }}
end

function AutoWarmth:getScheduleMenu()
    local function store_times(touchmenu_instance, new_time, num)
        self.scheduler_times[num] = new_time
        if num == 1 then
            if self.scheduler_times[1] then
                self.scheduler_times[midnight_index]
                    = self.scheduler_times[1] + 24 -- next day
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
                    self:hoursToClock(self.scheduler_times[num], true))
            end,
            checked_func = function()
                return self.scheduler_times[num] ~= nil
            end,
            callback = function(touchmenu_instance)
                local hh = 12
                local mm = 0
                if self.scheduler_times[num] then
                    hh = math.floor(self.scheduler_times[num])
                    mm = math.floor(frac(self.scheduler_times[num])*60+0.5)
                end
                UIManager:show(DoubleSpinWidget:new{
                    title_text = _("Set time"),
                    left_text = _("HH"),
                    left_value = hh,
                    left_default = 0,
                    left_min = 0,
                    left_max = 23,
                    left_step = 1,
                    left_hold_step = 3,
                    left_wrap = true,
                    right_text = _("MM"),
                    right_value = mm,
                    right_default = 0,
                    right_min = 0,
                    right_max = 59,
                    right_step = 1,
                    right_hold_step = 5,
                    right_wrap = true,
                    callback = function(left, right)
                        local new_time = left + right / 60
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
                                text =  _("This time conflicts with the previous time.\nShall the previous time be adjusted?"),
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
                                text =  _("This time conflicts with the subsequent time.\nShall the subsequent time be adjusted?"),
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
        getScheduleMenuEntry(_("Midnight"), 1, false ),
        getScheduleMenuEntry(_("Astronomical dawn"), 2, false),
        getScheduleMenuEntry(_("Nautical dawn"), 3, false),
        getScheduleMenuEntry(_("Civil dawn"), 4),
        getScheduleMenuEntry(_("Sunrise"), 5),
        getScheduleMenuEntry(_("High noon"), 6, false),
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
                        width = math.floor(Device.screen:getWidth() * 0.6),
                        title_text = text,
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
            text = _("Set warmth for:"),
            enabled_func = function() return false end,
        },
        getWarmthMenuEntry(_("High noon"), 6, false),
        getWarmthMenuEntry(_("Daytime"), 5),
        getWarmthMenuEntry(_("Darkest time of civil dawn"), 4, false),
        getWarmthMenuEntry(_("Darkest time of civil twilight"), 4, true),
        getWarmthMenuEntry(_("Darkest time of nautical dawn"), 3, false),
        getWarmthMenuEntry(_("Darkest time of astronomical dawn"), 2, false),
        getWarmthMenuEntry(_("Midnight"), 1, false),
    }

    return tidy_menu(retval, self.easy_mode)
end

-- title
-- location: add a location string
-- activator: nil               .. current_times,
--            activate_sun      .. sun times
--            activate_schedule .. scheduler times
function AutoWarmth:getTimesMenu(title, location, activator)
    local function showTimesInfo()
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
        -- flag ... if true, only show easy_mode entries
        local function info_line(text, t, num, flag)
            local retval = text .. self:hoursToClock(t[num])
            if flag and self.current_times[num] ~= t[num] then
                return ""
            end
            if not t[num] then -- entry deactivated
                return ""
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

        UIManager:show(InfoMessage:new{
            face = Font:getFace("scfont"),
            width = math.floor(Screen:getWidth() * 0.90),
                text = title .. location_string .. ":\n\n" ..
                info_line(_("Midnight        "), times, 1, self.easy_mode) ..
                _("  Dawn\n") ..
                info_line(_("    Astronomic: "), times, 2, self.easy_mode) ..
                info_line(_("    Nautical:   "), times, 3, self.easy_mode) ..
                info_line(_("    Civil:      "), times, 4) ..
                _("  Dawn\n") ..
                info_line(_("Sunrise:        "), times, 5) ..
                info_line(_("\nHigh noon:      "), times, 6, self.easy_mode) ..

                info_line(_("\nSunset:         "), times, 7) ..
                _("  Dusk\n") ..
                info_line(_("    Civil:      "), times, 8) ..
                info_line(_("    Nautical:   "), times, 9, self.easy_mode) ..
                info_line(_("    Astronomic: "), times, 10, self.easy_mode) ..
                _("  Dusk\n") ..
                info_line(_("Midnight        "), times, midnight_index, self.easy_mode)
        })
    end

    return {
        text_func = function()
            if location then
                return title .. " " .. self:getLocationString()
            end
            return title
        end,
        callback = function()
            showTimesInfo(title, location, activator)
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
