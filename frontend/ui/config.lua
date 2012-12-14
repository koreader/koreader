require "ui/widget"
require "ui/focusmanager"
require "ui/infomessage"
require "ui/font"

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

function ConfigMenuItem:onFocus()
	self[1].inverse = true
	self.key_events = self.active_key_events
	return true
end

function ConfigMenuItem:onUnfocus()
	self[1].inverse = false
	self.key_events = { }
	return true
end

function ConfigMenuItem:onTapSelect()
	self.config:onShowDialog(self.dialog)
	return true
end

MenuItemDialog = FocusManager:new{
	dimen = nil,
	menu_item = nil,
	title = nil,
	is_borderless = false,
}

--[[
Widget that displays config menu
--]]
ConfigDialog = FocusManager:new{
	-- set this to true to not paint as popup menu
	is_borderless = false,
}

function ConfigDialog:init()
	self.menu_dimen = self.dimen:copy()
	-----------------------------------
	-- start to set up widget layout --
	-----------------------------------
	self.screen_rotate_options = HorizontalGroup:new{
		
	}
	self.screen_rotate_icon = ImageWidget:new{
		file = "resources/icons/appbar.transform.rotate.right.large.png"
	}
	self.screen_rotate_dialog = FrameContainer:new{
			dimen = self.screen_rotate_options:getSize(),
			background = 0,
			bordersize = 0,
			padding = 0,
			margin = 0,
			self.screen_rotate_options,
	}
	self.page_crop_icon = ImageWidget:new{
		file = "resources/icons/appbar.crop.large.png"
	}
	self.page_layout_icon = ImageWidget:new{
		file = "resources/icons/appbar.column.two.large.png"
	}
	self.text_font_icon = ImageWidget:new{
		file = "resources/icons/appbar.text.size.large.png"
	}
	self.contrast_icon = ImageWidget:new{
		file = "resources/icons/appbar.grade.b.large.png"
	}
	self.more_options_icon = ImageWidget:new{
		file = "resources/icons/appbar.settings.large.png"
	}
	self.icon_spacing = HorizontalSpan:new{
		width = (Screen:getWidth() - 64*6 - 20) / 7 
	}
	
	self.icon_dimen = Geom:new{
		w = 64,
		h = 64, -- hardcoded for now
	}
	
	-- group for config layout
	local config_dialog = VerticalGroup:new{
		align = "center",
		HorizontalGroup:new{
			align = "center",
			MenuItemDialog:new{
				self.screen_rotate_dialog,
				dimen = self.screen_rotate_dialog:getSize(),
				title = "Screen Rotation",
			},
		},
		HorizontalGroup:new{
			align = "center",
			self.icon_spacing,
			ConfigMenuItem:new{
				self.screen_rotate_icon,
				dimen = self.icon_dimen:new(),
				config = self,
			},
			self.icon_spacing,
			ConfigMenuItem:new{
				self.page_crop_icon,
				dimen = self.icon_dimen:new(),
				dialog = "Crop dialog",
				config = self,
			},
			self.icon_spacing,
			ConfigMenuItem:new{
				self.page_layout_icon,
				dimen = self.icon_dimen:new(),
				config = self,
			},
			self.icon_spacing,
			ConfigMenuItem:new{
				self.text_font_icon,
				dimen = self.icon_dimen:new(),
				config = self,
			},
			self.icon_spacing,
			ConfigMenuItem:new{
				self.contrast_icon,
				dimen = self.icon_dimen:new(),
				config = self,
			},
			self.icon_spacing,
			ConfigMenuItem:new{
				self.more_options_icon,
				dimen = self.icon_dimen:new(),
				config = self,
			},
			self.icon_spacing,
		}
	}
	-- maintain reference to content so we can change it later
	self.config_dialog = config_dialog

	self[1] = BottomContainer:new{
		dimen = Screen:getSize(),
		FrameContainer:new{
			dimen = config_dialog:getSize(),
			background = 0,
			config_dialog
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

function ConfigDialog:onShowDialog(dialog)
	DEBUG("Showing dialog of item", dialog)
	UIManager:show(dialog)
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