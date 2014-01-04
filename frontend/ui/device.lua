local KindlePowerD = require("ui/device/kindlepowerd")
local KoboPowerD = require("ui/device/kobopowerd")
local BasePowerD = require("ui/device/basepowerd")
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
	powerd = nil,
	has_no_keyboard = nil,
	is_touch_device = nil,
	has_front_light = nil,
	screen = Screen
}

Screen.device = Device

function Set (list)
	local set = {}
	for _, l in ipairs(list) do set[l] = true end
	return set
end

function Device:getModel()
	if self.model then return self.model end
	if util.isEmulated() then
		self.model = "Emulator"
		return self.model
	end
	self.model = nil
	local kindle_sn = io.open("/proc/usid", "r")
	if kindle_sn then
		local kindle_devcode = string.sub(kindle_sn:read(),3,4)
		kindle_sn:close()
		-- NOTE: Update me when new models come out :)
		local k2_set = Set { "02", "03" }
		local dx_set = Set { "04", "05" }
		local dxg_set = Set { "09" }
		local k3_set = Set { "08", "06", "0A" }
		local k4_set = Set { "0E", "23" }
		local touch_set = Set { "0F", "11", "10", "12" }
		local pw_set = Set { "24", "1B", "1D", "1F", "1C", "20" }
		local pw2_set = Set { "D4", "5A", "D5", "D7", "D8", "F2" }

		if k2_set[kindle_devcode] then
			self.model = "Kindle2"
		elseif dx_set[kindle_devcode] then
			self.model = "Kindle2"
		elseif dxg_set[kindle_devcode] then
			self.model = "Kindle2"
		elseif k3_set[kindle_devcode] then
			self.model = "Kindle3"
		elseif k4_set[kindle_devcode] then
			self.model = "Kindle4"
		elseif touch_set[kindle_devcode] then
			self.model = "KindleTouch"
		elseif pw_set[kindle_devcode] then
			self.model = "KindlePaperWhite"
		elseif pw2_set[kindle_devcode] then
			self.model = "KindlePaperWhite2"
		end
	else
		local kg_test_fd = lfs.attributes("/bin/kobo_config.sh")
		if kg_test_fd then
			local std_out = io.popen("/bin/kobo_config.sh", "r")
			local codename = std_out:read()
			self.model = "Kobo_" .. codename
			local version_file = io.open("/mnt/onboard/.kobo/version", "r")
			self.firmware_rev = string.sub(version_file:read(),24,28)
			version_file:close()
		end
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
	if self.has_no_keyboard ~= nil then return self.has_no_keyboard end
	local model = self:getModel()
	self.has_no_keyboard = (model == "KindlePaperWhite") or (model == "KindlePaperWhite2")
						or (model == "KindleTouch") or self:isKobo()
	return self.has_no_keyboard
end

function Device:hasKeyboard()
	return not self:hasNoKeyboard()
end

function Device:isTouchDevice()
	if self.is_touch_device ~= nil then return self.is_touch_device end
	local model = self:getModel()
	self.is_touch_device = (model == "KindlePaperWhite") or (model == "KindlePaperWhite2")
						or (model == "KindleTouch") or self:isKobo() or util.isEmulated()
	return self.is_touch_device
end

function Device:hasFrontlight()
	if self.has_front_light ~= nil then return self.has_front_light end
	local model = self:getModel()
	self.has_front_light = (model == "KindlePaperWhite") or (model == "KindlePaperWhite2")
						or (model == "Kobo_dragon") or (model == "Kobo_kraken") or (model == "Kobo_phoenix")
						or util.isEmulated()
	return self.has_front_light
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
	local powerd = self:getPowerDevice()
	if powerd ~= nil then
		powerd.fl:sleep()
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
	local powerd = self:getPowerDevice()
	if powerd ~= nil then
		powerd.fl:restore()
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

function Device:getPowerDevice()
	if self.powerd ~= nil then
		return self.powerd
	else
		local model = self:getModel()
		if model == "KindleTouch" or model == "KindlePaperWhite" or model == "KindlePaperWhite2" then
			self.powerd = KindlePowerD:new{model = model}
		elseif self:isKobo() then
			self.powerd = KoboPowerD:new()
		else -- emulated FrontLight
			self.powerd = BasePowerD:new()
		end
	end
	return self.powerd
end

return Device
