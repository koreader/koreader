Device = {
	screen_saver_mode = false,
	charging_mode = false,
	survive_screen_saver = false,
	touch_dev = nil,
	model = nil,
}

function Device:getModel()
	if self.model then return self.model end
	if util.isEmulated()==1 then
		self.model = "Emulator"
		return self.model
	end
	local std_out = io.popen("grep 'MX' /proc/cpuinfo | cut -d':' -f2 | awk {'print $2'}", "r")
	local cpu_mod = std_out:read()
	if not cpu_mod then
		local ret = os.execute("grep 'Hardware : Mario Platform' /proc/cpuinfo", "r")
		if ret ~= 0 then
			self.model = nil
		else
			self.model = "KindleDXG"
		end
	end
	if cpu_mod == "MX50" then
		-- for KPW
		local pw_test_fd = lfs.attributes("/sys/devices/system/fl_tps6116x/fl_tps6116x0/fl_intensity")
		-- for Kobo
		local kg_test_fd = lfs.attributes("/bin/kobo_config.sh")
		-- for KT
		local kt_test_fd = lfs.attributes("/sys/devices/platform/whitney-button")
		-- another special file for KT is Neonode zForce touchscreen:
		-- /sys/devices/platform/zforce.0/
		if pw_test_fd then
			self.model = "KindlePaperWhite"
		elseif kg_test_fd then
			local std_out = io.popen("/bin/kobo_config.sh", "r")
			local codename = std_out:read()
			self.model = "Kobo_" .. codename
		elseif kt_test_fd then
			self.model = "KindleTouch"
		else
			self.model = "Kindle4"
		end
	elseif cpu_mod == "MX35" then
		-- check if we are running on Kindle 3 (additional volume input)
		self.model = "Kindle3"
	elseif cpu_mod == "MX3" then
		self.model = "Kindle2"
	else
		self.model = nil
	end
	return self.model
end

function Device:isKindle4()
	return (self:getModel() == "Kindle4")
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

function Device:isKobo()
	if not self.model then
		self.model = self:getModel()
	end
	re_val = string.find(self.model,"Kobo_")
	if re_val == 1 then
		return true
	else
		return false
	end
end

function Device:hasNoKeyboard()
	if not self.model then
		self.model = self:getModel()
	end
	return self:isTouchDevice() or (self.model == "Kindle4")
end

function Device:hasKeyboard()
	return not self:hasNoKeyboard()
end

function Device:isTouchDevice()
	if not self.model then
		self.model = self:getModel()
	end
	return (self.model == "KindlePaperWhite") or (self.model == "KindleTouch") or self:isKobo() or util.isEmulated()
end

function Device:setTouchInputDev(dev)
	self.touch_dev = dev
end

function Device:getTouchInputDev()
	return self.touch_dev
end

function Device:intoScreenSaver()
	--os.execute("echo 'screensaver in' >> /mnt/us/event_test.txt")
	if self.charging_mode == false and self.screen_saver_mode == false then
		Screen:saveCurrentBB()
		--UIManager:show(InfoMessage:new{
			--text = "Going into screensaver... ",
			--timeout = 2,
		--})
		--util.sleep(1)
		--os.execute("killall -cont cvm")
		self.screen_saver_mode = true
	end
end

function Device:outofScreenSaver()
	--os.execute("echo 'screensaver out' >> /mnt/us/event_test.txt")
	if self.screen_saver_mode == true and self.charging_mode == false then
		-- wait for native system update screen before we recover saved
		-- Blitbuffer.
		util.usleep(1500000)
		--os.execute("killall -stop cvm")
		Screen:restoreFromSavedBB()
		Screen:refresh(0)
		self.survive_screen_saver = true
	end
	self.screen_saver_mode = false
end

function Device:usbPlugIn()
	--os.execute("echo 'usb in' >> /mnt/us/event_test.txt")
	if self.charging_mode == false and self.screen_saver_mode == false then
		Screen:saveCurrentBB()
		--UIManager:show(InfoMessage:new{
			--text = "Going into USB mode... ",
			--timeout = 2,
		--})
		--util.sleep(1)
		--os.execute("killall -cont cvm")
	end
	self.charging_mode = true
end

function Device:usbPlugOut()
	--os.execute("echo 'usb out' >> /mnt/us/event_test.txt")
	if self.charging_mode == true and self.screen_saver_mode == false then
		--util.usleep(1500000)
		--os.execute("killall -stop cvm")
		Screen:restoreFromSavedBB()
		Screen:refresh(0)
	end

	--@TODO signal filemanager for file changes  13.06 2012 (houqp)
	self.charging_mode = false
end
