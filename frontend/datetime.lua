--[[--
This module contains date translations and helper functions for the KOReader frontend.
]]

local BaseUtil = require("ffi/util")
local _ = require("gettext")
local C_ = _.pgettext
local T = BaseUtil.template

local datetime = {}

datetime.weekDays = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" } -- in Lua wday order

datetime.shortMonthTranslation = {
    ["Jan"] = _("Jan"),
    ["Feb"] = _("Feb"),
    ["Mar"] = _("Mar"),
    ["Apr"] = _("Apr"),
    ["May"] = _("May"),
    ["Jun"] = _("Jun"),
    ["Jul"] = _("Jul"),
    ["Aug"] = _("Aug"),
    ["Sep"] = _("Sep"),
    ["Oct"] = _("Oct"),
    ["Nov"] = _("Nov"),
    ["Dec"] = _("Dec"),
}

datetime.longMonthTranslation = {
    ["January"] = _("January"),
    ["February"] = _("February"),
    ["March"] = _("March"),
    ["April"] = _("April"),
    ["May"] = _("May"),
    ["June"] = _("June"),
    ["July"] = _("July"),
    ["August"] = _("August"),
    ["September"] = _("September"),
    ["October"] = _("October"),
    ["November"] = _("November"),
    ["December"] = _("December"),
}

datetime.shortDayOfWeekTranslation = {
   ["Mon"] = _("Mon"),
   ["Tue"] = _("Tue"),
   ["Wed"] = _("Wed"),
   ["Thu"] = _("Thu"),
   ["Fri"] = _("Fri"),
   ["Sat"] = _("Sat"),
   ["Sun"] = _("Sun"),
}

datetime.shortDayOfWeekToLongTranslation = {
    ["Mon"] = _("Monday"),
    ["Tue"] = _("Tuesday"),
    ["Wed"] = _("Wednesday"),
    ["Thu"] = _("Thursday"),
    ["Fri"] = _("Friday"),
    ["Sat"] = _("Saturday"),
    ["Sun"] = _("Sunday"),
}

--[[--
Converts seconds to a clock string.

Source: <a href="https://gist.github.com/jesseadams/791673">https://gist.github.com/jesseadams/791673</a>
]]
---- @int seconds number of seconds
---- @bool withoutSeconds if true 00:00, if false 00:00:00
---- @treturn string clock string in the form of 00:00 or 00:00:00
function datetime.secondsToClock(seconds, withoutSeconds, withDays)
    seconds = tonumber(seconds)
    if not seconds then
        if withoutSeconds then
            return "--:--"
        else
            return "--:--:--"
        end
    elseif seconds == 0 or seconds ~= seconds then
        if withoutSeconds then
            return "00:00"
        else
            return "00:00:00"
        end
    else
        local round = withoutSeconds and require("optmath").round or function(n) return n end
        local days = "0"
        local hours
        if withDays then
            days = string.format("%d", seconds * (1/(24*3600))) -- implicit math.floor for string.format
            hours = string.format("%02d", (seconds * (1/3600)) % 24)
        else
            hours = string.format("%02d", seconds * (1/3600))
        end
        local mins = string.format("%02d", round(seconds % 3600 * (1/60)))
        if withoutSeconds then
            if mins == "60" then
                -- Can only happen because of rounding, which only happens if withoutSeconds...
                mins = string.format("%02d", 0)
                hours = string.format("%02d", hours + 1)
            end
            return  (days ~= "0" and (days .. C_("Time", "d")) or "") .. hours .. ":" .. mins
        else
            local secs = string.format("%02d", seconds % 60)
            return (days ~= "0" and (days .. C_("Time", "d")) or "") .. hours .. ":" .. mins .. ":" .. secs
        end
    end
end

