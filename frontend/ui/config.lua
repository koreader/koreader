require "ui/widget"
require "ui/focusmanager"
require "ui/infomessage"
require "ui/font"

FixedTextWidget = TextWidget:new{}
function FixedTextWidget:getSize()
	local tsize = sizeUtf8Text(0, Screen:getWidth(), self.face, self.text, true)
	if not tsize then
		return Geom:new{}
	end
	self._length = tsize.x
	self._height = self.face.size
	return Geom:new{
		w = self._length,
		h = self._height,
	}
end

function FixedTextWidget:paintTo(bb, x, y)
	renderUtf8Text(bb, x, y+self._height, self.face, self.text, true)
end

ConfigMenuItem = InputContainer:new{
	dimen = nil,
}

function ConfigMenuItem:init()
-- we need this table per-instance, so we declare it here
	if Device:isTouchDevice() then
		self.ges_events = {
			TapSelect = {
				GestureRange:new{
					ges = "tap",
					range = self.dimen,
				},
				doc = "Select Menu Item",
			},
		}
	else
		self.active_key_events = {
			Select = { {"Press"}, doc = "chose selected item" },
		}
	end
end

function ConfigMenuItem:onTapSelect()
	for _, item in pairs(self.config.menu_items) do
		item[1].invert = false
	end
	self[1].invert = true
	self.config:onShowOptions(self.options)
	UIManager.repaint_all = true
	return true
end

MenuItemDialog = FocusManager:new{
	dimen = nil,
	menu_item = nil,
	title = nil,
	is_borderless = false,
}

ConfigIcons = HorizontalGroup:new{}
function ConfigIcons:init()
	for c = 1, #self.icons do
		table.insert(self, self.spacing)
		table.insert(self, self.icons[c])
	end
	table.insert(self, self.spacing)
end

ConfigOption = CenterContainer:new{dimen = Geom:new{ w = Screen:getWidth(), h = 100},}
function ConfigOption:init()
	local vertical_group = VerticalGroup:new{}
	for c = 1, #self.options do
		local name_align = self.options[c].name_align_right
		local item_align = self.options[c].item_align_center
		local horizontal_group = HorizontalGroup:new{}
		local option_name_container = RightContainer:new{
			dimen = Geom:new{ w = Screen:getWidth()*(name_align and name_align or 0.33), h = 30},
		}
		local option_name =	TextWidget:new{
				text = self.options[c].name,
				face = self.options[c].name_face,
		}
		table.insert(option_name_container, option_name)
		table.insert(horizontal_group, option_name_container)
		local option_items_container = CenterContainer:new{
			dimen = Geom:new{w = Screen:getWidth()*(item_align and item_align or 0.66), h = 30}
		}
		local option_items_group = HorizontalGroup:new{}
		for d = 1, #self.options[c].items do
			local option_item = TextWidget:new{
				text = self.options[c].items[d],
				face = self.options[c].item_face,
			}
			table.insert(option_items_group, option_item)
			table.insert(option_items_group, self.options[c].spacing)
		end
		table.insert(option_items_container, option_items_group)
		table.insert(horizontal_group, option_items_container)
		table.insert(vertical_group, horizontal_group)
	end
	self[1] = vertical_group
end

ConfigFontSize = CenterContainer:new{dimen = Geom:new{ w = Screen:getWidth(), h = 100},}
function ConfigFontSize:init()
	local vertical_group = VerticalGroup:new{}
	local horizontal_group = HorizontalGroup:new{align = "bottom"}
	for c = 1, #self.items do
		local widget = FixedTextWidget:new{
			text = self.items[c],
			face = Font:getFace(self.item_font_face, self.item_font_size[c]),
		}
		table.insert(horizontal_group, self.spacing)
		table.insert(horizontal_group, widget)
	end
	table.insert(vertical_group, horizontal_group)
	self[1] = vertical_group
end

