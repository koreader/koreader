-- return the current battery level
function BatteryLevel()
	local p = io.popen("gasgauge-info -s 2> /dev/null", "r") -- io.popen() _never_ fails!
	local battery = p:read("*a") or "?"
	if battery == "" then battery = "?" end
	p:close()
	return string.gsub(battery, "[\n\r]+", "")
end

-- log battery level in "batlog.txt" file, blevent can be any string
function logBatteryLevel(blevent)
	local file = io.open("batlog.txt", "a+")
	if file then
		if file:seek("end") == 0 then -- write the header only once
			file:write(string.format("DATE\t\tTIME\t\tBATTERY\tEVENT\n"))
		end
		file:write(string.format("%s\t%s\t%s\t%s\n",
			os.date("%d-%b-%y"), os.date("%T"),
			BatteryLevel(), blevent or "RUNNING"))
		file:close()
	end
end