--- Converts seconds to a period of time string.
---- @int seconds number of seconds
---- @bool withoutSeconds if true 1h30', if false 1h30'10"
---- @bool hmsFormat, if true format 1h 30m 10s
---- @bool withDays, if true format 1d12h30'10" or 1d 12h 30m 10s
---- @bool compact, if set removes all leading zeros (incl. units if necessary) and turns thinspaces into hairspaces (if present)
---- @treturn string clock string in the form of 1h30'10" or 1h 30m 10s
function datetime.secondsToHClock(seconds, withoutSeconds, hmsFormat, withDays, compact)
    local SECONDS_SYMBOL = "\""
    seconds = tonumber(seconds)
    if seconds == 0 then
        if withoutSeconds then
            if hmsFormat then
                return T(_("%1m"), "0")
            else
                return "0'"
            end
        else
            if hmsFormat then
                return T(C_("Time", "%1s"), "0")
            else
                return "0" .. SECONDS_SYMBOL
            end
        end
    elseif seconds < 60 then
        if withoutSeconds and seconds < 30 then
            if hmsFormat then
                return T(C_("Time", "%1m"), "0")
            else
                return "0'"
            end
        elseif withoutSeconds and seconds >= 30 then
            if hmsFormat then
                return T(C_("Time", "%1m"), "1")
            else
                return "1'"
            end
        else
            if hmsFormat then
                if compact then
                    return T(C_("Time", "%1s"), string.format("%d", seconds))
                else
                    return T(C_("Time", "%1m\xE2\x80\x89%2s"), "0", string.format("%d", seconds)) -- use a thin space
                end
            else
                if compact then
                    return string.format("%d", seconds) .. SECONDS_SYMBOL
                else
                    return "0'" .. string.format("%02d", seconds) .. SECONDS_SYMBOL
                end
            end
        end
    else
        local time_string = datetime.secondsToClock(seconds, withoutSeconds, withDays)
        if withoutSeconds then
            time_string = time_string .. ":"
        end
        time_string = time_string:gsub(":", C_("Time", "h"), 1)
        time_string = time_string:gsub(":", C_("Time", "m"), 1)
        time_string = time_string:gsub("^00" .. C_("Time", "h"), "") -- delete leading "00h"
        time_string = time_string:gsub("^00" .. C_("Time", "m"), "") -- delete leading "00m"
        if time_string:find("^0%d") then
            time_string = time_string:gsub("^0", "") -- delete leading "0"
        end
        if withoutSeconds and time_string == "" then
            time_string = "0" .. C_("Time", "m")
        end

        if hmsFormat then
            time_string = time_string:gsub("0(%d)", "%1") -- delete all leading "0"s
            time_string = time_string:gsub(C_("Time", "d"), C_("Time", "d") .. "\u{2009}") -- add thin space after "d"
            time_string = time_string:gsub(C_("Time", "h"), C_("Time", "h") .. "\u{2009}") -- add thin space after "h"
            if not withoutSeconds then
                time_string = time_string:gsub(C_("Time", "m"), C_("Time", "m") .. "\u{2009}") .. C_("Time", "s")  -- add thin space after "m"
            end
            if compact then
                time_string = time_string:gsub("\u{2009}", "\u{200A}") -- replace thin space with hair space
            end
            return time_string
        else
            time_string = time_string:gsub(C_("Time", "m"), "'") -- replace m with '
            return withoutSeconds and time_string or (time_string .. SECONDS_SYMBOL)
        end
    end
end

--- Converts seconds to a clock type (classic or modern), based on the given format preference
--- "Classic" format calls secondsToClock, "Modern" and "Letters" formats call secondsToHClock
---- @string Either "modern" for 1h30'10", "letters" for 1h 30m 10s, or "classic" for 1:30:10
---- @bool withoutSeconds if true 1h30' or 1h 30m, if false 1h30'10" or 1h 30m 10s
---- @bool withDays, if hours>=24 include days in clock string 1d12h10'10" or 1d 12h 10m 10s
---- @bool compact, if set removes all leading zeros (incl. units if necessary) and turns thinspaces into hairspaces (if present)
---- @treturn string clock string in the specific format of 1h30', 1h30'10" resp. 1h 30m, 1h 30m 10s
function datetime.secondsToClockDuration(format, seconds, withoutSeconds, withDays, compact)
    if format == "modern" then
        return datetime.secondsToHClock(seconds, withoutSeconds, false, withDays, compact)
    elseif format == "letters" then
        return datetime.secondsToHClock(seconds, withoutSeconds, true, withDays, compact)
    else
         -- Assume "classic" to give safe default
        return datetime.secondsToClock(seconds, withoutSeconds, withDays)
    end
end

