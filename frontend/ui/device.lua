Device = {
	screen_saver_mode = false,
	charging_mode = false,
}

function Device:getModel()
	local std_out = io.popen("grep 'MX' /proc/cpuinfo | cut -d':' -f2 | awk {'print $2'}", "r")
	local cpu_mod = std_out:read()	
	if not cpu_mod then
		local ret = os.execute("grep 'Hardware : Mario Platform' /proc/cpuinfo", "r")
		if ret ~= 0 then
			return nil
		else
			return "KindleDXG"
		end
	end
	if cpu_mod == "MX50" then
		local f = lfs.attributes("/sys/devices/system/fl_tps6116x/fl_tps6116x0/fl_intensity")
		if f then
			return "KindlePaperWhite"
		else
			return "Kindle4"
		end
	elseif cpu_mod == "MX35" then
		-- check if we are running on Kindle 3 (additional volume input)
		return "Kindle3"
	elseif cpu_mod == "MX3" then
		return "Kindle2"
	else
		return nil
	end
end

function Device:isKindle4()
	re_val = os.execute("cat /proc/cpuinfo | grep MX50")
	if re_val == 0 then
		return true
	else
		return false
	end
end

function Device:isKindle3()
	re_val = os.execute("cat /proc/cpuinfo | grep MX35")
	if re_val == 0 then
		return true
	else
		return false
	end
end

function Device:isKindle2()
	re_val = os.execute("cat /proc/cpuinfo | grep MX3")
	if re_val == 0 then
		return true
	else
		return false
	end
end

function Device:isTouchDevice()
	local model = self:getModel()
	return (model == "Kindle4") or (model == "KindlePaperWhite") or util.isEmulated()
end

function Device:intoScreenSaver()
	--os.execute("echo 'screensaver in' >> /mnt/us/event_test.txt")
	if self.charging_mode == false and self.screen_saver_mode == false then
		Screen:saveCurrentBB()
		msg = InfoMessage:new{"Going into screensaver... "}
		UIManager:show(msg)

		Screen.kpv_rotation_mode = Screen.cur_rotation_mode
		Screen.fb:setOrientation(Screen.native_rotation_mode)
		util.sleep(1)
		os.execute("killall -cont cvm")
		self.screen_saver_mode = true

		UIManager:close(msg)
	end
end

function Device:outofScreenSaver()
	--os.execute("echo 'screensaver out' >> /mnt/us/event_test.txt")
	if self.screen_saver_mode == true and self.charging_mode == false then
		util.usleep(1500000)
		os.execute("killall -stop cvm")
		Screen.fb:setOrientation(Screen.kpv_rotation_mode)
		Screen:restoreFromSavedBB()
		Screen.fb:refresh(0)
	end
	self.screen_saver_mode = false
end

function Device:usbPlugIn()
	--os.execute("echo 'usb in' >> /mnt/us/event_test.txt")
	if self.charging_mode == false and self.screen_saver_mode == false then
		Screen:saveCurrentBB()
		Screen.kpv_rotation_mode = Screen.cur_rotation_mode
		Screen.fb:setOrientation(Screen.native_rotation_mode)
		msg = InfoMessage:new{"Going into USB mode... "}
		UIManager:show(msg)
		util.sleep(1)
		UIManager:close(msg)
		os.execute("killall -cont cvm")
	end
	self.charging_mode = true
end

function Device:usbPlugOut()
	--os.execute("echo 'usb out' >> /mnt/us/event_test.txt")
	if self.charging_mode == true and self.screen_saver_mode == false then
		util.usleep(1500000)
		os.execute("killall -stop cvm")
		Screen.fb:setOrientation(Screen.kpv_rotation_mode)
		Screen:restoreFromSavedBB()
		Screen.fb:refresh(0)
	end

	--@TODO signal filemanager for file changes  13.06 2012 (houqp)
	--FileChooser:setPath(FileChooser.path)
	--FileChooser.pagedirty = true
	
	self.charging_mode = false
end
