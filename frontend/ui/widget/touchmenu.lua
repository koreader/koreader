require "ui/widget/container"
require "ui/widget/group"
require "ui/widget/line"
require "ui/widget/iconbutton"


--[[
TouchMenuItem widget
--]]
TouchMenuItem = InputContainer:new{
	menu = nil,
	vertical_align = "center",
	item = nil,
	dimen = nil,
	face = Font:getFace("cfont", 22),
	show_parent = nil,
}

function TouchMenuItem:init()
	self.ges_events = {
		TapSelect = {
			GestureRange:new{
				ges = "tap",
				range = self.dimen,
			},
			doc = "Select Menu Item",
		},
	}

	self.item_frame = FrameContainer:new{
		width = self.dimen.w,
		bordersize = 0,
		color = 15,
		HorizontalGroup:new {
			align = "center",
			HorizontalSpan:new{ width = 10 },
			TextWidget:new{
				text = self.item.text,
				face = self.face,
			},
		},
	}
	self[1] = self.item_frame
end

function TouchMenuItem:onTapSelect(arg, ges)
	self.item_frame.invert = true
	UIManager:setDirty(self.show_parent, "partial")
	UIManager:scheduleIn(0.5, function()
		self.item_frame.invert = false
		UIManager:setDirty(self.show_parent, "partial")
	end)
	self.menu:onMenuSelect(self.item)
	return true
end


--[[
TouchMenuBar widget
--]]
TouchMenuBar = InputContainer:new{
	height = scaleByDPI(70),
	width = Screen:getWidth(),
	icons = {},
	-- touch menu that holds the bar, used for trigger repaint on icons
	show_parent = nil,
	menu = nil,
}

function TouchMenuBar:init()
	self.show_parent = self.show_parent or self

	self.dimen = Geom:new{
		w = self.width,
		h = self.height,
	}

	self.bar_icon_group = HorizontalGroup:new{}

	local icon_sep = LineWidget:new{
		dimen = Geom:new{
			w = scaleByDPI(2),
			h = self.height,
		}
	}

	local icon_span = HorizontalSpan:new{ width = scaleByDPI(20) }

	-- build up image widget for menu icon bar
	self.icon_widgets = {}
	-- the start_seg for first icon_widget should be 0
	-- we asign negative here to offset it in the loop
	start_seg = -icon_sep:getSize().w
	end_seg = start_seg
	for k, v in ipairs(self.icons) do
		local ib = IconButton:new{
			show_parent = self.show_parent,
			icon_file = v,
			callback = nil,
		}

		table.insert(self.icon_widgets, HorizontalGroup:new{
			icon_span,
			ib,
			icon_span,
		})

		-- we have to use local variable here for closure callback
		local _start_seg = end_seg + icon_sep:getSize().w
		local _end_seg = _start_seg + self.icon_widgets[k]:getSize().w

		if k == 1 then
			self.bar_sep = LineWidget:new{
				dimen = Geom:new{
					w = self.width,
					h = scaleByDPI(2),
				},
				empty_segments = {
					{
						s = _start_seg, e = _end_seg
					}
				},
			}
		end

		ib.callback = function()
			self.bar_sep.empty_segments = {
				{
					s = _start_seg, e = _end_seg
				}
			}
			self.menu:switchMenuTab(k)
		end

		table.insert(self.bar_icon_group, self.icon_widgets[k])
		table.insert(self.bar_icon_group, icon_sep)

		start_seg = _start_seg
		end_seg = _end_seg
	end

	self[1] = FrameContainer:new{
		bordersize = 0,
		padding = 0,
		VerticalGroup:new{
			align = "left",
			-- bar icons
			self.bar_icon_group,
			-- separate line
			self.bar_sep
		},
	}
end


--[[
TouchMenu widget
--]]
TouchMenu = InputContainer:new{
	tab_item_table = {},
	-- for returnning in multi-level menus
	item_table_stack = nil,
	item_table = nil,
	item_height = scaleByDPI(50),
	bordersize = scaleByDPI(2),
	padding = scaleByDPI(5),
	width = nil,
	height = nil,
	page = 1,
	max_per_page = 10,
	-- for UIManager:setDirty
	show_parent = nil,
	cur_tab = -1,
	close_callback = nil,
}

