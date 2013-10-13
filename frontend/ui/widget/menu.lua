require "ui/widget/container"
require "ui/widget/focusmanager"
require "ui/widget/infomessage"
require "ui/widget/button"
require "ui/widget/text"
require "ui/widget/group"
require "ui/widget/span"
require "ui/font"

--[[
Widget that displays a shortcut icon for menu item
--]]
ItemShortCutIcon = WidgetContainer:new{
	dimen = Geom:new{ w = 22, h = 22 },
	key = nil,
	bordersize = 2,
	radius = 0,
	style = "square"
}

function ItemShortCutIcon:init()
	if not self.key then
		return
	end

	local radius = 0
	local background = 0
	if self.style == "rounded_corner" then
		radius = math.floor(self.width/2)
	elseif self.style == "grey_square" then
		background = 3
	end

	--@TODO calculate font size by icon size  01.05 2012 (houqp)
	local sc_face = nil
	if self.key:len() > 1 then
		sc_face = Font:getFace("ffont", 14)
	else
		sc_face = Font:getFace("scfont", 22)
	end

	self[1] = FrameContainer:new{
		padding = 0,
		bordersize = self.bordersize,
		radius = radius,
		background = background,
		dimen = self.dimen,
		CenterContainer:new{
			dimen = self.dimen,
			TextWidget:new{
				text = self.key,
				face = sc_face,
				bgcolor = background/15,
			},
		},
	}
end

--[[
NOTICE:
@menu entry must be provided in order to close the menu
--]]
MenuCloseButton = InputContainer:new{
	align = "right",
	menu = nil,
	dimen = Geom:new{},
}

function MenuCloseButton:init()
	self[1] = TextWidget:new{
		text = "  X ",
		face = Font:getFace("cfont", 42),
	}

	local text_size = self[1]:getSize()
	self.dimen.w, self.dimen.h = text_size.w, text_size.h

	self.ges_events.Close = {
		GestureRange:new{
			ges = "tap",
			range = self.dimen,
		},
		doc = "Close menu",
	}
end

function MenuCloseButton:onClose()
	self.menu:onClose()
	return true
end

--[[
Widget that displays an item for menu
--]]
MenuItem = InputContainer:new{
	text = nil,
	show_parent = nil,
	detail = nil,
	face = Font:getFace("cfont", 22),
	dimen = nil,
	shortcut = nil,
	shortcut_style = "square",
	_underline_container = nil,
}

function MenuItem:init()
	local shortcut_icon_dimen = Geom:new()
	if self.shortcut then
		shortcut_icon_dimen.w = math.floor(self.dimen.h*4/5)
		shortcut_icon_dimen.h = shortcut_icon_dimen.w
	end

	self.detail = self.text
	-- 15 for HorizontalSpan,
	self.content_width = self.dimen.w - shortcut_icon_dimen.w - 15

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
	end
	if Device:hasKeyboard() then
		self.active_key_events = {
			Select = { {"Press"}, doc = "chose selected item" },
		}
	end

	w = sizeUtf8Text(0, self.dimen.w, self.face, self.text, true).x
	if w >= self.content_width then
		if Device:isTouchDevice() then
		else
			self.active_key_events.ShowItemDetail = {
				{"Right"}, doc = "show item detail"
			}
		end
		indicator = "  >>"
		indicator_w = sizeUtf8Text(0, self.dimen.w, self.face, indicator, true).x
		self.text = getSubTextByWidth(self.text, self.face,
			self.content_width - indicator_w, true) .. indicator
	end

	self._underline_container = UnderlineContainer:new{
		dimen = Geom:new{
			w = self.content_width,
			h = self.dimen.h
		},
		HorizontalGroup:new {
			align = "center",
			TextWidget:new{
				text = self.text,
				face = self.face,
			},
		},
	}

	self[1] = HorizontalGroup:new{
		HorizontalSpan:new{ width = 5 },
		ItemShortCutIcon:new{
			dimen = shortcut_icon_dimen,
			key = self.shortcut,
			radius = shortcut_icon_r,
			style = self.shortcut_style,
		},
		HorizontalSpan:new{ width = 10 },
		self._underline_container
	}
