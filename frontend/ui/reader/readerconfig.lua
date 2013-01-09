require "ui/config"

Configurable = {}

function Configurable:hash(sep)
	local hash = ""
	local excluded = {multi_threads = true,}
	for key,value in pairs(self) do
		if type(value) == "number" and not excluded[key] then
			hash = hash..sep..value
		end
	end
	return hash
end

function Configurable:loadDefaults(config_options)
	for i=1,#config_options do
		local options = config_options[i].options
		for j=1,#config_options[i].options do
			local key = config_options[i].options[j].name
			self[key] = config_options[i].options[j].default_value
			if not self[key] then
				self[key] = config_options[i].options[j].default_arg
			end
		end
	end
end

function Configurable:loadSettings(settings, prefix)
	for key,value in pairs(self) do
		if type(value) == "number" then
			saved_value = settings:readSetting(prefix..key)
			self[key] = (saved_value == nil) and self[key] or saved_value
			--Debug("Configurable:loadSettings", "key", key, "saved value", saved_value,"Configurable.key", self[key])
		end
	end
	--Debug("loaded config:", dump(Configurable))
end

function Configurable:saveSettings(settings, prefix)
	for key,value in pairs(self) do
		if type(value) == "number" then
			settings:saveSetting(prefix..key, value)
		end
	end
end

ReaderConfig = InputContainer:new{
	dimen = Geom:new{
		x = 0, 
		y = 7*Screen:getHeight()/8,
		w = Screen:getWidth(),
		h = Screen:getHeight()/8,
	}
}

function ReaderConfig:init()
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
		dimen = self.dimen:copy(),
		ui = self.ui,
		configurable = self.configurable,
		config_options = self.options,
	}

	function config_dialog:onConfigChoice(option_name, option_value, event)
		self.configurable[option_name] = option_value
		if event then
			self.ui:handleEvent(Event:new(event, option_value))
		end
	end
	
	local dialog_container = CenterContainer:new{
		config_dialog,
		dimen = self.dimen:copy(),
	}
	config_dialog.close_callback = function () 
		UIManager:close(menu_container)
	end

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

function ReaderConfig:onReadSettings(config)
	self.configurable:loadSettings(config, self.options.prefix..'_')
end

function ReaderConfig:onCloseDocument()
	self.configurable:saveSettings(self.ui.doc_settings, self.options.prefix..'_')
end
