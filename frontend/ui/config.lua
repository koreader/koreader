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

MenuBarItem = InputContainer:new{}
function MenuBarItem:init()
	self.dimen = self[1]:getSize()
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

function MenuBarItem:onTapSelect()
	for _, item in pairs(self.items) do
		item[1].invert = false
	end
	self[1].invert = true
	self.config:onShowOptions(self.options)
	UIManager.repaint_all = true
	return true
end

OptionTextItem = InputContainer:new{}
function OptionTextItem:init()
	local text_widget = self[1]
	self.dimen = text_widget:getSize()
	self[1] = UnderlineContainer:new{
		text_widget,
		padding = self.padding,
		color = self.color,
		}
	-- we need this table per-instance, so we declare it here
	if Device:isTouchDevice() then
		self.ges_events = {
			TapSelect = {
				GestureRange:new{
					ges = "tap",
					range = self.dimen,
				},
				doc = "Select Option Item",
			},
		}
	else
		self.active_key_events = {
			Select = { {"Press"}, doc = "chose selected item" },
		}
	end
end

function OptionTextItem:onTapSelect()
	for _, item in pairs(self.items) do
		item[1].color = 0
	end
	self[1].color = 15
	local option_value = nil
	if type(self.values) == "table" then
		option_value = self.values[self.current_item]
		self.config:onConfigChoice(self.name, option_value)
	end
	UIManager.repaint_all = true
	return true
end

ConfigIcons = HorizontalGroup:new{}
function ConfigIcons:init()
	for c = 1, #self.icons do
		table.insert(self, self.spacing)
		table.insert(self, self.icons[c])
	end
	table.insert(self, self.spacing)
end

ConfigOption = CenterContainer:new{dimen = Geom:new{ w = Screen:getWidth(), h = math.floor(150*Screen:getWidth()/600)}}
function ConfigOption:init()
	local default_name_font_size = math.floor(20*Screen:getWidth()/600)
	local default_item_font_size = math.floor(16*Screen:getWidth()/600)
	local default_items_spacing = math.floor(30*Screen:getWidth()/600)
	local default_option_height = math.floor(30*Screen:getWidth()/600)
	local vertical_group = VerticalGroup:new{}
	for c = 1, #self.options do
		if self.options[c].show ~= false then
			local name_align = self.options[c].name_align_right and self.options[c].name_align_right or 0.33
			local item_align = self.options[c].item_align_center and self.options[c].item_align_center or 0.66
			local name_font_face = self.options[c].name_font_face and self.options[c].name_font_face or "tfont"
			local name_font_size = self.options[c].name_font_size and self.options[c].name_font_size or default_name_font_size
			local item_font_face = self.options[c].item_font_face and self.options[c].item_font_face or "cfont"
			local item_font_size = self.options[c].item_font_size and self.options[c].item_font_size or default_item_font_size
			local option_height = self.options[c].height and self.options[c].height or default_option_height
			local items_spacing = HorizontalSpan:new{ width = self.options[c].spacing and self.options[c].spacing or default_items_spacing}
			
			local horizontal_group = HorizontalGroup:new{}
			if self.options[c].name_text then
				local option_name_container = RightContainer:new{
					dimen = Geom:new{ w = Screen:getWidth()*name_align, h = option_height},
				}
				local option_name =	TextWidget:new{
						text = self.options[c].name_text,
						face = Font:getFace(name_font_face, name_font_size),
				}
				table.insert(option_name_container, option_name)
				table.insert(horizontal_group, option_name_container)
			end
			
			if self.options[c].widget == "ProgressWidget" then
				local widget_container = CenterContainer:new{
					dimen = Geom:new{w = Screen:getWidth()*self.options[c].widget_align_center, h = option_height}
				}
				local widget = ProgressWidget:new{
					width = self.options[c].width,
					height = self.options[c].height,
					percentage = self.options[c].percentage,
				}
				table.insert(widget_container, widget)
				table.insert(horizontal_group, widget_container)
			end
			
			local option_items_container = CenterContainer:new{
				dimen = Geom:new{w = Screen:getWidth()*item_align, h = option_height}
			}
			local option_items_group = HorizontalGroup:new{}
			local option_items_fixed = false
			local option_items = {}
			if type(self.options[c].item_font_size) == "table" then
				option_items_group.align = "bottom"
				option_items_fixed = true
			end
			-- make current index according to configurable table
			local current_item = nil
			if self.options[c].name then
				local val = self.config.configurable[self.options[c].name]
				local min_diff = math.abs(val - self.options[c].values[1])
				local diff = nil
				for index, val_ in pairs(self.options[c].values) do
					if val == val_ then
						current_item = index
						break
					end
					diff = math.abs(val - val_)
					if diff <= min_diff then
						min_diff = diff
						current_item = index
					end
				end
			end
			
			for d = 1, #self.options[c].item_text do
				local option_item = nil
				if option_items_fixed then
					option_item = OptionTextItem:new{
						FixedTextWidget:new{
							text = self.options[c].item_text[d],
							face = Font:getFace(item_font_face, item_font_size[d]),
						},
						padding = 3,
						color = d == current_item and 15 or 0,
					}
				else
					option_item = OptionTextItem:new{
						TextWidget:new{
							text = self.options[c].item_text[d],
							face = Font:getFace(item_font_face, item_font_size),
						},
						padding = -3,
						color = d == current_item and 15 or 0,
					}
				end
				option_items[d] = option_item
				option_item.items = option_items
				option_item.name = self.options[c].name
				option_item.values = self.options[c].values
				option_item.current_item = d
				option_item.config = self.config
				table.insert(option_items_group, option_item)
				table.insert(option_items_group, items_spacing)
			end
			table.insert(option_items_container, option_items_group)
			table.insert(horizontal_group, option_items_container)
			table.insert(vertical_group, horizontal_group)
		end -- if
	end -- for
	self[1] = vertical_group