function TouchMenu:init()
	self.show_parent = self.show_parent or self
	if not self.close_callback then
		self.close_callback = function()
			UIManager:close(self.show_parent)
		end
	end

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
	self.ges_events.Swipe = {
		GestureRange:new{
			ges = "swipe",
			range = self.dimen,
		}
	}

	local icons = {}
	for _,v in ipairs(self.tab_item_table) do
		table.insert(icons, v.icon)
	end
	self.bar = TouchMenuBar:new{
		width = self.width - self.padding * 2 - self.bordersize * 2,
		icons = icons,
		show_parent = self.show_parent,
		menu = self,
	}

	self.item_group = VerticalGroup:new{
		align = "left",
	}

	self.footer_page = TextWidget:new{
		face = Font:getFace("ffont", 20),
		text = "",
	}
	self.footer = HorizontalGroup:new{
		IconButton:new{
			invert = true,
			icon_file = "resources/icons/appbar.chevron.up.png",
			show_parent = self.show_parent,
			callback = function()
				self:backToUpperMenu()
			end,
		},
		self.footer_page,
	}

	self[1] = FrameContainer:new{
		padding = self.padding,
		bordersize = self.bordersize,
		background = 0,
		-- menubar and footer will be inserted in
		-- item_group in updateItems
		self.item_group,
	}

	self:switchMenuTab(1)
	self:updateItems()
end

function TouchMenu:_recalculateDimen()
	self.dimen.w = self.width
	-- if height not given, dynamically calculate it
	if not self.height then
		self.dimen.h = (#self.item_table + 2) * self.item_height
						+ self.bar:getSize().h
	else
		self.dimen.h = self.height
	end
	if self.dimen.h > Screen:getHeight() then
		self.dimen.h = Screen:getHeight()
	end
	self.perpage = math.floor(self.dimen.h / self.item_height) - 2
	if self.perpage > self.max_per_page then
		self.perpage = self.max_per_page
	end
	self.page_num = math.ceil(#self.item_table / self.perpage)
end

function TouchMenu:updateItems()
	self:_recalculateDimen()
	self.item_group:clear()
	table.insert(self.item_group, self.bar)

	local item_width = self.dimen.w - self.padding*2 - self.bordersize*2

	for c = 1, self.perpage do
		-- calculate index in item_table
		local i = (self.page - 1) * self.perpage + c
		if i <= #self.item_table then
			local item_tmp = TouchMenuItem:new{
				item = self.item_table[i],
				menu = self,
				dimen = Geom:new{
					w = item_width,
					h = self.item_height,
				},
				show_parent = self.show_parent,
			}
			table.insert(self.item_group, item_tmp)
			-- insert split line
			if c ~= self.perpage then
				table.insert(self.item_group, HorizontalGroup:new{
					-- pad with spacing
					HorizontalSpan:new{width = scaleByDPI(10)},
					LineWidget:new{
						style = "dashed",
						dimen = Geom:new{
							w = item_width - 20,
							h = 1,
						}
					}
				})
			end
		else
			-- item not enough to fill the whole page, break out of loop
			--table.insert(self.item_group,
				--VerticalSpan:new{
					--width = self.item_height
				--})
			--break
		end -- if i <= self.items
	end -- for c=1, self.perpage

	table.insert(self.item_group, VerticalSpan:new{width = scaleByDPI(2)})
	table.insert(self.item_group, self.footer)
	self.footer_page.text = "Page "..self.page.."/"..self.page_num
	-- FIXME: this is a dirty hack to clear previous menus
	-- refert to issue #664
	UIManager.repaint_all = true
end

function TouchMenu:switchMenuTab(tab_num)
	if self.tab_item_table[tab_num].callback then
		self.tab_item_table[tab_num].callback()
	end
	if self.cur_tab ~= tab_num then
		-- it's like getting a new menu everytime we switch tab!
		self.page = 1
		-- clear item table stack
		self.item_table_stack = {}
		self.cur_tab = tab_num
		self.item_table = self.tab_item_table[tab_num]
		self:updateItems()
	end
end

function TouchMenu:backToUpperMenu()
	if #self.item_table_stack ~= 0 then
		self.item_table = table.remove(self.item_table_stack)
		self:updateItems()
	end
end

function TouchMenu:closeMenu()
	self.close_callback()
end

function TouchMenu:onNextPage()
	if self.page < self.page_num then
		self.page = self.page + 1
		self:updateItems()
	end
	return true
end

function TouchMenu:onPrevPage()
	if self.page > 1 then
		self.page = self.page - 1
		self:updateItems()
	end
	return true
end

function TouchMenu:onSwipe(arg, ges_ev)
	if ges_ev.direction == "west" then
		self:onNextPage()
	elseif ges_ev.direction == "east" then
		self:onPrevPage()
	end
end

function TouchMenu:onMenuSelect(item)
	if item.sub_item_table == nil then
		if item.callback then
			-- put stuff in scheduler so we can See
			-- the effect of inverted menu item
			UIManager:scheduleIn(0.1, function()
				self:closeMenu()
				item.callback()
			end)
		end
	else
		table.insert(self.item_table_stack, self.item_table)
		self.item_table = item.sub_item_table
		self:updateItems()
	end
	return true
end

function TouchMenu:onTapCloseAllMenus(arg, ges_ev)
	if ges_ev.pos:notIntersectWith(self.dimen) then
		self:closeMenu()
		return true
	end
end

