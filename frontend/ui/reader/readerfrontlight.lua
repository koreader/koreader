local InputContainer = require("ui/widget/container/inputcontainer")
local Geom = require("ui/geometry")
local Screen = require("ui/screen")
local Device = require("ui/device")
local GestureRange = require("ui/gesturerange")
local InputDialog = require("ui/widget/inputdialog")
local UIManager = require("ui/uimanager")
local Notification = require("ui/widget/notification")
local _ = require("gettext")

local ReaderFrontLight = InputContainer:new{
	steps = {0,1,2,3,4,5,6,7,8,9,10},
}

function ReaderFrontLight:init()
	if Device:isTouchDevice() then
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
		self.ui.menu:registerToMainMenu(self)
	end
end

function ReaderFrontLight:onAdjust(arg, ges)
	local powerd = Device:getPowerDevice()
	if powerd.flIntensity ~= nil then
		local rel_proportion = ges.distance / Screen:getWidth()
		local delta_int = self.steps[math.ceil(#self.steps*rel_proportion)] or self.steps[#self.steps]
		local msg = nil
		if ges.direction == "north" then
			msg = _("Increase front light intensity to ")
			powerd:setIntensity(powerd.flIntensity + delta_int)
		elseif ges.direction == "south" then
			msg = _("Decrease front light intensity to ")
			powerd:setIntensity(powerd.flIntensity - delta_int)
		end
		if msg ~= nil then
			UIManager:show(Notification:new{
				text = msg..powerd.flIntensity,
				timeout = 1
			})
		end
	end
	return true
end

function ReaderFrontLight:addToMainMenu(tab_item_table)
	-- insert fldial command to main reader menu
	table.insert(tab_item_table.main, {
		text = _("Frontlight settings"),
		callback = function()
			self:onShowFlDialog()
		end,
	})
end

function ReaderFrontLight:onShowFlDialog()
	local powerd = Device:getPowerDevice()
	self.fl_dialog = InputDialog:new{
		title = _("Frontlight Level"),
		input_hint = ("(%d - %d)"):format(powerd.fl_min, powerd.fl_max),
		buttons = {
			{
				{
					text = _("Toggle"),
					enabled = true,
					callback = function()
						self.fl_dialog.input:setText("")
						powerd:toggleFrontlight()
					end,
				},
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
	G_reader_settings:saveSetting("frontlight_intensity", Device:getPowerDevice().flIntensity)
	UIManager:close(self.fl_dialog)
end

function ReaderFrontLight:fldialIntensity()
	local number = tonumber(self.fl_dialog:getInputText())
	if number ~= nil then
		Device:getPowerDevice():setIntensity(number)
	end
end

return ReaderFrontLight
