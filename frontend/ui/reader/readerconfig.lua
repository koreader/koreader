require "ui/widget/config"

Configurable = {}

function Configurable:hash(sep)
	local hash = ""
	local excluded = {multi_threads = true,}
	for key,value in pairs(self) do
		if type(value) == "number" or type(value) == "string" 
			and not excluded[key] then
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
		if type(value) == "number" or type(value) == "string"
			or type(value) == "table" then
			local saved_value = settings:readSetting(prefix..key)
			self[key] = (saved_value == nil) and self[key] or saved_value
			--Debug("Configurable:loadSettings", "key", key, "saved value", saved_value,"Configurable.key", self[key])
		end
	end
	--Debug("loaded config:", dump(Configurable))
end

function Configurable:saveSettings(settings, prefix)
	for key,value in pairs(self) do
		if type(value) == "number" or type(value) == "string"
			or type(value) == "table" then
			settings:saveSetting(prefix..key, value)
		end
	end
end

ReaderConfig = InputContainer:new{
	last_panel_index = 1,
}

function ReaderConfig:init()
	if Device:hasKeyboard() then
		self.key_events = {
			ShowConfigMenu = { { "AA" }, doc = _("show config dialog") },
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
				range = Geom:new{
					x = 0,
					y = 11*Screen:getHeight()/12,
					w = Screen:getWidth(),
					h = Screen:getHeight()/12,
				}
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
		close_callback = function() self:onCloseCallback() end,
	}
	self.ui:handleEvent(Event:new("DisableHinting"))
	-- show last used panel when opening config dialog
	self.config_dialog:onShowConfigPanel(self.last_panel_index)
	UIManager:show(self.config_dialog)

	return true
end

function ReaderConfig:onTapShowConfigMenu()
	self:onShowConfigMenu()
	return true
end

function ReaderConfig:onSetDimensions(dimen)
	if Device:isTouchDevice() then
		self:initGesListener()
	end
	-- since we cannot redraw config_dialog with new size, we close
	-- the old one on screen size change
	if self.config_dialog then
		self.config_dialog:closeDialog()
	end
end

function ReaderConfig:onCloseCallback()
	self.last_panel_index = self.config_dialog.panel_index
	self.ui:handleEvent(Event:new("RestoreHinting"))
end

-- event handler for readercropping
function ReaderConfig:onCloseConfig()
	self.config_dialog:closeDialog()
end

function ReaderConfig:onReadSettings(config)
	self.configurable:loadSettings(config, self.options.prefix.."_")
	self.last_panel_index = config:readSetting("config_panel_index") or 1
end

function ReaderConfig:onCloseDocument()
	self.configurable:saveSettings(self.ui.doc_settings, self.options.prefix.."_")
	self.ui.doc_settings:saveSetting("config_panel_index", self.last_panel_index)
end
