--[[--
-- Author: Martin Zwicknagl (zwim)
-- Date: 2021-10-29
-- The current source code of this file can be found on https://github.com/zwim/suntime.

Module to calculate ephemeris and other times depending on the sun position.

Maximal errors from 2020-2050 (compared to https://midcdmz.nrel.gov/spa/) are:

* -43.52° Christchurch 66s
* -20.16° Mauritius:   25s
* 20.30° Honolulu:     47s
* 33.58° Casablanca:   24s
* 35.68° Tokio:        50s
* 37.97° Athene:       24s
* 38°    Sacramento:   67s
* 41.91° Rome:         27s
* 47.25° Innsbruck:    13s
* 52.32° Berlin:       30s
* 59.92° Oslo:         42s
* 64.14° Reykjavik:    69s
* 65.69° Akureyri:    <24s (except *)
* 70.67° Hammerfest: <105s (except **)

*) A few days around beginning of summer (error <290s)

**) A few days after and before midnight sun (error <1200s)

@usage
    local SunTime = require("suntime")

    time_zone = 0
    altitude = 50
    degree = true
    SunTime:setPosition("Reykjavik", 64.14381, -21.92626, timezone, altitude, degree)

    SunTime:setAdvanced()

    SunTime:setDate()

    SunTime:calculateTimes()

    print(SunTime.rise, SunTime.set, SunTime.set_civil) -- or similar see calculateTime()

@module suntime
--]]--

-- math abbreviations
local pi = math.pi
local pi_2 = pi/2

local abs = math.abs
local floor = math.floor
local sin = math.sin
local cos = math.cos
local tan = math.tan
local asin = math.asin
local acos = math.acos
local atan = math.atan

local toRad = pi/180
local toDeg = 1/toRad

local function Rad(x)
    return x*toRad
end

--------------------------------------------
local speed_of_light = 2.99792E8
local sun_radius = 6.96342e8
local average_earth_radius = 6371e3
local semimajor_axis = 149598022.96E3 -- earth orbit's major semi-axis in meter
local average_speed_earth = 29.7859e3
local aberration = asin(average_speed_earth/speed_of_light) -- Aberration relativistic
-- local average_speed_equator = (2*pi * average_earth_radius) / (24*3600)
--------------------------------------------

 -- minimal twillight times in hours
local min_civil_twilight = 20/60
local min_nautic_twilight = 45/60 - min_civil_twilight
local min_astronomic_twilight = 20/60 - min_nautic_twilight

local SunTime = {
        astronomic = Rad(-18),
        nautic =  Rad(-12),
        civil = Rad(-6),
        -- eod = Rad(-49/60), -- approx. end of day
        earth_flatten = 1 / 298.257223563, -- WGS84
        average_temperature = 10, -- °C

        times = {},
    }

----------------------------------------------------------------

-- simple 'Equation of time' good for dates between 2008-2027
-- errors for latitude 20° are within 1min
--                     47° are within 1min 30sec
--                     65° are within 5min
-- https://www.astronomie.info/zeitgleichung/#Auf-_und_Untergang (German)
function SunTime:getZglSimple()
    local T = self.date.yday
    return -0.171 * sin(0.0337 * T + 0.465)  - 0.1299 * sin(0.01787 * T - 0.168)
end

-- more advanced 'Equation of time' good for dates between 1800-2200
-- errors are better than with the simple method
-- https://de.wikipedia.org/wiki/Zeitgleichung (German) and
-- more infos on http://www.hlmths.de/Scilab/Zeitgleichung.pdf (German)
function SunTime:getZglAdvanced()
    local e = self.num_ex
    local e2 = e*e
    local e3 = e2*e
    local e4 = e3*e
    local e5 = e4*e

    -- https://de.wikibooks.org/wiki/Astronomische_Berechnungen_f%C3%BCr_Amateure/_Himmelsmechanik/_Sonne
    local C = (2*e - e3/4 + 5/96*e5) * self.sin_M
            + (5/4*e2 + 11/24*e4) * self.sin_2M
            + (13/12*e3 - 43/64*e5) * self.sin_3M
            + 103/96*e4 * self.sin_4M
            + 1097/960*e5 * self.sin_5M -- rad

    local lamb = self.L + C
    local tanL = tan(self.L)
    local tanLamb = tan(lamb)
    local cosEps = cos(self.epsilon)

    local zgl = atan( (tanL - tanLamb*cosEps) / (1 + tanL*tanLamb*cosEps) ) --rad
    return zgl*toDeg/15 --  to hours *4'/60
