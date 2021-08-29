
-- usage
-- SunTime:setPosition()
-- SunTime:setSimple() or SunTime:setAdvanced()
-- SunTime:setDate()
-- SunTime:calculate(height, hour)  height==Rad(0°)-> Midday; hour=6 or 18 for rise or set
-- SunTime:calculateTimes()
-- use values

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

local SunTime = {}

function SunTime:frac(x)
    return x - floor(x)
end

SunTime.astronomic = Rad(-18)
SunTime.nautic =  Rad(-12)
SunTime.civil = Rad(-6)
--local refract = 1013*.5^(500/5500)/1013*36 + 31.5/2; -- 500m Meereshöhe + Sonnendurchmesser
-- SunTime.eod = Rad(-49/60) -- approx. end of day

-- simple 'Equation of time' good for dates between 2008-2027
-- errors for latitude 20° are within 1min
--                     47° are within 1min 30sec
--                     65° are within 5min
-- https://www.astronomie.info/zeitgleichung/#Auf-_und_Untergang (German)
function SunTime:getZglSimple()
    local T = self.date.yday
    return -0.171 * sin(0.0337 * T + 0.465)  - 0.1299 * sin(0.01787 * T - 0.168)
end

-- more advanced 'Equation of time' goot for dates between 1800-2200
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
    self.oldDate = self.date

    self.date = os.date("*t")

    if year and month and day and hour and min and sec then
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

    -- use cached results
    if self.olddate and self.oldDate.day == self.date.day and
        self.oldDate.month == self.date.month and
        self.oldDate.year == self.date.year and
        self.oldDate.isdst == self.date.isdst then
        return
    end

    self:initVars()

    if not self.getZgl then
        self.getZgl = self.getZglAdvanced
    end

    self.zgl = self:getZgl()
end

function SunTime:setPosition(name, latitude, longitude, time_zone)
    if self.name == name and self.pos.latitude == latitude and self.pos.longitude == longitude
        and self.time_zone == time_zone then
        return
    end

    if self.date then
        self.olddate.year = -1
    end --invalidate cache
    self.name = name
    self.pos = {latitude = latitude, longitude = longitude}
    self.time_zone = time_zone
end

function SunTime:setSimple()
    self.getZgl = self.getZglSimple
end
function SunTime:setAdvanced()
    self.getZgl = self.getZglAdvanced
end

function SunTime:daysSince2000()
    local delta = self.date.year - 2000
    local leap = floor(delta/4) + 1 -- +1 for 2000, which was a leap year
    local days_since_2000 = delta * 365 + leap + self.date.yday    -- WMO No.8
    return days_since_2000
end

-- more accurate parameters of earth orbit from_
-- Title: Numerical expressions for precession formulae and mean elements for the Moon and the planets
-- Authors: Simon, J. L., Bretagnon, P., Chapront, J., Chapront-Touze, M., Francou, G., & Laskar, J., ,
-- Journal: Astronomy and Astrophysics (ISSN 0004-6361), vol. 282, no. 2, p. 663-683
-- Bibliographic Code: 1994A&A...282..663S
function SunTime:initVars()
    self.days_since_2000 = self:daysSince2000()
    local T = self.days_since_2000/36525
--    self.num_ex = 0.016709 - 0.000042 * T
--    self.num_ex = 0.0167086342 - 0.000042 * T
    -- see wikipedia: https://de.wikipedia.org/wiki/Erdbahn-> Meeus
    self.num_ex = 0.0167086342         + T*(-0.0004203654e-1
                + T*(-0.0000126734e-2  + T*(0.0000001444e-3
                + T*(-0.0000000002e-4  + T*0.0000000003e-5))))

--    self.epsilon = (23 + 26/60 + 21/3600 - 46.82/3600 * T) * toRad
    -- see wikipedia: https://de.wikipedia.org/wiki/Erdbahn-> Meeus
    local epsilon = 23 + 26/60 + (21.412 + T*(-46.80927
                + T*(-0.000152   + T*(0.00019989
                + T*(-0.00000051 - T*0.00000025)))))/3600 --°
    self.epsilon = epsilon * toRad

    -- shift from time to Equinox as data is given for JD2000.0, but date is in days from 20000101
    local nT = T * 1.0000388062
