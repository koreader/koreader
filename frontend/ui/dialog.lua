require "ui/widget"
require "ui/font"

--[[
Wrapper Widget that manages focus for a whole dialog

supports a 2D model of active elements

e.g.:
	layout = {
		{ textinput, textinput },
		{ okbutton,  cancelbutton }
	}

this is a dialog with 2 rows. in the top row, there is the
single (!) widget <textinput>. when the focus is in this
group, left/right movement seems (!) to be doing nothing.

in the second row, there are two widgets and you can move
left/right. also, you can go up from both to reach <textinput>,
and from that go down and (depending on internat coordinates)
reach either <okbutton> or <cancelbutton>.

but notice that this does _not_ do the layout for you,
it rather defines an abstract layout.
]]
FocusManager = InputContainer:new{
	selected = nil, -- defaults to x=1, y=1
	layout = nil, -- mandatory
	movement_allowed = { x = true, y = true }
}

function FocusManager:init()
	self.selected = { x = 1, y = 1 }
	self.key_events = {
		-- these will all generate the same event, just with different arguments
		FocusUp =    { {"Up"},    doc = "move focus up",    event = "FocusMove", args = {0, -1} },
		FocusDown =  { {"Down"},  doc = "move focus down",  event = "FocusMove", args = {0,  1} },
		FocusLeft =  { {"Left"},  doc = "move focus left",  event = "FocusMove", args = {-1, 0} },
		FocusRight = { {"Right"}, doc = "move focus right", event = "FocusMove", args = {1,  0} },
	}
end

function FocusManager:onFocusMove(args)
	local dx, dy = unpack(args)

	if (dx ~= 0 and not self.movement_allowed.x)
		or (dy ~= 0 and not self.movement_allowed.y) then
		return true
	end

	local current_item = self.layout[self.selected.y][self.selected.x]
	while true do
		if self.selected.x + dx > #self.layout[self.selected.y]
		or self.selected.x + dx < 1 then
			break  -- abort when we run into horizontal borders
		end

		-- move cyclic in vertical direction
		if self.selected.y + dy > #self.layout then
			self.selected.y = 1
		elseif self.selected.y + dy < 1 then
			self.selected.y = #self.layout
		else
			self.selected.y = self.selected.y + dy
		end
		self.selected.x = self.selected.x + dx

		if self.layout[self.selected.y][self.selected.x] ~= current_item
		or not self.layout[self.selected.y][self.selected.x].is_inactive then
			-- we found a different object to focus
			current_item:handleEvent(Event:new("Unfocus"))
			self.layout[self.selected.y][self.selected.x]:handleEvent(Event:new("Focus"))
			-- trigger a repaint (we need to be the registered widget!)
			UIManager:setDirty(self)
			break
		end
	end

	return true
end


--[[
a button widget
]]
Button = WidgetContainer:new{
	text = nil, -- mandatory
	preselect = false
}

function Button:init()
	-- set FrameContainer content
	self[1] = FrameContainer:new{
		margin = 0,
		bordersize = 3,
		background = 0,
		radius = 15,
		padding = 2,

		HorizontalGroup:new{
			HorizontalSpan:new{ width = 8 },
			TextWidget:new{
				text = self.text,
				face = Font:getFace("cfont", 20)
			},
			HorizontalSpan:new{ width = 8 },
		}
	}
	if self.preselect then
		self[1].color = 15
	else
		self[1].color = 5
	end
end

function Button:onFocus()
	self[1].color = 15
	return true
end

function Button:onUnfocus()
	self[1].color = 5
	return true
end


--[[
Widget that shows a message and OK/Cancel buttons
]]
ConfirmBox = FocusManager:new{
	text = "no text",
	width = nil,
	ok_text = "OK",
	cancel_text = "Cancel",
	ok_callback = function() end,
	cancel_callback = function() end,
}