end

-- set current date or year/month/day daylightsaving hh/mm/ss
-- if dst == nil use current daylight saving of the system
local days_in_month = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}

function SunTime:setDate(year, month, day, dst, hour, min, sec)
    self.date = os.date("*t") -- get current day

    if year and month and day then
        self.date.year = year
        self.date.month = month
        self.date.day = day
        if year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0) then
            days_in_month[2] = 29
        else
            days_in_month[2] = 28
        end
        self.date.yday = day
        for i = 1, month-1 do
            self.date.yday = self.date.yday + days_in_month[i]
        end
        self.date.hour = hour or 12
        self.date.min = min or 0
        self.date.sec = sec or 0
        if dst ~= nil then
            self.date.isdst = dst
        end
    end
end

--[[--
Set position for later calculations

@param name Name of the location
@param latitude Geographical latitude, North is positive
@param longitude Geographical longitude, West is negative
@param time_zone Timezone e.g. CET = +1; if nil try to autodetect the current zone
@param altitude Altitude of the location above the sea level
@param degree if `nil` latitude and longitude are in radian, else in decimal degree
 --]]--
function SunTime:setPosition(name, latitude, longitude, time_zone, altitude, degree)
    altitude = altitude or 200
    if degree then
        latitude = latitude * toRad
        longitude = longitude * toRad
    end

    -- check for sane values
    -- latitudes are from -90° to +90°
    if latitude > pi_2 then
        latitude = pi_2
    elseif latitude < -pi_2 then
        latitude = -pi_2
    end
    -- longitudes are from -180° to +180°
    if longitude > pi then
        longitude = pi
    elseif longitude < -pi then
        longitude = -pi
    end

    latitude = atan((1-self.earth_flatten)^2 * tan(latitude))

    self.pos = {name = name, latitude = latitude, longitude = longitude, altitude = altitude}
    self.time_zone = time_zone or self:getTimezoneOffset()
--    self.refract = Rad(36.35/60 * .5 ^ (altitude / 5538)) -- constant temperature
    self.refract = Rad(36.20/60 * (1 - 0.0065*altitude/(273.15+self.average_temperature)) ^ 5.255 )

    self.sin_latitude = sin(self.pos.latitude)
    self.cos_latitude = cos(self.pos.latitude)
end

--[[--
  Use a simple equation of time (valid for the years 2008-2027)
--]]--
function SunTime:setSimple()
    self.getZgl = self.getZglSimple
end
--[[--
  Use an advanced equation of time (valid for the years 1800-2200 at least)
--]]--
function SunTime:setAdvanced()
    self.getZgl = self.getZglAdvanced
end

--[[--
  Function to get the equation of time, can be set by setSimple() or setAdvanced()
--]]--
SunTime.getZgl = SunTime.getZglAdvanced

function SunTime:daysSince2000(hour)
    local delta = self.date.year - 2000
    local leap = floor((delta-1)/4)
    return 365 * delta + leap + self.date.yday + (hour-12)/24   -- WMO No.8, rebased for 2000-01-01 12:00
end

-- more accurate parameters of earth orbit from
-- Title: Numerical expressions for precession formulae and mean elements for the Moon and the planets
-- Authors: Simon, J. L., Bretagnon, P., Chapront, J., Chapront-Touze, M., Francou, G., & Laskar, J., ,
-- Journal: Astronomy and Astrophysics (ISSN 0004-6361), vol. 282, no. 2, p. 663-683
-- Bibliographic Code: 1994A&A...282..663S
function SunTime:initVars(hour)
    if not hour then
        hour = 12
    end

    local after_noon = hour > 12

    local T = self:daysSince2000(hour)/36525 -- in Julian centuries form 2000-01-01 12:00

    --    self.num_ex = 0.0167086342 - 0.000042 * T
    -- numerical eccentricity of earth's orbit
    -- see wikipedia: https://de.wikipedia.org/wiki/Erdbahn-> Meeus
    --    and Numerical expressions for preccession formulae
    -- time is in Julian centuries
    self.num_ex =     0.0167086342     + T*(-0.0004203654e-1
                + T*(-0.0000126734e-2  + T*( 0.0000001444e-3
                + T*(-0.0000000002e-4  + T*  0.0000000003e-5))))

    --    self.epsilon = (23 + 26/60 + 21/3600 - 46.82/3600 * T) * toRad
    -- earth's obliquity to the ecliptic
    -- see Numerical expressions for precession formulae ...
    -- Time is here in Julian centuries