end

ConfigPanel = VerticalGroup:new{}
function ConfigPanel:init()
	local default_option = ConfigOption:new{
		options = self.config_options.default_options
	}
	local menu_bar = FrameContainer:new{
		background = 0,
	}
	local menu_items = {}
	local icons_width = 0
	local icons_height = 0
	for c = 1, #self.config_options do
		local menu_icon = ImageWidget:new{
			file = self.config_options[c].icon
		}
		local icon_dimen = menu_icon:getSize()
		icons_width = icons_width + icon_dimen.w
		icons_height = icon_dimen.h > icons_height and icon_dimen.h or icons_height
		
		menu_items[c] = MenuBarItem:new{
			menu_icon,
			options = ConfigOption:new{
				options = self.config_options[c].options,
				config = self.config_dialog,
			},
			config = self.config_dialog,
			items = menu_items,
		}
	end
	menu_bar[1] = ConfigIcons:new{
		icons = menu_items,
		spacing = HorizontalSpan:new{
			width = (Screen:getWidth() - icons_width) / (#menu_items+1)
		}
	}
	menu_bar.dimen = Geom:new{ w = Screen:getWidth(), h = icons_height}
	
	self[1] = default_option
	self[2] = menu_bar
end

--[[
Widget that displays config menu
--]]
ConfigDialog = InputContainer:new{
	--is_borderless = false,
}

function ConfigDialog:init()
	------------------------------------------
	-- start to set up widget layout ---------
	------------------------------------------
	self.config_panel = ConfigPanel:new{ 
		config_options = self.config_options,
		config_dialog = self,
	}
	
	local config_panel_size = self.config_panel:getSize()
	
	self.menu_dimen = Geom:new{
		x = (Screen:getWidth() - config_panel_size.w)/2,
		y = Screen:getHeight() - config_panel_size.h,
		w = config_panel_size.w,
		h = config_panel_size.h,
	}

	self[1] = BottomContainer:new{
		dimen = Screen:getSize(),
		FrameContainer:new{
			dimen = self.config_panel:getSize(),
			background = 0,
			self.config_panel,
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
	self.config_panel[1] = options
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
		--self.ui:handleEvent(Event:new("GotoPageRel", 0))
		return true
	end
end