function ConfirmBox:init()
	-- calculate box width on the fly if not given
	if not self.width then
		self.width = G_width - 200
	end
	-- build bottons
	self.key_events.Close = { {{"Home","Back"}}, doc = "cancel" }
	self.key_events.Select = { {{"Enter","Press"}}, doc = "chose selected option" }

	local ok_button = Button:new{
		text = self.ok_text,
	}
	local cancel_button = Button:new{
		text = self.cancel_text,
		preselect = true
	}

	self.layout = { { ok_button, cancel_button } }
	self.selected.x = 2 -- Cancel is default 

	self[1] = CenterContainer:new{
		dimen = { w = G_width, h = G_height },
		FrameContainer:new{
			margin = 2,
			background = 0,
			padding = 10,
			HorizontalGroup:new{
				ImageWidget:new{
					file = "resources/info-i.png"
				},
				HorizontalSpan:new{ width = 10 },
				VerticalGroup:new{
					align = "left",
					TextBoxWidget:new{
						text = self.text,
						face = Font:getFace("cfont", 30),
						width = self.width,
					},
					VerticalSpan:new{ width = 10 },
					HorizontalGroup:new{
						ok_button,
						HorizontalSpan:new{ width = 10 },
						cancel_button,
					}
				}
			}
		}
	}
end

function ConfirmBox:onClose()
	UIManager:close(self)
	return true
end

function ConfirmBox:onSelect()
	debug("selected:", self.selected.x)
	if self.selected.x == 1 then
		self:ok_callback()
	else
		self:cancel_callback()
	end
	UIManager:close(self)
	return true
end
	

--[[
Widget that displays an informational message

it vanishes on key press or after a given timeout
]]
InfoMessage = InputContainer:new{
	face = Font:getFace("infofont", 25),
	text = "",
	timeout = nil,

	key_events = {
		AnyKeyPressed = { { Input.group.Any }, seqtext = "any key", doc = "close dialog" }
	}
}

function InfoMessage:init()
	-- we construct the actual content here because self.text is only available now
	self[1] = CenterContainer:new{
		dimen = { w = G_width, h = G_height },
		FrameContainer:new{
			margin = 2,
			background = 0,
			HorizontalGroup:new{
				align = "center",
				ImageWidget:new{
					file = "resources/info-i.png"
				},
				HorizontalSpan:new{ width = 10 },
				TextBoxWidget:new{
					text = self.text,
					face = Font:getFace("cfont", 30)
				}
			}
		}
	}
end

function InfoMessage:onShow()
	-- triggered by the UIManager after we got successfully shown (not yet painted)
	if self.timeout then
		UIManager:scheduleIn(self.timeout, function() UIManager:close(self) end)
	end
	return true
end

function InfoMessage:onAnyKeyPressed()
	-- triggered by our defined key events
	UIManager:close(self)
	return true
end