--    local epsilon = 23 + 26/60  + (21.412 + T*(-468.0927E-1
--                + T*(-0.0152E-2 + T*(1.9989E-3
--                + T*(-0.0051E-4 - T*0.0025E-5)))))/3600 --°

    -- Astronomical Almanac 2010, p. B52
    -- Time is here in Julian centuries
    local epsilon = 23 + 26/60 + (21.406 - T*(46.836769
                  - T*( 0.0001831 + T*(0.00200340
                  + T*(-5.76E-7   - T* 4.34E-8)))))/3600 --°

    self.epsilon = epsilon * toRad

    -- see Numerical expressions for precession formulae ...
    -- mean longitude
    local nT = T * (36000.7690/35999.3720) -- convert from equinox to date
    local L =  100.46645683   + (nT*(1295977422.83429E-1
            + nT*(-2.04411E-2 -  nT* 0.00523E-3)))/3600 --°
    self.L = (L - floor(L/360)*360) * toRad

    -- see Numerical expressions for precession formulae ...
    -- Time is here in Julian centuries
    local omega =     102.93734808 + nT*(11612.35290e-1
                + nT*(53.27577e-2  + nT*(-0.14095e-3
                + nT*( 0.11440e-4  + nT* 0.00478e-5))))/3600 --°

    -- mean anomaly
    local M = L - omega --°
    self.M = (M - floor(M/360)*360) * toRad

    self.sin_M = sin(self.M)
    self.cos_M = cos(self.M)

    -- sin(2x)=2 sin(x) cos(x)
    self.sin_2M = 2 * self.sin_M * self.cos_M

    -- sin(3x) = 3 sin(x) − 4 sin(x)^3
    self.sin_3M = 3 * self.sin_M - 4 * self.sin_M^3

    -- sin(4x) = 8 sin(x) cos(x)^3 - 4 sin(x) cos(x)
    self.sin_4M = 8 * self.sin_M * self.cos_M^3 - 4 * self.sin_M * self.cos_M

    -- sin(5x) = 5 sin(x) - 20 sin(x)^3+ 16 sin(x)^5
    self.sin_5M = 5 * self.sin_M - 20 * self.sin_M^3 + 16 * self.sin_M^5

    -- Deklination nach astronomie.info
    --  local decl = 0.4095 * sin(0.016906 * (self.date.yday - 80.086))
    --Deklination nach Brodbeck (2001)
    --  local decl = 0.40954 * sin(0.0172 * (self.date.yday - 79.349740))

    -- Deklination WMO-No.8 page I-7-37
    --local T = self.days_since_2000
    --local L = 280.460 + 0.9856474 * T
    --L = (L - floor(L/360)*360) * toRad
    --local g = 357.528 + 0.9856003 * T -- mean anomaly
    --g = (g - floor(g/360)*360) * toRad
    --local l =  L + (1.915 * sin (g) + 0.020 * sin (2*g))*toRad
    --local ep = self.epsilon
    --  -- sin(decl) = sin(ep)*sin(l)
    --self.decl = asin(sin(ep)*sin(l))

    -- Deklination WMO-No.8 page I-7-37
    local l =  self.L + pi + (1.915 * self.sin_M + 0.020 * self.sin_2M)*toRad
    self.decl = asin(sin(self.epsilon)*sin(l))

    -- Nutation see https://de.wikipedia.org/wiki/Nutation_(Astronomie)
    local A = { 2.18243920 - 33.7570460 * T,
               -2.77624462 + 1256.66393 * T,
                7.62068856 + 16799.4182 * T,
                4.36487839 - 67.5140919 * T}
    local B = {92025e-4 + 8.9e-4 * T,
                5736e-4 - 3.1e-4 * T,
                 977e-4 - 0.5e-4 * T,
                -895e-4 + 0.5e-4 * T}
    local delta_epsilon = 0 --"
    for i = 1, #A do
        delta_epsilon = delta_epsilon + B[i]*cos(A[i])
    end

    -- add nutation to declination
    self.decl = self.decl + delta_epsilon/3600*toRad

    -- https://de.wikipedia.org/wiki/Kepler-Gleichung#Wahre_Anomalie
    self.E = self.M + self.num_ex * self.sin_M + self.num_ex^2 / 2 * self.sin_2M
    self.r = semimajor_axis * (1 - self.num_ex * cos(self.E))

    --    self.eod = -atan(sun_radius/self.r) - self.refract
    --                                            ^- astronomical refraction (at altitude)

    if after_noon then
        self.eod = -atan((sun_radius-average_earth_radius*self.cos_latitude)/self.r) - self.refract
        self.eod = self.eod + aberration
    else
        self.eod = -atan((sun_radius+average_earth_radius*self.cos_latitude)/self.r) - self.refract
        self.eod = self.eod - aberration
    end

    self.zgl = self:getZgl()