--[[
Widget that displays config menu
--]]
ConfigDialog = FocusManager:new{
	-- face for option names
	tface = Font:getFace("tfont", 20),
	-- face for option items
	cface = Font:getFace("cfont", 16),
	is_borderless = false,
}

function ConfigDialog:init()	
	self.menu_dimen = self.dimen:copy()
	-----------------------------------
	-- start to set up widget layout --
	-----------------------------------
	self.screen_rotate_icon = ImageWidget:new{
		file = "resources/icons/appbar.transform.rotate.right.large.png"
	}
	self.screen_rotate_options = ConfigOption:new{
		options = {
			{
				name = "Screen Rotation",
				name_face = Font:getFace("tfont", 20),
				items = {"portrait", "landscape"},
				item_face = Font:getFace("cfont", 16),
				spacing = HorizontalSpan:new{ width = 30 },
			}
		},
	}

	self.page_crop_icon = ImageWidget:new{
		file = "resources/icons/appbar.crop.large.png"
	}
	self.page_crop_options = ConfigOption:new{
		options = {
			{
				name = "Page Crop",
				name_face = Font:getFace("tfont", 20),
				items = {"auto", "manual"},
				item_face = Font:getFace("cfont", 16),
				spacing = HorizontalSpan:new{ width = 30 },
			}
		},
	}

	self.page_layout_icon = ImageWidget:new{
		file = "resources/icons/appbar.column.two.large.png"
	}
	self.page_layout_options = ConfigOption:new{
		options = {
			{
				name = "Page Margin",
				name_face = Font:getFace("tfont", 20),
				items = {"small", "medium", "large"},
				item_face = Font:getFace("cfont", 16),
				spacing = HorizontalSpan:new{ width = 30 },
			},
			{
				name = "Line Spacing",
				name_face = Font:getFace("tfont", 20),
				items = {"small", "medium", "large"},
				item_face = Font:getFace("cfont", 16),
				spacing = HorizontalSpan:new{ width = 30 },
			},
			{
				name = "Word Spacing",
				name_face = Font:getFace("tfont", 20),
				items = {"small", "medium", "large"},
				item_face = Font:getFace("cfont", 16),
				spacing = HorizontalSpan:new{ width = 30 },
			},
		},
	}

	self.text_font_icon = ImageWidget:new{
		file = "resources/icons/appbar.text.size.large.png"
	}
	self.text_font_options = ConfigFontSize:new{
		items = {"Aa","Aa","Aa","Aa","Aa","Aa","Aa","Aa","Aa","Aa"},
		item_font_face = "cfont",
		item_font_size={14,16,20,23,26,30,34,38,42,46},
		spacing = HorizontalSpan:new{ width = Screen:getWidth()*0.03 },
	}

	self.contrast_icon = ImageWidget:new{
		file = "resources/icons/appbar.grade.b.large.png"
	}
	self.contrast_options = ConfigOption:new{
		options = {
			{
				name = "Contrast",
				name_face = Font:getFace("tfont", 20),
				name_align_right = 0.2,
				items = {"lightest", "lighter", "default", "darker", "darkest"},
				item_align_center = 0.8,
				item_face = Font:getFace("cfont", 16),
				spacing = HorizontalSpan:new{ width = 30 },
			}
		},
	}

	self.more_options_icon = ImageWidget:new{
		file = "resources/icons/appbar.settings.large.png"
	}
	self.more_options = ConfigOption:new{
		options = {
			{
				name = "Render Quality",
				name_face = Font:getFace("tfont", 20),
				items = {"low", "default", "high"},
				item_face = Font:getFace("cfont", 16),
				spacing = HorizontalSpan:new{ width = 20 },
			},
			{
				name = "Auto Straighten",
				name_face = Font:getFace("tfont", 20),
				items = {"0 deg", "5 deg", "10 deg"},
				item_face = Font:getFace("cfont", 16),
				spacing = HorizontalSpan:new{ width = 20 },
			},
		}
	}
	
	self.icon_dimen = Geom:new{
		w = 64,
		h = 64, -- hardcoded for now
	}
	
	self.reading_progress = VerticalGroup:new{
		ProgressWidget:new{
			width = Screen:getWidth()*0.7,
			height = 5,
			percentage = 0.0,
		}
	}
	local default_options = CenterContainer:new{
		HorizontalGroup:new{
			CenterContainer:new{
				VerticalGroup:new{
					align = "center",
					self.reading_progress,
				},
				dimen = Geom:new{ w = Screen:getWidth()*0.8, h = 100},
			},
			CenterContainer:new{
				TextWidget:new{
					text = "Goto",
					face = self.tface,
				},
				dimen = Geom:new{ w = Screen:getWidth()*0.2, h = 100},
			},
		},
		dimen = Geom:new{ w = Screen:getWidth(), h = 100},
	}
	
	self.menu_items = {
		ConfigMenuItem:new{
			self.screen_rotate_icon,
			options = self.screen_rotate_options,
			dimen = self.icon_dimen:new(),
			config = self,
		},
		ConfigMenuItem:new{
			self.page_crop_icon,
			options = self.page_crop_options,
			dimen = self.icon_dimen:new(),
			config = self,
		},
		ConfigMenuItem:new{
			self.page_layout_icon,
			options = self.page_layout_options,
			dimen = self.icon_dimen:new(),
			config = self,
		},
		ConfigMenuItem:new{
			self.text_font_icon,
			options = self.text_font_options,
			dimen = self.icon_dimen:new(),
			config = self,
		},
		ConfigMenuItem:new{
			self.contrast_icon,
			options = self.contrast_options,
			dimen = self.icon_dimen:new(),
			config = self,
		},
		ConfigMenuItem:new{
			self.more_options_icon,
			options = self.more_options,
			dimen = self.icon_dimen:new(),
			config = self,
		},
	}
	
	local config_icons = ConfigIcons:new{
		icons = self.menu_items,
		spacing = HorizontalSpan:new{
			width = (Screen:getWidth() - self.icon_dimen.w * #self.menu_items - 20) / (#self.menu_items+1)
		},
	}
	
	local config_menu = FrameContainer:new{
		dimen = config_icons:getSize(),
		background = 0,
		config_icons,
	}
	
	-- group for config layout
	local config_layout = VerticalGroup:new{
		default_options,
		config_menu,
	}
	-- maintain reference to content so we can change it later
	self.config_layout = config_layout

	self[1] = BottomContainer:new{
		dimen = Screen:getSize(),
		FrameContainer:new{
			dimen = config_layout:getSize(),
			background = 0,
			config_layout,
		}
	}

	------------------------------------------
	-- start to set up input event callback --
	------------------------------------------
	if Device:isTouchDevice() then
		self.ges_events.TapCloseMenu = {
			GestureRange:new{
				ges = "tap",
				range = Geom:new{
					x = 0, y = 0,
					w = Screen:getWidth(),
					h = Screen:getHeight(),
				}
			}
		}
	else
		-- set up keyboard events
		self.key_events.Close = { {"Back"}, doc = "close config menu" }
		-- we won't catch presses to "Right"
		self.key_events.FocusRight = nil
	end
	self.key_events.Select = { {"Press"}, doc = "select current menu item"}
	
	UIManager.repaint_all = true
end

function ConfigDialog:onShowOptions(options)
	self.config_layout[1] = options
	UIManager.repaint_all = true
	return true
end

function ConfigDialog:onCloseMenu()
	UIManager:close(self)
	if self.close_callback then
		self.close_callback()
	end
	return true
end

function ConfigDialog:onTapCloseMenu(arg, ges_ev)
	if ges_ev.pos:notIntersectWith(self.menu_dimen) then
		self:onCloseMenu()
		return true
	end
end