--[[
Widget that displays a shortcut icon for menu item
]]
ItemShortCutIcon = WidgetContainer:new{
	width = 22,
	height = 22,
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
		dimen = {
			w = self.width,
			h = self.height,
		},
		CenterContainer:new{
			dimen = {
				w = self.width,
				h = self.height,
			},
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
MenuItem = WidgetContainer:new{
	text = nil,
	detail = nil,
	face = Font:getFace("cfont", 22),
	width = nil,
	height = nil,
	shortcut = nil,
	shortcut_style = "square",
	_underline_container = nil
}

function MenuItem:init()
	local shortcut_icon_w = 0
	local shortcut_icon_h = 0
	if self.shortcut then
		shortcut_icon_w = math.floor(self.height*4/5)
		shortcut_icon_h = shortcut_icon_w 
	end

	self.detail = self.text
	-- 15 for HorizontalSpan,
	self.content_width = self.width - shortcut_icon_w - 15

	w = sizeUtf8Text(0, self.width, self.face, self.text, true).x
	if w >= self.content_width then
		indicator = "  >>"
		indicator_w = sizeUtf8Text(0, self.width, self.face, indicator, true).x
		self.text = getSubTextByWidth(self.text, self.face,
			self.content_width - indicator_w, true) .. indicator
	end

	self._underline_container = UnderlineContainer:new{
		dimen = {
			w = self.content_width,
			h = self.height
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
			width = shortcut_icon_w,
			height = shortcut_icon_h,
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
	return true
end

function MenuItem:onUnfocus()
	self._underline_container.color = 0
	return true
end

function MenuItem:onShowDetail()
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
	height = 500,
	width = 500,
	item_table = {},
	items = 0,
	item_shortcuts = {
		"Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P",
		"A", "S", "D", "F", "G", "H", "J", "K", "L", "Del",
		"Z", "X", "C", "V", "B", "N", "M", ".", "Sym", "Enter",
	},
	is_enable_shortcut = true,

	item_height = 36,
	page = 1,

	on_select_callback = function() end,

	item_group = nil,
	page_info = nil,
}

function Menu:init()
	self.items = #self.item_table
	self.perpage = math.floor(self.height / self.item_height) - 2
	self.page = 1
	self.page_num = math.ceil(self.items / self.perpage)

	-- set up keyboard events
	self.key_events.Close = { {"Back"}, doc = "close menu" }
	self.key_events.Select = { {"Press"}, doc = "chose selected item" }
	self.key_events.NextPage = {
		{Input.group.PgFwd}, doc = "goto next page of the menu"
	}
	self.key_events.PrevPage = {
		{Input.group.PgBack}, doc = "goto previous page of the menu"
	}
	-- we won't catch presses to "Right"
	self.key_events.FocusRight = nil
	-- rather, we reserve that key for showing details
	self.key_events.ShowItemDetail = { {"Right"}, doc = "show item detail" }
	if self.is_enable_shortcut then
		self.key_events.SelectByShortCut = { {self.item_shortcuts} }
	end
	self.key_events.Select = { {"Press"}, doc = "select current menu item"}

	-- group for items
	self.item_group = VerticalGroup:new{}
	self.page_info = TextWidget:new{
		face = self.fface,
	}

	self[1] = CenterContainer:new{
		FrameContainer:new{
			background = 0,
			radius = math.floor(self.width/20),
			VerticalGroup:new{
				TextWidget:new{
					text = self.title,
					face = self.tface,
				},
				self.item_group,
				self.page_info,
			}, -- VerticalGroup
		}, -- FrameContainer
		dimen = {w = G_width, h = G_height},
	} -- CenterContainer

	self:_updateItems()
end

function Menu:_updateItems()
	self.layout = {}
	self.item_group:clear()

	for c = 1, self.perpage do
		local i = (self.page - 1) * self.perpage + c 
		if i <= self.items then
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
			item_tmp = MenuItem:new{
				text = self.item_table[i].text,
				face = self.cface,
				width = self.width - 14,
				height = self.item_height,
				shortcut = item_shortcut,
				shortcut_style = shortcut_style,
			}
			table.insert(self.item_group, item_tmp)
			table.insert(self.layout, {item_tmp})
			--self.last_shortcut = c
		end -- if i <= self.items
	end -- for c=1, self.perpage
	-- set focus to first menu item
	self.item_group[1]:onFocus()
	-- reset focus manager accordingly
	self.selected = { x = 1, y = 1 }
	-- update page information
	self.page_info.text = "page "..self.page.."/"..self.page_num
end

function Menu:onSelectByShortCut(_, keyevent)
	for k,v in ipairs(self.item_shortcuts) do
		if k > self.perpage then
			break
		elseif v == keyevent.key then
			local item = self.item_table[(self.page-1)*self.perpage+k]
			self.item_table = nil
			UIManager:close(self)
			self.on_select_callback(item)
			break 
		end
	end
	return true
end

function Menu:onNextPage()
	if self.page < self.page_num then
		self.page = self.page + 1
		self:_updateItems()
		UIManager:setDirty(self)
	end
	return true
end

function Menu:onPrevPage()
	if self.page > 1 then
		self.page = self.page - 1
		self:_updateItems()
		UIManager:setDirty(self)
	end
	return true
end

function Menu:onShowItemDetail()
	self.layout[self.selected.y][self.selected.x]:handleEvent(
		Event:new("ShowDetail")
	)
	return true
end

function Menu:onSelect()
	UIManager:close(self)
	self.on_select_callback(self.item_table[self.selected.y])
	return true
end

function Menu:onClose()
	UIManager:close(self)
	return true
end
