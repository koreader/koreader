local KindleFrontLight = require("ui/device/kindlefrontlight")
local KoboFrontLight = require("ui/device/kobofrontlight")
local BaseFrontLight = require("ui/device/basefrontlight")
local Screen = require("ui/device/screen")
-- util
-- lfs

local Device = {
	screen_saver_mode = false,
	charging_mode = false,
	survive_screen_saver = false,
	touch_dev = nil,
	model = nil,
	firmware_rev = nil,
	frontlight = nil,
	screen = Screen
}

Screen.device = Device

function Device:getModel()
	if self.model then return self.model end
	if util.isEmulated() then
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
	local model = self:getModel()
	return (model == "KindlePaperWhite") or (model == "KindleTouch") or self:isKobo()
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
		self.screen:saveCurrentBB()
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
		self.screen:restoreFromSavedBB()
		self.screen:refresh(0)
		self.survive_screen_saver = true
	end
	self.screen_saver_mode = false
end

function Device:prepareSuspend() -- currently only used for kobo devices
	local fl = self:getFrontlight()
	if fl ~= nil then
		fl.fl:sleep()
	end
	self.screen:refresh(0)
	self.screen_saver_mode = true
end

function Device:Suspend() -- currently only used for kobo devices
	os.execute("./kobo_suspend.sh")
end

function Device:Resume() -- currently only used for kobo devices
	os.execute("echo 0 > /sys/power/state-extended")
	self.screen:refresh(0)
	local fl = self:getFrontlight()
	if fl ~= nil then
		fl.fl:restore()
	end
	self.screen_saver_mode = false
end

function Device:usbPlugIn()
	--os.execute("echo 'usb in' >> /mnt/us/event_test.txt")
	if self.charging_mode == false and self.screen_saver_mode == false then
		self.screen:saveCurrentBB()
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
		self.screen:restoreFromSavedBB()
		self.screen:refresh(0)
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
		else -- emulated FrontLight
			self.frontlight = BaseFrontLight
		end
		self.frontlight:init()
	end
	return self.frontlight
end

return Device
