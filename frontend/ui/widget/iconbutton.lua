require "ui/widget/container"
require "ui/widget/image"


--[[
Button with a big icon image! Designed for touch device
--]]
IconButton = InputContainer:new{
	icon_file = "resources/info-confirm.png",
	dimen = nil,
	-- parent is used for UIManager:setDirty
	parent = nil,
	callback = function() end,
}

function IconButton:init()
	self.image = ImageWidget:new{
		file = self.icon_file
	}

	self.parent = self.parent or self
	self.dimen = self.image:getSize()

	self:initGesListener()

	self[1] = self.image
end

function IconButton:initGesListener()
	self.ges_events = {
		TapClickButton = {
			GestureRange:new{
				ges = "tap",
				range = self.dimen,
			}
		},
	}
end

function IconButton:onTapClickButton()
	self.image.invert = true
	UIManager:setDirty(self.parent, "partial")
	UIManager:scheduleIn(0.5, function()
		self.image.invert = false
		UIManager:setDirty(self.parent, "partial")
	end)
	self.callback()
end

function IconButton:onSetDimensions(new_dimen)
	self.dimen = new_dimen
end