if jit.os == "Windows" then
    --- Converts timestamp to an hour string
    ---- @int seconds number of seconds
    ---- @bool twelve_hour_clock
    ---- @treturn string hour string
    ---- @note: The MS CRT doesn't support either %l & %k, or the - format modifier (as they're not technically C99 or POSIX).
    ----        They are otherwise supported on Linux, BSD & Bionic, so, just special-case Windows...
    ----        We *could* arguably feed the os.date output to gsub("^0(%d)(.*)$", "%1%2"), but, while unlikely,
    ----        it's conceivable that a translator would put something other that the hour at the front of the string ;).
    function datetime.secondsToHour(seconds, twelve_hour_clock)
        if twelve_hour_clock then
            if os.date("%p", seconds) == "AM" then
                -- @translators This is the time in the morning using a 12-hour clock (%I is the hour, %M the minute).
                return os.date(_("%I:%M AM"), seconds)
            else
                -- @translators This is the time in the afternoon using a 12-hour clock (%I is the hour, %M the minute).
                return os.date(_("%I:%M PM"), seconds)
            end
        else
            -- @translators This is the time using a 24-hour clock (%H is the hour, %M the minute).
            return os.date(_("%H:%M"), seconds)
        end
    end
else
    function datetime.secondsToHour(seconds, twelve_hour_clock, pad_with_spaces)
        if twelve_hour_clock then
            if os.date("%p", seconds) == "AM" then
                if pad_with_spaces then
                    -- @translators This is the time in the morning using a 12-hour clock (%_I is the hour, %M the minute).
                    return os.date(_("%_I:%M AM"), seconds)
                else
                    -- @translators This is the time in the morning using a 12-hour clock (%-I is the hour, %M the minute).
                    return os.date(_("%-I:%M AM"), seconds)
                end
            else
                if pad_with_spaces then
                    -- @translators This is the time in the afternoon using a 12-hour clock (%_I is the hour, %M the minute).
                    return os.date(_("%_I:%M PM"), seconds)
                else
                    -- @translators This is the time in the afternoon using a 12-hour clock (%-I is the hour, %M the minute).
                    return os.date(_("%-I:%M PM"), seconds)
                end
            end
        else
            if pad_with_spaces then
                -- @translators This is the time using a 24-hour clock (%_H is the hour, %M the minute).
                return os.date(_("%_H:%M"), seconds)
            else
                -- @translators This is the time using a 24-hour clock (%-H is the hour, %M the minute).
                return os.date(_("%-H:%M"), seconds)
            end
        end
    end
end

--- Converts timestamp to a date string
---- @int seconds number of seconds
---- @use_locale if true allows to translate the date-time string, if false return "%Y-%m-%d time"
---- @treturn string date string
function datetime.secondsToDate(seconds, use_locale)
    seconds = seconds or os.time()
    if use_locale then
        local wday  = os.date("%a", seconds)
        local month = os.date("%b", seconds)
        local day   = os.date("%d", seconds)
        local year  = os.date("%Y", seconds)

        -- @translators Use the following placeholders in the desired order: %1 name of day, %2 name of month, %3 day, %4 year
        return T(C_("Date string", "%1 %2 %3 %4"),
            datetime.shortDayOfWeekTranslation[wday], datetime.shortMonthTranslation[month], day, year)
    else
        -- @translators This is the date (%Y is the year, %m the month, %d the day)
        return os.date(C_("Date string", "%Y-%m-%d"), seconds)
    end
end

--- Converts timestamp to a date+time string
---- @int seconds number of seconds
---- @bool twelve_hour_clock
---- @use_locale if true allows to translate the date-time string, if false return "%Y-%m-%d time"
---- @treturn string date+time
function datetime.secondsToDateTime(seconds, twelve_hour_clock, use_locale)
    seconds = seconds or os.time()
    if twelve_hour_clock == nil then
        twelve_hour_clock = G_reader_settings:isTrue("twelve_hour_clock")
    end
    local BD = require("ui/bidi")
    local date_string = datetime.secondsToDate(seconds, use_locale)
    local time_string = datetime.secondsToHour(seconds, twelve_hour_clock, not use_locale)

    -- @translators Use the following placeholders in the desired order: %1 date, %2 time
    local message_text = T(C_("Date string", "%1 %2"), BD.wrap(date_string), BD.wrap(time_string))
    return message_text
end

--- Converts a date+time string to seconds
---- @string "YYYY-MM-DD HH:MM:SS", time may be absent
---- @treturn seconds
function datetime.stringToSeconds(datetime_string)
    local year, month, day = datetime_string:match("(%d+)-(%d+)-(%d+)")
    local hour, min, sec   = datetime_string:match("(%d+):(%d+):(%d+)")
    return os.time({ year = year, month = month, day = day, hour = hour or 0, min = min or 0, sec = sec or 0 })
end

return datetime
