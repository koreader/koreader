require "ui/widget/config"

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
	if Device:hasKeyboard() then
		self.key_events = {
			ShowConfigMenu = { { "AA" }, doc = "show config dialog" },
		}
	end
	if Device:isTouchDevice() then
		self:initGesListener()
	end
end

function ReaderConfig:initGesListener()
	self.ges_events = {
		TapShowConfigMenu = {
			GestureRange:new{
				ges = "tap",
				range = self.dimen,
			}
		}
	}
end

function ReaderConfig:onShowConfigMenu()
	self.config_dialog = ConfigDialog:new{
		dimen = self.dimen:copy(),
		ui = self.ui,
		configurable = self.configurable,
		config_options = self.options,
		close_callback = function() 
			self.ui:handleEvent(Event:new("RestoreHinting"))
		end,
	}
	self.ui:handleEvent(Event:new("DisableHinting"))
	UIManager:show(self.config_dialog)

	return true
end

function ReaderConfig:onTapShowConfigMenu()
	self:onShowConfigMenu()
	return true
end

function ReaderConfig:onSetDimensions(dimen)
	self.dimen.x = 0
	self.dimen.y = 7 * Screen:getHeight() / 8
	self.dimen.w = Screen:getWidth()
	self.dimen.h = Screen:getHeight() / 8
	-- since we cannot redraw config_dialog with new size, we close
	-- the old one on screen size change
	if self.config_dialog then
		self.config_dialog:closeDialog()
	end
end

function ReaderConfig:onCloseConfig()
	self.config_dialog:closeDialog()
end

function ReaderConfig:onReadSettings(config)
	self.configurable:loadSettings(config, self.options.prefix..'_')
end

function ReaderConfig:onCloseDocument()
	self.configurable:saveSettings(self.ui.doc_settings, self.options.prefix..'_')
end
