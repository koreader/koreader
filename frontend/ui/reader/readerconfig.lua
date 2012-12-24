require "ui/config"

KOPTOptions = {
	default_options = {
		{
			widget = "ProgressWidget",
			widget_align_center = 0.8,
			width = Screen:getWidth()*0.7,
			height = 5,
			percentage = 0.0,
			item_text = {"Goto"},
			item_align_center = 0.2,
			item_font_face = "tfont",
			item_font_size = 20,
		}
	},
	{
		icon = "resources/icons/appbar.transform.rotate.right.large.png",
		options = {
			{
				name="screen_rotation",
				name_text = "Screen Rotation",
				item_text = {"portrait", "landscape"},
				values = {0, 90},
				default_value = 0,
			}
		}
	},
	{
		icon = "resources/icons/appbar.crop.large.png",
		options = {
			{
				name="trim_page",
				name_text = "Page Crop",
				item_text = {"auto", "manual"},
				values = {1, 0},
				default_value = 1,
			}
		}
	},
	{
		icon = "resources/icons/appbar.column.two.large.png",
		options = {
			{
				name = "text_wrap",
				name_text = "Reflow",
				item_text = {"on","off"},
				values = {1, 0},
				default_value = 1,
				show = false
			},
			{
				name = "max_columns",
				name_text = "Columns",
				item_text = {"1","2","3","4"},
				values = {1,2,3,4},
				default_value = 2,
				show = false
			},
			{
				name = "page_margin",
				name_text = "Page Margin",
				item_text = {"small", "medium", "large"},
				values = {0.02, 0.06, 0.10},
				default_value = 0.06,
			},
			{
				name = "line_spacing",
				name_text = "Line Spacing",
				item_text = {"small", "medium", "large"},
				values = {1.0, 1.2, 1.4},
				default_value = 1.2,
			},
			{
				name = "word_spacing",
				name_text = "Word Spacing",
				item_text = {"small", "medium", "large"},
				values = {0.05, 0.15, 0.375},
				default_value = 0.15,
			},
			{
				name = "justification",
				name_text = "Justification",
				item_text = {"auto","left","center","right","full"},
				values = {-1,0,1,2,3},
				default_value = -1,
			},
		}
	},
	{
		icon = "resources/icons/appbar.text.size.large.png",
		options = {
			{
				name = "font_size",
				item_text = {"Aa","Aa","Aa","Aa","Aa","Aa","Aa","Aa","Aa","Aa"},
				item_align_center = 1.0,
				spacing = Screen:getWidth()*0.03,
				item_font_size = {20,24,28,32,36,38,40,42,46,50},
				values = {0.2, 0.3, 0.4, 0.6, 0.8, 1.0, 1.2, 1.6, 2.2, 2.8},
				default_value = 1.0,
			},
		}
	},
	{
		icon = "resources/icons/appbar.grade.b.large.png",
		options = {
			{
				name = "contrast",
				name_text = "Contrast",
				name_align_right = 0.2,
				item_text = {"lightest", "lighter", "default", "darker", "darkest"},
				item_font_size = math.floor(18*Screen:getWidth()/600),
				item_align_center = 0.8,
				values = {2.0, 1.5, 1.0, 0.5, 0.2},
				default_value = 1.0,
			}
		}
	},
	{
		icon = "resources/icons/appbar.settings.large.png",
		options = {
			{
				name = "quality",
				name_text = "Render Quality",
				item_text = {"low", "default", "high"},
				values={0.5, 0.8, 1.0},
				default_value = 1.0,
			},
			{
				name = "auto_straighten",
				name_text = "Auto Straighten",
				item_text = {"0 deg", "5 deg", "10 deg"},
				values = {0, 5, 10},
				default_value = 0,
			},
			{
				name = "detect_indent",
				name_text = "Indentation",
				item_text = {"enable","disable"},
				values = {1, 0},
				default_value = 1,
				show = false,
			},
			{
				name = "defect_size",
				name_text = "Defect Size",
				item_text = {"small","medium","large"},
				values = {0.5, 1.0, 2.0},
				default_value = 1.0,
				show = false,
			},
		}
	},
}

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
		config_options = KOPTOptions,
	}

	function config_dialog:onConfigChoice(option_name, option_value)
		self.configurable[option_name] = option_value
		--DEBUG("configurable", self.configurable)
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

function ReaderConfig:onReadSettings(config)
	DEBUG("read setting", config)
	self.configurable:loadSettings(config, 'kopt_')
end

function ReaderConfig:onCloseDocument()
	self.configurable:saveSettings(self.ui.doc_settings, 'kopt_')
end