--    local L = (280.4656 + 36000.7690 * T ) --°
    -- see Numerical expressions for precession formulae ...
    local L = 100.46645683 + (nT*(1295977422.83429E-1
            + nT*(-2.04411E-2 - nT* 0.00523E-3)))/3600--°
    self.L = (L - floor(L/360)*360) * toRad

--    local omega (282.9400 + 1.7192 * T) --°
    -- wikipedia: https://de.wikipedia.org/wiki/Erdbahn-> Meeus
    local omega = 102.93734808        + nT*(17.194598028e-1
                + nT*( 0.045688325e-2 + nT*(-0.000017680e-3
                + nT*(-0.000033583e-4 + nT*( 0.000000828e-5
                + nT*  0.000000056e-6))))) --°

    local M = L - omega
    self.M = (M - floor(M/360)*360) * toRad

    -- https://de.wikipedia.org/wiki/Kepler-Gleichung#Wahre_Anomalie
    self.E = self.M + self.num_ex * sin(self.M) + self.num_ex^2 / 2 * sin(2*self.M)
    self.a = 149598022.96E3 -- große Halbaches in m
    self.r = self.a * (1 - self.num_ex * cos(self.E))
    self.eod = -atan(6.96342e8/self.r) - Rad(33.3/60)
--                ^--sun radius                ^- astronomical refraction (400m altitude)
end
--------------------------

function SunTime:getTimeDiff(height, hour)
    -- Deklination nach astronomie.info
--    local decl = 0.4095 * sin(0.016906 * (self.date.yday - 80.086))
    --Deklination nach Brodbeck (2001)
--    local decl = 0.40954 * sin(0.0172 * (self.date.yday-79.349740))

    --Deklination nach WMO-No.8
    local x = (36000/36525 * (self.date.yday+hour/24) - 2.72)*toRad
    local decl = asin(0.397748 * sin(x + (1.92*sin(x) - 77.51)*toRad))

    local val = (sin(height) - sin(self.pos.latitude)*sin(decl))
                / (cos(self.pos.latitude)*cos(decl))

    if math.abs(val) > 1 then
        return
    end
    return 12/math.pi * acos(val)
end

-- get time for a certain height
-- result rise and set times
--        nil and nil sun does not reach the height
function SunTime:calculateTime(height, hour)
    hour = hour or 12
    local dst = self.date.isdst and 1 or 0
    local timeDiff = self:getTimeDiff(height, hour)
    if not timeDiff then
        return
    end
    local local_correction = self.time_zone - self.pos.longitude*12/math.pi + dst - self.zgl

    if hour < 12 then
        return 12 - timeDiff + local_correction
    else
        return 12 + timeDiff + local_correction
    end
end

function SunTime:calculateTimeIter(height, hour)
    local x = self:calculateTime(height, hour)
    return self:calculateTime(height, x)
end

function SunTime:calculateTimes()
    self.rise = self:calculateTimeIter(self.eod, 6)
    self.set = self:calculateTimeIter(self.eod, 18)

    self.rise_civil = self:calculateTimeIter(self.civil, 6)
    self.set_civil = self:calculateTimeIter(self.civil, 18)
    self.rise_nautic = self:calculateTimeIter(self.nautic, 6)
    self.set_nautic = self:calculateTimeIter(self.nautic, 18)
    self.rise_astronomic = self:calculateTimeIter(self.astronomic, 6)
    self.set_astronomic = self:calculateTimeIter(self.astronomic, 18)

    self.noon = self:calculateTimeIter(0, 12)
    self.midnight = self.noon - 12

    self.times = {}
    self.times[1]  = self.midnight
    self.times[2]  = self.rise_astronomic
    self.times[3]  = self.rise_nautic
    self.times[4]  = self.rise_civil
    self.times[5]  = self.rise
    self.times[6]  = self.noon
    self.times[7]  = self.set
    self.times[8]  = self.set_civil
    self.times[9]  = self.set_nautic
    self.times[10] = self.set_astronomic
    self.times[11] = self.noon + 12
end

-- get time in seconds (either actual time in hours or date struct)
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
