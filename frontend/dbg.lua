require "settings" -- for dump method

Dbg = {
	is_on = false,
	ev_log = nil,
}

function Dbg:turnOn()
	self.is_on = true

	-- create or clear ev log file
	os.execute("echo > ev.log")
	self.ev_log = io.open("ev.log", "w")
end

function Dbg:logEv(ev)
	local log = ev.type.."|"..ev.code.."|"
				..ev.value.."|"..ev.time.sec.."|"..ev.time.usec.."\n"
	self.ev_log:write(log)
	self.ev_log:flush()
end

function DEBUG(...)
	LvDEBUG(math.huge, ...)
end

function LvDEBUG(lv, ...)
	local line = ""
	for i,v in ipairs({...}) do
		if type(v) == "table" then
			line = line .. " " .. dump(v, lv)
		else
			line = line .. " " .. tostring(v)
		end
	end
	print("#"..line)
end

