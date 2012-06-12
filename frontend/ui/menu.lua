require "ui/widget"
require "ui/focusmanager"
require "ui/infomessage"
require "ui/font"

--[[
Widget that displays a shortcut icon for menu item
]]
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
			},
		},
	}
end


--[[
Widget that displays an item for menu

]]
MenuItem = InputContainer:new{
	text = nil,
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
	self.active_key_events = {
		Select = { {"Press"}, doc = "chose selected item" },
	}

	w = sizeUtf8Text(0, self.dimen.w, self.face, self.text, true).x
	if w >= self.content_width then
		self.active_key_events.ShowItemDetail = { {"Right"}, doc = "show item detail" }
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
	self._underline_container.color = 10
	self.key_events = self.active_key_events
	return true
end

function MenuItem:onUnfocus()
	self._underline_container.color = 0
	self.key_events = { }
	return true
end

function MenuItem:onShowItemDetail()
	UIManager:show(InfoMessage:new{
		text=self.detail,
	})
	return true
end


--[[
Widget that displays menu
]]
Menu = FocusManager:new{
	-- face for displaying item contents
	cface = Font:getFace("cfont", 22),
	-- face for menu title
	tface = Font:getFace("tfont", 25),
	-- face for paging info display
	fface = Font:getFace("ffont", 16),
	-- font for item shortcut
	sface = Font:getFace("scfont", 20),

	title = "No Title",
	dimen = Geom:new{ w = 500, h = 500 },
	item_table = {},
	item_shortcuts = {
		"Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P",
		"A", "S", "D", "F", "G", "H", "J", "K", "L", "Del",
		"Z", "X", "C", "V", "B", "N", "M", ".", "Sym", "Enter",
	},
	item_table_stack = {},
	is_enable_shortcut = true,

	item_dimen = nil,
	page = 1,

	item_group = nil,
	page_info = nil,

	-- set this to true to not paint as popup menu
	is_borderless = false,
}

function Menu:init()
	self.item_dimen = Geom:new{
		w = self.dimen.w,
		h = 36, -- hardcoded for now
	}

	self.perpage = math.floor(self.dimen.h / self.item_dimen.h) - 2
	self.page = 1
	self.page_num = math.ceil(#self.item_table / self.perpage)

	-- set up keyboard events
	self.key_events.Close = { {"Back"}, doc = "close menu" }
	self.key_events.NextPage = {
		{Input.group.PgFwd}, doc = "goto next page of the menu"
	}
	self.key_events.PrevPage = {
		{Input.group.PgBack}, doc = "goto previous page of the menu"
	}
	-- we won't catch presses to "Right"
	self.key_events.FocusRight = nil
	if self.is_enable_shortcut then
		self.key_events.SelectByShortCut = { {self.item_shortcuts} }
	end
	self.key_events.Select = { {"Press"}, doc = "select current menu item"}

	self.menu_title = TextWidget:new{
		text = self.title,
		face = self.tface,
	}
	-- group for items
	self.item_group = VerticalGroup:new{}
	self.page_info = TextWidget:new{
		face = self.fface,
	}

	local content = VerticalGroup:new{
		self.menu_title,
		self.item_group,
		self.page_info,
	} -- VerticalGroup

	if not self.is_borderless then
		self[1] = CenterContainer:new{
			FrameContainer:new{
				background = 0,
				radius = math.floor(self.dimen.w/20),
				content
			},
			dimen = Screen:getSize(),
		}
		-- we need to substract border, margin and padding
		self.item_dimen.w = self.item_dimen.w - 14
	else
		self[1] = FrameContainer:new{
			background = 0,
			bordersize = 0,
			padding = 0,
			margin = 0,
			dimen = Screen:getSize(),
			content
		}
	end

	if #self.item_table > 0 then
		-- if the table is not yet initialized, this call
		-- must be done manually:
		self:updateItems(1)
	end
end

function Menu:updateItems(select_number)
	self.layout = {}
	self.item_group:clear()

	for c = 1, self.perpage do
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
				text = self.item_table[i].text,
				face = self.cface,
				dimen = self.item_dimen,
				shortcut = item_shortcut,
				shortcut_style = shortcut_style,
			}
			table.insert(self.item_group, item_tmp)
			table.insert(self.layout, {item_tmp})
			--self.last_shortcut = c
		end -- if i <= self.items
	end -- for c=1, self.perpage
	if self.item_group[1] then
		-- reset focus manager accordingly
		self.selected = { x = 1, y = select_number }
		-- set focus to requested menu item
		self.item_group[select_number]:onFocus()
		-- update page information
		self.page_info.text = "page "..self.page.."/"..self.page_num
	else
		self.page_info.text = "no choices available"
	end

	UIManager:setDirty(self)
end

function Menu:swithItemTable(new_title, new_item_table)
	self.menu_title.text = new_title
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
		UIManager:close(self)
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
override this function to handle the choice
]]--
function Menu:onMenuChoice(item)
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
		self:updateItems(1)
	end
	return true
end

function Menu:onSelect()
	self:onMenuSelect(self.item_table[(self.page-1)*self.perpage+self.selected.y])
	return true
end

function Menu:onClose()
	local table_length = #self.item_table_stack
	if table_length == 0 then
		UIManager:close(self)
	else
		-- back to parent menu
		parent_item_table = table.remove(self.item_table_stack, table_length)
		self:swithItemTable(parent_item_table.title, parent_item_table)
	end
	return true
end

