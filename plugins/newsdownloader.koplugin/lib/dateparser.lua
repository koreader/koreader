local difftime, time, date = os.difftime, os.time, os.date
local format = string.format
local tremove, tinsert = table.remove, table.insert
local pcall, pairs, ipairs, tostring, tonumber, type, setmetatable = pcall, pairs, ipairs, tostring, tonumber, type, setmetatable

local dateparser={}

--we shall use the host OS's time conversion facilities. Dealing with all those leap seconds by hand can be such a bore.
local unix_timestamp
do
	local now = time()
	local local_UTC_offset_sec = difftime(time(date("!*t", now)), time(date("*t", now)))
	unix_timestamp = function(t, offset_sec)
		local success, improper_time = pcall(time, t)
		if not success or not improper_time then return nil, "invalid date. os.time says: " .. (improper_time or "nothing") end
		return improper_time - local_UTC_offset_sec - offset_sec
	end
end

local formats = {} -- format names
local format_func = setmetatable({}, {__mode='v'})  --format functions

---register a date format parsing function
function dateparser.register_format(format_name, format_function)
	if type(format_name)~="string" or type(format_function)~='function' then return nil, "improper arguments, can't register format handler" end

	local found
	for i, f in ipairs(format_func) do --for ordering
		if f==format_function then
			found=true
			break
		end
	end
	if not found then
		tinsert(format_func, format_function)
	end
	formats[format_name] = format_function
	return true
end

---register a date format parsing function
function dateparser.unregister_format(format_name)
	if type(format_name)~="string" then return nil, "format name must be a string" end
	formats[format_name]=nil
end

---return the function responsible for handling format_name date strings
function dateparser.get_format_function(format_name)
	return formats[format_name] or nil, ("format %s not registered"):format(format_name)
end

---try to parse date string
--@param str date string
--@param date_format optional date format name, if known
--@return unix timestamp if str can be parsed; nil, error otherwise.
function dateparser.parse(str, date_format)
	local success, res, err
	if date_format then 
		if not formats[date_format] then return 'unknown date format: ' .. tostring(date_format) end
		success, res = pcall(formats[date_format], str)
	else
		for i, func in ipairs(format_func) do
			success, res = pcall(func, str)
			if success and res then return res end
		end
	end
	return success and res
end

dateparser.register_format('W3CDTF', function(rest)
	
	local year, day_of_year, month, day, week
	local hour, minute, second, second_fraction, offset_hours
	
	local alt_rest
	
	year,  rest = rest:match("^(%d%d%d%d)%-?(.*)$")

	day_of_year, alt_rest = rest:match("^(%d%d%d)%-?(.*)$")

	if day_of_year then rest=alt_rest end

	month, rest = rest:match("^(%d%d)%-?(.*)$")

	day,   rest = rest:match("^(%d%d)(.*)$")
	if #rest>0 then
		rest = rest:match("^T(.*)$")
		hour,   rest = rest:match("^([0-2][0-9]):?(.*)$")
		minute, rest = rest:match("^([0-6][0-9]):?(.*)$")
		second, rest = rest:match("^([0-6][0-9])(.*)$")
		second_fraction, alt_rest = rest:match("^%.(%d+)(.*)$")
		if second_fraction then 
			rest=alt_rest 
		end
		if rest=="Z" then 
			rest=""
			offset_hours=0
		else
			local sign, offset_h, offset_m
			sign, offset_h, rest = rest:match("^([+-])(%d%d)%:?(.*)$")
			local offset_m, alt_rest = rest:match("^(%d%d)(.*)$")
			if offset_m then rest=alt_rest end
			offset_hours = tonumber(sign .. offset_h) + (tonumber(offset_m) or 0)/60
		end
		if #rest>0 then return nil end
	end
	
	year = tonumber(year)
	local d = {
		year = year and (year > 100 and year or (year < 50 and (year + 2000) or (year + 1900))),
		month = tonumber(month) or 1,
		day = tonumber(day) or 1,
		hour = tonumber(hour) or 0,
		min = tonumber(minute) or 0,
		sec = tonumber(second) or 0,
		isdst = false
	}
	local t = unix_timestamp(d, (offset_hours or 0) * 3600)
	if second_fraction then
		return t + tonumber("0."..second_fraction)
	else
		return t
	end
end)


do
	local tz_table = { --taken from http://www.timeanddate.com/library/abbreviations/timezones/
		A = 1, 	B = 2, C = 3, D = 4,  E=5, F = 6,	G = 7,	H = 8,	I = 9,	
		K = 10,	L = 11,	M = 12, N = -1,	O = -2,	P = -3, Q = -4,	R = -5,	
		S = -6,	T = -7,	U = -8,	V = -9,	W = -10, X = -11, Y = -12, 
		Z = 0,
		
		EST = -5, EDT = -4, CST = -6, CDT = -5, 
		MST = -7, MDT = -6, PST = -8, PDT = -7,	

		GMT = 0, UT = 0, UTC = 0
	}
	
	local month_val = {Jan=1, Feb=2, Mar=3, Apr=4, May=5, Jun=6, Jul=7, Aug=8, Sep=9, Oct=10, Nov=11, Dec=12}
	
	dateparser.register_format('RFC2822', function(rest)

		local year, month, day, day_of_year, week_of_year, weekday
		local hour, minute, second, second_fraction, offset_hours
		
		local alt_rest
		
		weekday, alt_rest = rest:match("^(%w%w%w),%s+(.*)$")
		if weekday then rest=alt_rest end
		day, rest=rest:match("^(%d%d?)%s+(.*)$")
		month, rest=rest:match("^(%w%w%w)%s+(.*)$")
		month = month_val[month]
		year, rest = rest:match("^(%d%d%d?%d?)%s+(.*)$")
		hour, rest = rest:match("^(%d%d?):(.*)$")
		minute, rest = rest:match("^(%d%d?)(.*)$")
		second, alt_rest = rest:match("^:(%d%d)(.*)$")
		if second then rest = alt_rest end
		local tz, offset_sign, offset_h, offset_m
		tz, alt_rest = rest:match("^%s+(%u+)(.*)$")
		if tz then
			rest = alt_rest
			offset_hours = tz_table[tz]
		else
			offset_sign, offset_h, offset_m, rest = rest:match("^%s+([+-])(%d%d)(%d%d)%s*(.*)$")
			offset_hours = tonumber(offset_sign .. offset_h) + (tonumber(offset_m) or 0)/60
		end
		
		if #rest>0 or not (year and day and month and hour and minute) then 
			return nil 
		end
		
		year = tonumber(year)
		local d = {
			year = year and ((year > 100) and year or (year < 50 and (year + 2000) or (year + 1900))),
			month = month,
			day = tonumber(day),
			
			hour= tonumber(hour) or 0,
			min = tonumber(minute) or 0,
			sec = tonumber(second) or 0,
			isdst  = false
		} 
		return unix_timestamp(d, offset_hours * 3600) 
	end)
end

dateparser.register_format('RFC822', formats.RFC2822) --2822 supercedes 822, but is not a strict superset. For our intents and purposes though, it's perfectly good enough
dateparser.register_format('RFC3339', formats.W3CDTF) --RFC3339 is a subset of W3CDTF


return dateparser