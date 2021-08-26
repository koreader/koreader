
-- usage
-- SunTime:setPosition()
-- SunTime:setSimple() or SunTime:setAdvanced()
-- SunTime:setDate()
-- SunTime:calculate(height)  height==Rad(0°)-> Midday
-- SunTime:calculateTimes()

-- use values

local toRad = math.pi/180
local toDeg = 1/toRad

local function Rad(x)
    return x*toRad
end

local SunTime = {}

function SunTime:frac(x)
    return x - math.floor(x)
end

SunTime.astronomic = Rad(90 + 18)
SunTime.nautic =  Rad(90 + 12)
SunTime.civil = Rad(90 + 6)
SunTime.eod = Rad(90 + 50/60) -- end of day

-- simple 'Equation of time' good for dates between 2008-2027
-- errors for latitude 20° are within 1min
--                     47° are within 1min 30sec
--                     65° are within 5min
-- https://www.astronomie.info/zeitgleichung/#Auf-_und_Untergang (German)
function SunTime:getZglSimple()
    local T = self.date.yday
    print("-------------- simple")
    return -0.171 * math.sin(0.0337 * T + 0.465)  - 0.1299 * math.sin(0.01787 * T - 0.168)
end

-- more advanced 'Equation of time' goot for dates between 1800-2200
-- errors are better than with the simple method
-- https://de.wikipedia.org/wiki/Zeitgleichung (German) and
-- more infos on http://www.hlmths.de/Scilab/Zeitgleichung.pdf (German)
function SunTime:getZglAdvanced()
    print("-----------...advanced")
    local e = self.num_ex
    local e2 = e*e
    local e3 = e2*e
    local C = (2*e-e3/4)*math.sin(self.M) + 5/4*e2*math.sin(2*self.M) + 13/12*e3*math.sin(3*self.M) -- rad

    local lamb = self.L + C
    local tanL = math.tan(self.L)
    local tanLamb = math.tan(lamb)
    local cosEps = math.cos(self.epsilon)

    local zgl = math.atan( (tanL - tanLamb*cosEps) / (1 + tanL*tanLamb*cosEps) )
    return zgl*toDeg/15 --  to hours *4/60
end

-- set current date or year/month/day daylightsaving hh/mm/ss
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
    end

    -- use cached results
    if self.olddate and self.oldDate.day == self.date.day and
        self.oldDate.month == self.date.month and
        self.oldDate.year == self.date.year then
        return
    end

    self:initVars()

    if not self.getZgl then
        self.getZgl = self.getZglAdvanced
    end
    self.zgl = self:getZgl()
    print("Zgl: (min)", self.zgl*60 )
end

function SunTime:setPosition(name, latitude, longitude, time_zone)
    if self.name == name and self.pos.latitude == latitude and self.pos.longitude == longitude
        and self.time_zone == time_zone then
        return
    end

    if self.date then self.date.year = -1 end --invalidate cache
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
    local leap = math.floor(delta/4) + 1 -- +1 for 2000, which was a leap year
    self.days_since_2000 = delta * 365 + leap + self.date.yday + self.date.hour/24 + self.date.min/24/60 -- WMO No.8
    return self.days_since_2000
end

-- more accurate parameters of earth orbit from_
-- Title: Numerical expressions for precession formulae and mean elements for the Moon and the planets
-- Authors: Simon, J. L., Bretagnon, P., Chapront, J., Chapront-Touze, M., Francou, G., & Laskar, J., ,
-- Journal: Astronomy and Astrophysics (ISSN 0004-6361), vol. 282, no. 2, p. 663-683
-- Bibliographic Code: 1994A&A...282..663S
function SunTime:initVars()
    self:daysSince2000()
    local T = self.days_since_2000/36525
    local T2 = T * T
    local T3 = T2 * T
    local T4 = T3 * T
    local T5 = T4 * T
    local T6 = T5 * T
--    self.num_ex = 0.016709 - 0.000042 * T
--    self.num_ex = 0.0167086342 - 0.000042 * T
    self.num_ex = 0.0167086342      - 00.004203654 * T
                - 000.00126734 * T2 + 0000.0001444 * T3
                - 00000.000002 * T4 + 000000.00003 * T5
--    self.epsilon = (23 + 26/60 + 21/3600 - 46.82/3600 * T) * toRad
    local epsilon = 23 + 26/60 + 21.412/3600 - 46.80927/3600 * T
        - 0.000152/3600 * T2   + 0.00019989/3600 * T3
        - 0.00000051/3600 * T4 - 0.00000025/3600 * T5 --°
    self.epsilon = epsilon * toRad
--    local L = (280.4656 + 36000.7690 * T ) --°
    local L = 280.46645683 + 12959774228.3429/3600 * T - 204.411/3600 * T2 - 5.23/3600 * T3 --°
    self.L = (L - math.floor(L/360)*360) * toRad
--    local M = L - (282.9400 + 1.7192 * T) --°
    local M = L - (282.93734808      + 1.7194598028 * T
                  + 004.5688325 * T2 - 0000.017680 * T3
                  - 00000.33583 * T5 + 000000.0828 * T5
                  + 0000000.056 * T6) --°

    self.M = (M - math.floor(M/360)*360) * toRad
end
--------------------------

function SunTime:getTimeDiff(height)
--    local decl = 0.4095 * math.sin(0.016906 * (self.date.yday - 80.086)) --Deklination nach astronomie.info
--    local decl = 0.40954 * math.sin(0.0172 * (self.date.yday-79.349740)) --Deklination nach Brodbeck (2001)

    local x = (36000/36525 * (self.date.yday+.5) - 2.72)*toRad
    local decl = math.asin(0.397748 * math.sin( x + (1.92*math.sin(x) -77.51)*toRad)) --Deklination nach

    local val = (math.cos(height) - math.sin(self.pos.latitude)*math.sin(decl)) / (math.cos(self.pos.latitude)*math.cos(decl))
    if math.abs(val) > 1 then
        return
    end
    return 12/math.pi * math.acos(val)
end

-- get time for a certain height
-- result rise and set times
--        nil and nil sun does not reach the height
function SunTime:calculateTime(height)
    local dst = self.date.isdst and 1 or 0
    local timeDiff = self:getTimeDiff(height)
    if not timeDiff then
        return nil, nil
    end
    local local_correction = self.time_zone - self.pos.longitude*12/math.pi + dst - self.zgl

    local rise = 12 - timeDiff + local_correction
    local set  = 12 + timeDiff + local_correction
    return rise, set
end

function SunTime:calculateTimes()
    self.rise_astronomic, self.set_astronomic = self:calculateTime(self.astronomic)
    self.rise_nautic, self.set_nautic         = self:calculateTime(self.nautic)
    self.rise_civil, self.set_civil           = self:calculateTime(self.civil)
    self.rise, self.set                       = self:calculateTime(self.eod)
    self.noon = (self.rise + self.set)/2
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
    self.times[11] = self.midnight + 24
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
