require "ui/config"

ReaderConfig = InputContainer:new{
	dimen = Geom:new{
		x = 0, 
		y = 7*Screen:getHeight()/8,
		w = Screen:getWidth(),
		h = Screen:getHeight()/8,
	}
}

function ReaderConfig:init()
	DEBUG("init ReaderConfig.")
	if Device:isTouchDevice() then
		self.ges_events = {
			TapShowConfigMenu = {
				GestureRange:new{
					ges = "tap",
					range = self.dimen:copy(),
				}
			}
		}
	else
		self.key_events = {
			ShowConfigMenu = { { "AA" }, doc = "show config dialog" },
		}
	end
end

function ReaderConfig:onShowConfigMenu()
	local config_dialog = ConfigDialog:new{
		configurable = self.configurable,
		options = self.options,
		dimen = self.dimen:copy(),
	}

	function config_dialog:onConfigChoice(item)
		if item.callback then
			item.callback()
		end
	end
	
	local dialog_container = CenterContainer:new{
		config_dialog,
		dimen = self.dimen:copy(),
	}
	config_dialog.close_callback = function () 
		UIManager:close(menu_container)
	end
	-- maintain a reference to menu_container
	self.dialog_container = dialog_container

	UIManager:show(config_dialog)

	return true
end

function ReaderConfig:onTapShowConfigMenu()
	self:onShowConfigMenu()
	return true
end

function ReaderConfig:onSetDimensions(dimen)
	-- update gesture listenning range according to new screen orientation
	self:init()
end
