require "ui/widget/container"
require "ui/widget/inputdialog"
require "ui/device"

ReaderFrontLight = InputContainer:new{
	fldial_menu_title = ("Frontlight Settings"),
	fl_dialog_title = ("Frontlight Level"),
	steps = {0,1,2,3,4,5,6,7,8,9,10},
	intensity = nil,
	fl = nil,
}

function ReaderFrontLight:init()
	local dev_mod = Device:getModel()
	if dev_mod == "KindlePaperWhite" then
		require "liblipclua"
		self.lipc_handle = lipc.init("com.github.koreader")
		if self.lipc_handle then
			self.intensity = self.lipc_handle:get_int_property("com.lab126.powerd", "flIntensity")
		end
		self.ges_events = {
			Adjust = {
				GestureRange:new{
					ges = "two_finger_pan",
					range = Geom:new{
						x = 0, y = 0,
						w = Screen:getWidth(),
						h = Screen:getHeight(),
					},
					rate = 2.0,
				}
			},
		}
	end
	if Device:isKobo() then
		self.fl = kobolight.open()
		self.intensity = G_reader_settings:readSetting("frontlight_intensity")
		if not self.intensity then
			self.intensity = 20
		end
		self:setIntensity(self.intensity, "Set intensity")
	end
end

function ReaderFrontLight:onAdjust(arg, ges)
	if self.lipc_handle and self.intensity ~=nil then
		local rel_proportion = ges.distance / Screen:getWidth()
		local delta_int = self.steps[math.ceil(#self.steps*rel_proportion)] or self.steps[#self.steps]
		local msg = ""
		if ges.direction == "north" then
			msg = _("Increase front light intensity to ")
			self.intensity = self.intensity + delta_int
			self:setIntensity(self.intensity, msg)
		elseif ges.direction == "south" then
			msg = _("Decrease front light intensity to ")
			self.intensity = self.intensity - delta_int
			self:setIntensity(self.intensity, msg)
		end
	end
	return true
end

function ReaderFrontLight:setIntensity(intensity, msg)
	if self.lipc_handle then
		intensity = intensity < 0 and 0 or intensity
		intensity = intensity > 24 and 24 or intensity
		self.intensity = intensity
		self.lipc_handle:set_int_property("com.lab126.powerd", "flIntensity", intensity)
		UIManager:show(Notification:new{
			text = msg..intensity,
			timeout = 1
		})
	end
	if Device:isKobo() then
		intensity = intensity < 1 and 1 or intensity
		intensity = intensity > 100 and 100 or intensity
		if self.fl == nil then
			ReaderFrontLight:init()
		end
		if self.fl ~= nil then
			self.fl:setBrightness(intensity)
			self.intensity = intensity
		end
	end
	return true
end

function ReaderFrontLight:toggle()
	if Device:isKobo() then
		if self.fl == nil then
			ReaderFrontLight:init()
		end
		if self.fl ~= nil then
			self.fl:toggle()
		end
	end
	return true
end

function ReaderFrontLight:addToMainMenu(tab_item_table)
	-- insert fldial command to main reader menu
	table.insert(tab_item_table.main, {
		text = self.fldial_menu_title,
		callback = function()
			self:onShowFlDialog()
		end,
	})
end

function ReaderFrontLight:onShowFlDialog()
	DEBUG("show fldial dialog")
	self.fl_dialog = InputDialog:new{
		title = self.fl_dialog_title,
		input_hint = "(1 - 100)",
		buttons = {
			{
				{
					text = _("Apply"),
					enabled = true,
					callback = function()
						self:fldialIntensity()
					end,
				},
				{
					text = _("OK"),
					enabled = true,
					callback = function()
						self:fldialIntensity()
						self:close()
					end,
				},

			},
		},
		input_type = "number",
		width = Screen:getWidth() * 0.8,
		height = Screen:getHeight() * 0.2,
	}
	self.fl_dialog:onShowKeyboard()
	UIManager:show(self.fl_dialog)
end

function ReaderFrontLight:close()
	self.fl_dialog:onClose()
	G_reader_settings:saveSetting("frontlight_intensity", self.intensity)
	UIManager:close(self.fl_dialog)
end

function ReaderFrontLight:fldialIntensity()
	local number = tonumber(self.fl_dialog:getInputText())
	if number then
		self:setIntensity(number, "Set intensity")
	end
	return true
end