end

function MenuItem:onFocus()
	self._underline_container.color = 15
	self.key_events = self.active_key_events
	return true
end

function MenuItem:onUnfocus()
	self._underline_container.color = 0
	self.key_events = {}
	return true
end

function MenuItem:onShowItemDetail()
	UIManager:show(InfoMessage:new{
		text=self.detail,
	})
	return true
end

function MenuItem:onTapSelect()
	self[1].invert = true
	UIManager:setDirty(self.show_parent, "partial")
	UIManager:scheduleIn(0.1, function()
		self[1].invert = false
		UIManager:setDirty(self.show_parent, "partial")
		self.menu:onMenuSelect(self.table)
	end)
	return true
end


--[[
Widget that displays menu
--]]
Menu = FocusManager:new{
	show_parent = nil,
	-- face for displaying item contents
	cface = Font:getFace("cfont", 22),
	-- face for menu title
	tface = Font:getFace("tfont", 25),
	-- face for paging info display
	fface = Font:getFace("ffont", 16),
	-- font for item shortcut
	sface = Font:getFace("scfont", 20),

	title = "No Title",
	-- default width and height
	width = 500,
	-- height will be calculated according to item number if not given
	height = nil,
	dimen = Geom:new{},
	item_table = {},
	item_shortcuts = {
		"Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P",
		"A", "S", "D", "F", "G", "H", "J", "K", "L", "Del",
		"Z", "X", "C", "V", "B", "N", "M", ".", "Sym", "Enter",
	},
	item_table_stack = nil,
	is_enable_shortcut = true,

	item_dimen = nil,
	page = 1,

	item_group = nil,
	page_info = nil,

	-- set this to true to not paint as popup menu
	is_borderless = false,
	-- if you want to embed the menu widget into another widget, set
	-- this to false
	is_popout = true,
	-- set this to true to add close button
	has_close_button = true,
	-- close_callback is a function, which is executed when menu is closed
	-- it is usually set by the widget which creates the menu
	close_callback = nil
}