end

function SunTime:getTimeDiff(height)
    local val = (sin(height) - self.sin_latitude*sin(self.decl))
                / (self.cos_latitude*cos(self.decl))

    if abs(val) > 1 then
        return
    end
    return 12/pi * acos(val)
end

-- get the sun height for a given time
-- eod for considering sun diameter and astronomic refraction
function SunTime:getHeight(time, eod)
    time = time - 12 -- subtrace 12, because JD starts at 12:00
    local val = cos(self.decl)*self.cos_latitude*cos(pi/12*time)
        + sin(self.decl)*self.sin_latitude

    if abs(val) > 1 then
        return
    end

    if eod then
        return asin(val) - eod -- self.eod might be a bit too small
    else
        return asin(val)
    end
end

-- Get time for a certain height
-- Set height to nil for sunset/rise
-- Set hour near to expected time
-- Set after_noon to true, if sunset is wanted
-- Set no_correct_dst if no daylight saving correction is wanted
-- Result rise or set time
--        nil sun does not reach the height
function SunTime:calculateTime(height, hour, after_noon, no_correct_dst)
    if not no_correct_dst then
        if self.date.isdst and hour then
            hour = hour - 1
        end
    end
    self:initVars(hour) -- calculate self.eod
    local timeDiff = self:getTimeDiff(height or self.eod, hour)
    if not timeDiff then
        return
    end

    local local_correction = self.time_zone - self.pos.longitude*12/pi - self.zgl
    if not after_noon then
        hour = 12 - timeDiff + local_correction
    else
        hour = 12 + timeDiff + local_correction
    end
    if not no_correct_dst then
        if self.date.isdst and hour then
            hour = hour + 1
        end
    end
    return hour
end

-- Calculates the hour, when the sun reaches height
-- If height is nil, use newly calculated self.eod
-- hour gives a start value, default is used when hour == nil
function SunTime:calculateTimeIter(height, hour, default_hour)
    local after_noon = (hour and hour > 12) or (default_hour and default_hour > 12)

    if not hour then -- do the iteration with the default value
        hour = self:calculateTime(height, default_hour, after_noon, true)
    elseif hour and not default_hour then -- do the full iteration with value
        hour = self:calculateTime(height, hour, after_noon, true)
    end -- if hour and default_hour are given don't do the first step

    if hour ~= nil then -- do the last calculation step
        hour = self:calculateTime(height, hour, hour > 12)
    end
    return hour
end

function SunTime:calculateNoon(hour)
    hour = hour or 12
    self:initVars(hour)
    local aberration_time = aberration / pi * 12 -- aberration in hours (angle/(2pi)*24)
    local dst = self.date.isdst and 1 or 0
    local local_correction = self.time_zone - self.pos.longitude*12/pi + dst - self.zgl
    if self.pos.latitude >= 0 then -- northern hemisphere
        if pi_2 - self.pos.latitude + self.decl > self.eod then
            if self:getHeight(hour) > 0 then
                return hour + local_correction + aberration_time
            end
        end
    else -- southern hemisphere
        if pi_2 + self.pos.latitude - self.decl > self.eod then
            if self:getHeight(hour) > 0 then
                return hour + local_correction + aberration_time
            end
        end
    end
end

function SunTime:calculateMidnight(hour)
    -- hour:
    -- 00 would be the beginning of the day
    -- 24 is the midnight at the end of the current day,
    hour = hour or 24
    self:initVars(hour)
    local dst = self.date.isdst and 1 or 0
    -- no aberration correction here, as you can't see the sun on her nadir ;-)
    local local_correction = self.time_zone - self.pos.longitude*12/pi + dst - self.zgl
    if self.pos.latitude >= 0 then -- northern hemisphere
        if pi_2 - self.pos.latitude - self.decl > self.eod then
            if self:getHeight(hour) < 0 then
                return hour + local_correction
            end
        end
    else -- southern hemisphere
        if pi_2 + self.pos.latitude + self.decl > self.eod then
            if self:getHeight(hour) < 0 then
                return hour + local_correction
            end
        end
    end
end

