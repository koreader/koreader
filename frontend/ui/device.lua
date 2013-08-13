Device = {
	screen_saver_mode = false,
	charging_mode = false,
	survive_screen_saver = false,
	touch_dev = nil,
	model = nil,
	firmware_rev = nil,
	frontlight = nil,
}

BaseFrontLight = {}

KindleFrontLight = {
	min = 0, max = 24,
	kpw_fl = "/sys/devices/system/fl_tps6116x/fl_tps6116x0/fl_intensity",
	intensity = nil,
	lipc_handle = nil,
}

KoboFrontLight = {
	min = 1, max = 100,
	intensity = 20,
	restore_settings = true,
	fl = nil,
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
		local pw_test_fd = lfs.attributes(KindleFrontLight.kpw_fl)
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
			local version_file = io.open("/mnt/onboard/.kobo/version", "r")
			self.firmware_rev = string.sub(version_file:read(),24,28)
			version_file:close()
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

function Device:getFirmVer()
	if not self.model then self:getModel() end
	return self.firmware_rev
end

function Device:isKindle4()
	return (self:getModel() == "Kindle4")
end

function Device:isKindle3()
	return (self:getModel() == "Kindle3")
end

function Device:isKindle2()
	return (self:getModel() == "Kindle2")
end

function Device:isKobo()
	return string.find(self:getModel(),"Kobo_") == 1
end

function Device:hasNoKeyboard()
	return self:isTouchDevice() or (self:getModel() == "Kindle4")
end

function Device:hasKeyboard()
	return not self:hasNoKeyboard()
end

function Device:isTouchDevice()
	local model = self:getModel()
	return (model == "KindlePaperWhite") or (model == "KindleTouch") or self:isKobo() or util.isEmulated()
end

function Device:hasFrontlight()
	local model = self:getModel()
	return (model == "KindlePaperWhite") or (model == "Kobo_dragon") or (model == "Kobo_kraken") or (model == "Kobo_phoenix") or util.isEmulated()
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

function Device:getFrontlight()
	if self.frontlight ~= nil then
		return self.frontlight
	elseif self:hasFrontlight() then
		if self:getModel() == "KindlePaperWhite" then
			self.frontlight = KindleFrontLight
		elseif self:isKobo() then
			self.frontlight = KoboFrontLight
		end
		if self.frontlight ~= nil then
			self.frontlight:init()
		end
	end
	return self.frontlight
end

function BaseFrontLight:intensityCheckBounds(intensity)
	intensity = intensity < self.min and self.min or intensity
	intensity = intensity > self.max and self.max or intensity
	self.intensity = intensity
end

function KindleFrontLight:init()
	require "liblipclua"
	self.lipc_handle = lipc.init("com.github.koreader")
	if self.lipc_handle then
		self.intensity = self.lipc_handle:get_int_property("com.lab126.powerd", "flIntensity")
	end
end

function KindleFrontLight:toggle()
	local f =  io.open(self.kpw_fl, "r")
	local sysint = tonumber(f:read("*all"):match("%d+"))
	f:close()
	if sysint == 0 then
		self:setIntensity(self.intensity)
	else
		os.execute("echo -n 0 > " .. self.kpw_fl)
	end
end

KindleFrontLight.intensityCheckBounds = BaseFrontLight.intensityCheckBounds

function KindleFrontLight:setIntensity(intensity)
	if self.lipc_handle ~= nil then
		self:intensityCheckBounds(intensity)
		self.lipc_handle:set_int_property("com.lab126.powerd", "flIntensity", self.intensity)
	end
end

function KoboFrontLight:init()
	self.fl = kobolight.open()
end

function KoboFrontLight:toggle()
	if self.fl ~= nil then
		self.fl:toggle()
	end
end

KoboFrontLight.intensityCheckBounds = BaseFrontLight.intensityCheckBounds

function KoboFrontLight:setIntensity(intensity)
	if self.fl ~= nil then
		self:intensityCheckBounds(intensity)
		self.fl:setBrightness(self.intensity)
	end
end
