
-- Author: Martin Zwicknagl (zwim)
-- Date: 2021-10-29
-- The current source code of this file can be found on https://github.com/zwim/suntime.

--[[--
Module to calculate ephemeris and other times depending on the sun position

Maximal errors from 2020-2050 are:

* 33.58° Casablanca:   24s
* 37.97° Athene:       25s
* 41.91° Rome:         28s
* 47.25° Innsbruck:    14s
* 52.32° Berlin:       32s
* 64.14° Reykjavik:   113s
* 65.69° Akureyri:   <110s (except *)
* 70.67° Hammerfest: <105s (except **)

*) A few days around beginning of summer (error <530s)

**) A few days after and befor midnight sun (error <1200s)

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

-- math abbrevations
local toRad = math.pi/180
local toDeg = 1/toRad

local floor = math.floor
local sin = math.sin
local cos = math.cos
local tan = math.tan
local asin = math.asin
local acos = math.acos
local atan = math.atan

local function Rad(x)
    return x*toRad
end

--------------------------------------------

local SunTime = {}

SunTime.astronomic = Rad(-18)
SunTime.nautic =  Rad(-12)
SunTime.civil = Rad(-6)
-- SunTime.eod = Rad(-49/60) -- approx. end of day
SunTime.earth_flatten = 1 / 298.257223563 -- WGS84
SunTime.average_temperature = 10 -- °C

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

    local M = self.M
    -- https://de.wikibooks.org/wiki/Astronomische_Berechnungen_f%C3%BCr_Amateure/_Himmelsmechanik/_Sonne
    local C = (2*e - e3/4 + 5/96*e5) * sin(M)
            + (5/4*e2 + 11/24*e4) * sin(2*M)
            + (13/12*e3 - 43/64*e5) * sin(3*M)
            + 103/96*e4 * sin(4*M)
            + 1097/960*e5 * sin(5*M) -- rad

    local lamb = self.L + C
    local tanL = tan(self.L)
    local tanLamb = tan(lamb)
    local cosEps = cos(self.epsilon)

    local zgl = atan( (tanL - tanLamb*cosEps) / (1 + tanL*tanLamb*cosEps) ) --rad
    return zgl*toDeg/15 --  to hours *4'/60
end

-- set current date or year/month/day daylightsaving hh/mm/ss
-- if dst == nil use curent daylight saving of the system
function SunTime:setDate(year, month, day, dst, hour, min, sec)
    self.date = os.date("*t") -- get current day

    if year and month and day then
        self.date.year = year
        self.date.month = month
        self.date.day = day
        local feb = 28
        if year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0) then
            feb = 29
        end
        local days_in_month = {31, feb, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}
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

    if not self.getZgl then
        self.getZgl = self.getZglAdvanced
    end
end

--[[--
Set position for later calculations

@param name Name of the location
@param latitude Geographical latitude, North is positive
@param longitude Geographical longitude, West is negative
@param time_zone Timezone e.g. CET = +1
@param altitude Altitude of the location above the sea level
@param degree if `nil` latitude and longitue are in radian, else in decimal degree
 --]]--
function SunTime:setPosition(name, latitude, longitude, time_zone, altitude, degree)
    altitude = altitude or 200
    if degree then
        latitude = latitude * toRad
        longitude = longitude * toRad
    end

    -- check for sane values
    -- latitudes are from -90° to +90°
    if latitude > math.pi/2 then
        latitude = math.pi/2
    elseif latitude < -math.pi/2 then
        latitude = -math.pi/2
    end
    -- longitudes are from -180° to +180°
    if longitude > math.pi then
        longitude = math.pi
    elseif longitude < -math.pi then
        longitude = -math.pi
    end

    self.pos = {name, latitude = latitude, longitude = longitude, altitude = altitude}
    self.time_zone = time_zone
--    self.refract = Rad(36.35/60 * .5 ^ (altitude / 5538)) -- constant temperature
    self.refract = Rad(36.20/60 * (1 - 0.0065*altitude/(273.15+self.average_temperature)) ^ 5.255 )
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
    local l =  self.L + math.pi + (1.915 * sin (self.M) + 0.020 * sin (2*self.M))*toRad
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
    self.E = self.M + self.num_ex * sin(self.M) + self.num_ex^2 / 2 * sin(2*self.M)
    self.a = 149598022.96E3 -- große Halbachse in meter
    self.r = self.a * (1 - self.num_ex * cos(self.E))

    self.eod = -atan(6.96342e8/self.r) - self.refract
    --                ^--sun radius            ^- astronomical refraction (at altitude)

    self.zgl = self:getZgl()