--[[--
Calculates the ephemeris and twilight times

@param fast_twilight If not nil, then exact twilight times will be calculated.

@usage
SunTime:calculateTimes(fast_twilight)


Times are in hours or `nil` if not applicable.

You can then access:
    self.midnight_beginning

    self.rise_astronomic
    self.rise_nautic
    self.rise_civil
    self.rise

    self.noon

    self.set
    self.set_civil
    self.set_nautic
    self.set_astronomic

    self.midnight

Or as values in a table:
    self.times[1]  midnight_beginning
    self.times[2]  rise_astronomic
    self.times[3]  rise_nautic
    self.times[4]  rise_civil
    self.times[5]  rise
    self.times[6]  noon
    self.times[7]  set
    self.times[8]  set_civil
    self.times[9]  set_nautic
    self.times[10] set_astronomic
    self.times[11] midnight
--]]--
function SunTime:calculateTimes(fast_twilight)
    -- All or some the times can be nil at great latitudes
    -- but either noon or midnight is not nil

    if not fast_twilight then
    -- The canonical way is to calculate everything from scratch
        self.rise = self:calculateTimeIter(nil, 6)
        self.set = self:calculateTimeIter(nil, 18)

        self.rise_civil = self:calculateTimeIter(self.civil, 6)
        self.set_civil = self:calculateTimeIter(self.civil, 18)
        self.rise_nautic = self:calculateTimeIter(self.nautic, 6)
        self.set_nautic = self:calculateTimeIter(self.nautic, 18)
        self.rise_astronomic = self:calculateTimeIter(self.astronomic, 6)
        self.set_astronomic = self:calculateTimeIter(self.astronomic, 18)
    else
        -- Calculate rise and set from scratch, use these values for twilight times
        self.rise = self:calculateTimeIter(nil, 6)
        self.rise_civil = self:calculateTimeIter(self.civil, self.rise - min_civil_twilight, 6)
        self.rise_nautic = self:calculateTimeIter(self.nautic, self.rise_civil - min_nautic_twilight, 6)
        self.rise_astronomic = self:calculateTimeIter(self.astronomic, self.rise_nautic - min_astronomic_twilight, 6)

        self.set = self:calculateTimeIter(nil, 18)
        self.set_civil = self:calculateTimeIter(self.civil, self.set + min_civil_twilight, 18)
        self.set_nautic = self:calculateTimeIter(self.nautic, self.set_civil + min_nautic_twilight, 18)
        self.set_astronomic = self:calculateTimeIter(self.astronomic, self.set_nautic + min_astronomic_twilight, 18)
    end

    self.midnight_beginning = self:calculateMidnight(0)
    self.noon = self:calculateNoon()
    self.midnight = self:calculateMidnight()

    -- Sometimes at high latitudes noon or midnight does not get calculated.
    -- Maybe there is a minor bug in the calculateNoon/calculateMidnight functions.
    if self.rise and self.set then
        if not self.noon and self.rise and self.set then
            self.noon = (self.rise + self.set) / 2
        end
        if not self.midnight and self.noon then
            self.midnight = self.noon + 12
        end
        if not self.midnight_beginning and self.midnight then
            self.midnight_beginning = self.midnight - 24
        elseif not self.midnight and self.midnight_beginning then
            self.midnight = self.midnight_beginning + 24
        end
    elseif self.rise and not self.set then -- only sunrise on that day
        self.midnight = nil
        self.midnight_beginning = nil
    elseif self.set and not self.rise then -- only sunset on that day
        self.noon = nil
    end

    self.times[1]  = self.midnight_beginning
    self.times[2]  = self.rise_astronomic
    self.times[3]  = self.rise_nautic
    self.times[4]  = self.rise_civil
    self.times[5]  = self.rise
    self.times[6]  = self.noon
    self.times[7]  = self.set
    self.times[8]  = self.set_civil
    self.times[9]  = self.set_nautic
    self.times[10] = self.set_astronomic
    self.times[11] = self.midnight
end

-- Get time in seconds, rounded to ms (either actual time in hours or date struct)
function SunTime:getTimeInSec(val)
    if not val then
        val = os.date("*t")
    end

    if type(val) == "table" then
        val = val.hour*3600 + val.min*60 + val.sec
    else
        val = val*3600
    end
    return math.floor(val * 1000) * (1/1000)
end

-- Get the timezone offset in hours (including dst).
 function SunTime:getTimezoneOffset()
    local now_ts = os.time()
    local utcdate   = os.date("!*t", now_ts)
    local localdate = os.date("*t", now_ts)
    return os.difftime(os.time(localdate), os.time(utcdate)) * (1/3600)
end

return SunTime