function Menu:_recalculateDimen()
	self.dimen.w = self.width
	-- if height not given, dynamically calculate it
	self.dimen.h = self.height or (#self.item_table + 2) * Screen:scaleByDPI(36)
	if self.dimen.h > Screen:getHeight() then
		self.dimen.h = Screen:getHeight()
	end
	self.item_dimen = Geom:new{
		w = self.dimen.w,
		h = Screen:scaleByDPI(36), -- hardcoded for now
	}
	self.perpage = math.floor((self.dimen.h - self.dimen.x) / self.item_dimen.h) - 2
	self.page_num = math.ceil(#self.item_table / self.perpage)
	-- update page info layout, fixed #281
	if self.page_info then
		self.page_info:resetLayout()
	end
end

function Menu:init()
	self.show_parent = self.show_parent or self
	self.item_table_stack = {}
	self:_recalculateDimen()
	self.page = 1

	-----------------------------------
	-- start to set up widget layout --
	-----------------------------------
	self.menu_title = TextWidget:new{
		align = "center",
		text = self.title,
		face = self.tface,
	}
	-- group for title bar
	self.title_bar = OverlapGroup:new{
		dimen = {w = self.dimen.w},
		self.menu_title,
	}
	-- group for items
	self.item_group = VerticalGroup:new{}
	-- group for page info
	self.page_info_left_chev = Button:new{
		icon = "resources/icons/appbar.chevron.left.png",
		callback = function() self:onPrevPage() end,
		bordersize = 0,
	}
	self.page_info_right_chev = Button:new{
		icon = "resources/icons/appbar.chevron.right.png",
		callback = function() self:onNextPage() end,
		bordersize = 0,
	}
	self.page_info_left_chev:hide()
	self.page_info_right_chev:hide()
	self.page_info_text = TextWidget:new{
		text = "",
		face = self.fface,
	}
	self.page_info = HorizontalGroup:new{
		self.page_info_left_chev,
		self.page_info_text,
		self.page_info_right_chev
	}

	local header = self.title_bar
	local body = self.item_group
	local footer = BottomContainer:new{
		dimen = self.dimen:copy(),
		self.page_info,
	}

	local content = nil
	if self.no_title then
		content = OverlapGroup:new{
			dimen = self.dimen:copy(),
			VerticalGroup:new{
				align = "left",
				body,
			},
			footer
		}
	else
		content = OverlapGroup:new{
			dimen = self.dimen:copy(),
			VerticalGroup:new{
				align = "left",
				header,
				body,
			},
			footer
		}
	end

	self[1] = FrameContainer:new{
		background = 0,
		bordersize = self.is_borderless and 0 or 2,
		padding = 0,
		margin = 0,
		radius = math.floor(self.dimen.w/20),
		content
	}

	------------------------------------------
	-- start to set up input event callback --
	------------------------------------------
	if Device:isTouchDevice() then
		if self.has_close_button then
			table.insert(self.title_bar,
				MenuCloseButton:new{
					menu = self,
				})
		end
		-- watch for outer region if it's a self contained widget
		if self.is_popout then
			self.ges_events.TapCloseAllMenus = {
				GestureRange:new{
					ges = "tap",
					range = Geom:new{
						x = 0, y = 0,
						w = Screen:getWidth(),
						h = Screen:getHeight(),
					}
				}
			}
		end
		self.ges_events.Swipe = {
			GestureRange:new{
				ges = "swipe",
				range = self.dimen,
			}
		}
	end
	if Device:hasKeyboard() then
		-- set up keyboard events
		self.key_events.Close = { {"Back"}, doc = _("close menu") }
		self.key_events.NextPage = {
			{Input.group.PgFwd}, doc = _("goto next page of the menu")
		}
		self.key_events.PrevPage = {
			{Input.group.PgBack}, doc = _("goto previous page of the menu")
		}
		-- we won't catch presses to "Right", leave that to MenuItem.
		self.key_events.FocusRight = nil
		-- shortcut icon is not needed for touch device
		if self.is_enable_shortcut then
			self.key_events.SelectByShortCut = { {self.item_shortcuts} }
		end
		self.key_events.Select = {
			{"Press"}, doc = _("select current menu item")
		}
	end


	if #self.item_table > 0 then
		-- if the table is not yet initialized, this call
		-- must be done manually:
		self:updateItems(1)
	end
end

function Menu:updateItems(select_number)
	-- self.layout must be updated for focusmanager
	self.layout = {}
	self.item_group:clear()
	self:_recalculateDimen()

	-- default to select the first item
	if not select_number then
		select_number = 1
	end

	for c = 1, self.perpage do
		-- calculate index in item_table
		local i = (self.page - 1) * self.perpage + c
		if i <= #self.item_table then
			local item_shortcut = nil
			local shortcut_style = "square"
			if self.is_enable_shortcut then
				-- give different shortcut_style to keys in different
				-- lines of keyboard
				if c >= 11 and c <= 20 then
					--shortcut_style = "rounded_corner"
					shortcut_style = "grey_square"
				end
				item_shortcut = self.item_shortcuts[c]
				if item_shortcut == "Enter" then
					item_shortcut = "Ent"
				end
			end
			local item_tmp = MenuItem:new{
				show_parent = self.show_parent,
				text = self.item_table[i].text,
				face = self.cface,
				dimen = self.item_dimen:new(),
				shortcut = item_shortcut,
				shortcut_style = shortcut_style,
				table = self.item_table[i],
				menu = self,
			}
			table.insert(self.item_group, item_tmp)
			-- this is for focus manager
			table.insert(self.layout, {item_tmp})
		end -- if i <= self.items
	end -- for c=1, self.perpage
	if self.item_group[1] then
		if not Device:isTouchDevice() then
			-- only draw underline for nontouch device
			-- reset focus manager accordingly
			self.selected = { x = 1, y = select_number }
			-- set focus to requested menu item
			self.item_group[select_number]:onFocus()
		end
		-- update page information
		self.page_info_text.text = _("page ")..self.page.."/"..self.page_num
		self.page_info_left_chev:showHide(self.page_num > 1)
		self.page_info_right_chev:showHide(self.page_num > 1)
		self.page_info_left_chev:enableDisable(self.page > 1)
		self.page_info_right_chev:enableDisable(self.page < self.page_num)
	else
		self.page_info_text.text = _("no choices available")
	end

	-- FIXME: this is a dirty hack to clear previous menus
	UIManager.repaint_all = true
	--UIManager:setDirty(self)
end

function Menu:swithItemTable(new_title, new_item_table)
	if self.menu_title then
		self.menu_title.text = new_title
	end
	self.page = 1
	self.item_table = new_item_table
	self:updateItems(1)
end

function Menu:onSelectByShortCut(_, keyevent)
	for k,v in ipairs(self.item_shortcuts) do
		if k > self.perpage then
			break
		elseif v == keyevent.key then
			if self.item_table[(self.page-1)*self.perpage + k] then
				self:onMenuSelect(self.item_table[(self.page-1)*self.perpage + k])
			end
			break
		end
	end
	return true
end

function Menu:onWrapFirst()
	if self.page > 1 then
		self.page = self.page - 1
		local end_position = self.perpage
		if self.page == self.page_num then
			end_position = #self.item_table % self.perpage
		end
		self:updateItems(end_position)
	end
	return false
end

function Menu:onWrapLast()
	if self.page < self.page_num then
		self:onNextPage()
	end
	return false
end

--[[
override this function to process the item selected in a different manner
]]--
function Menu:onMenuSelect(item)
	if item.sub_item_table == nil then
		self.close_callback()
		self:onMenuChoice(item)
	else
		-- save menu title for later resume
		self.item_table.title = self.title
		table.insert(self.item_table_stack, self.item_table)
		self:swithItemTable(item.text, item.sub_item_table)
	end
	return true
end

--[[
	default to call item callback
	override this function to handle the choice
--]]
function Menu:onMenuChoice(item)
	if item.callback then
		item.callback()
	end
	return true
end

function Menu:onNextPage()
	if self.page < self.page_num then
		self.page = self.page + 1
		self:updateItems(1)
	elseif self.page == self.page_num then
		-- on the last page, we check if we're on the last item
		local end_position = #self.item_table % self.perpage
		if end_position == 0 then
			end_position = self.perpage
		end
		if end_position ~= self.selected.y then
			self:updateItems(end_position)
		end
	end
	return true
end

function Menu:onPrevPage()
	if self.page > 1 then
		self.page = self.page - 1
	end
	self:updateItems(1)
	return true
end

function Menu:onSelect()
	self:onMenuSelect(self.item_table[(self.page-1)*self.perpage+self.selected.y])
	return true
end

function Menu:onClose()
	local table_length = #self.item_table_stack
	if table_length == 0 then
		self:onCloseAllMenus()
	else
		-- back to parent menu
		parent_item_table = table.remove(self.item_table_stack, table_length)
		self:swithItemTable(parent_item_table.title, parent_item_table)
	end
	return true
end

function Menu:onCloseAllMenus()
	UIManager:close(self)
	if self.close_callback then
		self.close_callback()
	end
	return true
end

function Menu:onTapCloseAllMenus(arg, ges_ev)
	if ges_ev.pos:notIntersectWith(self.dimen) then
		self:onCloseAllMenus()
		return true
	end
end

function Menu:onSwipe(arg, ges_ev)
	if ges_ev.direction == "west" then
		self:onNextPage()
	elseif ges_ev.direction == "east" then
		self:onPrevPage()
	end
end
