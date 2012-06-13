function util.isKindle4()
	re_val = os.execute("cat /proc/cpuinfo | grep MX50")
	if re_val == 0 then
		return true
	else
		return false
	end
end

function util.isKindle3()
	re_val = os.execute("cat /proc/cpuinfo | grep MX35")
	if re_val == 0 then
		return true
	else
		return false
	end
end

function util.isKindle2()
	re_val = os.execute("cat /proc/cpuinfo | grep MX3")
	if re_val == 0 then
		return true
	else
		return false
	end
end