end

function SunTime:getTimeDiff(height)
    local val = (sin(height) - sin(self.pos.latitude)*sin(self.decl))
                / (cos(self.pos.latitude)*cos(self.decl))

    if math.abs(val) > 1 then
        return
    end
    return 12/math.pi * acos(val)
end

-- Get time for a certain height
-- Set hour near to expected time
-- Sed after_noon to true, if sunset is wanted
-- Result rise or set time
--        nil sun does not reach the height
function SunTime:calculateTime(height, hour, after_noon)
    local dst = self.date.isdst and 1 or 0
    local timeDiff = self:getTimeDiff(height, hour)
    if not timeDiff then
        return
    end

    local local_correction = self.time_zone - self.pos.longitude*12/math.pi + dst - self.zgl
    if not after_noon then
        return 12 - timeDiff + local_correction
    else
        return 12 + timeDiff + local_correction
    end
end

-- If height is nil, use newly calculated self.eod
function SunTime:calculateTimeIter(height, hour)
    local after_noon = hour > 12

    self:initVars(hour) -- calculate self.eod
    hour = self:calculateTime(height or self.eod, hour, after_noon)
    if hour ~= nil then
        self:initVars(hour)  -- calculate self.eod
        hour = self:calculateTime(height or self.eod, hour, after_noon)
    end
    return hour
end

function SunTime:calculateNoon()
    self:initVars(12)
    if self.pos.latitude >= 0 then -- northern hemisphere
        if math.pi/2 - self.pos.latitude + self.decl > self.eod then
            local dst = self.date.isdst and 1 or 0
            local local_correction = self.time_zone - self.pos.longitude*12/math.pi + dst - self.zgl
            return 12 + local_correction
        end
    else -- sourthern hemisphere
        if math.pi/2 + self.pos.latitude - self.decl > self.eod then
            local dst = self.date.isdst and 1 or 0
            local local_correction = self.time_zone - self.pos.longitude*12/math.pi + dst - self.zgl
            return 12 + local_correction
        end
    end
end

function SunTime:calculateMidnight()
    -- 24 is the midnight at the end of the current day,
    -- 00 would be the beginning of the day
    self:initVars(24)
    if self.pos.latitude >= 0 then -- northern hemisphere
        if math.pi/2 - self.pos.latitude - self.decl > self.eod then
            local dst = self.date.isdst and 1 or 0
            local local_correction = self.time_zone - self.pos.longitude*12/math.pi + dst - self.zgl
            return 24 + local_correction
        end
    else -- southern hemisphere
        if math.pi/2 + self.pos.latitude + self.decl > self.eod then
            local dst = self.date.isdst and 1 or 0
            local local_correction = self.time_zone - self.pos.longitude*12/math.pi + dst - self.zgl
            return 24 + local_correction
        end
    end

end

--[[--
Calculates the ephemeris and twilight times

@usage
SunTime:calculateTime()

Times are in hours or `nil` if not applicable.

You can then access:
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
    self.times[1]  midnight - 24h
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
function SunTime:calculateTimes()
    -- All or some the times can be nil at great latitudes
    -- but either noon or midnight is not nil!
    self.rise = self:calculateTimeIter(nil, 6)
    self.set = self:calculateTimeIter(nil, 18)

    self.rise_civil = self:calculateTimeIter(self.civil, 6)
    self.set_civil = self:calculateTimeIter(self.civil, 18)
    self.rise_nautic = self:calculateTimeIter(self.nautic, 6)
    self.set_nautic = self:calculateTimeIter(self.nautic, 18)
    self.rise_astronomic = self:calculateTimeIter(self.astronomic, 6)
    self.set_astronomic = self:calculateTimeIter(self.astronomic, 18)

    self.noon = self:calculateNoon()
    self.midnight = self:calculateMidnight()

    self.times = {}
    self.times[1]  = self.midnight and (self.midnight - 24)
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

-- Get time in seconds (either actual time in hours or date struct)
function SunTime:getTimeInSec(val)
    if not val then
        val = os.date("*t")
    end

    if type(val) == "table" then
        return val.hour*3600 + val.min*60 + val.sec
    end

    return val*3600
end

return SunTime
