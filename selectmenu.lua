require "rendertext"
require "keys"
require "graphics"
require "font"
require "commands"

SelectMenu = {
	fsize = 22,	-- font for displaying item names
	tfsize = 25,	-- font for page title
	ffsize = 16,-- font for paging display

	title_H = 40,	-- title height
	spacing = 36,	-- spacing between lines
	foot_H = 27,	-- foot height
	margin_H = 10,	-- horisontal margin
	current_entry = 0,

	menu_title = "No Title",
	no_item_msg = "No items found.",
	item_array = {},
	items = 0,

	item_shortcuts = {
		"Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P",
		"A", "S", "D", "F", "G", "H", "J", "K", "L", "/",
		"Z", "X", "C", "V", "B", "N", "M", ".", "Sym", "Ent",
		},
	last_shortcut = 0,

	-- state buffer
	page = 1,
	current = 1,
	oldcurrent = 0,
	selected_item = nil,

	commands = nil,
	expandable = false, -- if true handle Right/Left FW selector keys
	deletable = false, -- if true handle Del key as a request to delete item
	-- note that currently expandable and deletable are mutually exclusive

	-- NuPogodi, 30.08.12: define font to render menu items
	own_glyph = 0,	-- render menu items with default "cfont"
	-- own_glyph = 1 => own glyphs for items like "Droid/DroidSans.ttf"
	-- own_glyph = 2 => own glyphs for Font.fontmap._index like "ffont", "tfont", etc.
}

function SelectMenu:new(o)
	o = o or {}
	setmetatable(o, self)
	self.__index = self
	o.items = #o.item_array
	o.page = 1
	o.current = 1
	o.oldcurrent = 0
	o.selected_item = nil
	-- increase spacing for DXG so we don't have more than 30 shortcuts
	if fb.bb:getHeight() == 1200 then
		o.spacing = 37
	end
	o:addAllCommands()
	return o
end

function SelectMenu:getItemIndexByShortCut(c, perpage)
	if c == nil then return end -- unused key
	for _k,_v in ipairs(self.item_shortcuts) do
		if _v == c and _k <= self.last_shortcut then
			return (perpage * (self.page - 1) + _k)
		end
	end
end

function SelectMenu:addAllCommands()
	self.commands = Commands:new{}

	self.commands:add(KEY_FW_UP, nil, "joypad up",
		"previous item",
		function(sm)
			if sm.current == 1 then
				if sm.page > 1 then
					sm.current = sm.perpage
					sm.page = sm.page - 1
					sm.pagedirty = true
				end
			else
				sm.current = sm.current - 1
				sm.markerdirty = true
			end
		end
	)
	self.commands:add(KEY_FW_DOWN, nil, "joypad down",
		"next item",
		function(sm)
			if sm.current == sm.perpage then
				if sm.page < (sm.items / sm.perpage) then
					sm.current = 1
					sm.page = sm.page + 1
					sm.pagedirty = true
				end
			else
				if sm.page ~= math.floor(sm.items / sm.perpage) + 1
					or sm.current + (sm.page - 1) * sm.perpage < sm.items then
					sm.current = sm.current + 1
					sm.markerdirty = true
				end
			end
		end
	)
	self.commands:add({KEY_PGFWD, KEY_LPGFWD}, nil, ">",
		"next page",
		function(sm)
			if sm.page < (sm.items / sm.perpage) then
				if sm.current + sm.page * sm.perpage > sm.items then
					sm.current = sm.items - sm.page * sm.perpage
				end
				sm.page = sm.page + 1
				sm.pagedirty = true
			else
				sm.current = sm.items - (sm.page - 1) * sm.perpage
				sm.markerdirty = true
			end
		end
	)
	self.commands:add({KEY_PGBCK, KEY_LPGBCK}, nil, "<",
		"previous page",
		function(sm)
			if sm.page > 1 then
				sm.page = sm.page - 1
				sm.pagedirty = true
			else
				sm.current = 1
				sm.markerdirty = true
			end
		end
	)
	self.commands:add(KEY_FW_PRESS, nil, "joypad center",
		"select item",
		function(sm)
			if sm.items == 0 then
				return "break"
			else
				self.selected_item = (sm.perpage * (sm.page - 1) + sm.current)
			end
		end
	)
	if self.deletable then
		self.commands:add(KEY_DEL, nil, "Del",
			"delete item",
			function(sm)
				self.selected_item = (sm.perpage * (sm.page - 1) + sm.current)
				return "delete"
			end
		)
	end
	if self.expandable then
		self.commands:add(KEY_FW_RIGHT, nil, "joypad right",
			"expand item",
			function(sm)
				self.selected_item = (sm.perpage * (sm.page - 1) + sm.current)
				return "expand"
			end
		)
		self.commands:add(KEY_FW_LEFT, nil, "joypad left",
			"collapse item",
			function(sm)
				self.selected_item = (sm.perpage * (sm.page - 1) + sm.current)
				return "collapse"
			end
		)
		self.commands:add(KEY_FW_RIGHT, MOD_SHIFT, "joypad right",
			"expand all subitems",
			function(sm)
				self.selected_item = (sm.perpage * (sm.page - 1) + sm.current)
				return "expand all"
			end
		)
	end
	local KEY_Q_to_P = {}
	for i = KEY_Q, KEY_P do 
		table.insert(KEY_Q_to_P, Keydef:new(i, nil, ""))
	end
	self.commands:addGroup("Q to P", KEY_Q_to_P, 
		"select item with Q to P key as shortcut",
		function(sm, keydef)
			sm.selected_item = sm:getItemIndexByShortCut(
				sm.item_shortcuts[ keydef.keycode - KEY_Q + 1 ], sm.perpage)
		end
	)
	local KEY_A_to_L = {}
	for i = KEY_A, KEY_L do 
		table.insert(KEY_A_to_L, Keydef:new(i, nil, ""))
	end
	self.commands:addGroup("A to L", KEY_A_to_L, 
		"select item with A to L key as shortcut",
		function(sm, keydef)
			sm.selected_item = sm:getItemIndexByShortCut(
				sm.item_shortcuts[ keydef.keycode - KEY_A + 11 ], sm.perpage)
		end
	)
	local KEY_Z_to_M = {}
	for i = KEY_Z, KEY_M do 
		table.insert(KEY_Z_to_M, Keydef:new(i, nil, ""))
	end
	self.commands:addGroup("Z to M", KEY_Z_to_M, 
		"select item with Z to M key as shortcut",
		function(sm, keydef)
			sm.selected_item = sm:getItemIndexByShortCut(
				sm.item_shortcuts[ keydef.keycode - KEY_Z + 21 ], sm.perpage)
		end
	)
	self.commands:add(KEY_SLASH, nil, "/",
		"select item with / key as shortcut",
		function(sm)
			sm.selected_item = sm:getItemIndexByShortCut("/", sm.perpage)
		end
	)
	self.commands:add(KEY_DOT, nil, ".",
		"select item with dot key as shortcut",
		function(sm)
			sm.selected_item = sm:getItemIndexByShortCut(".", sm.perpage)
		end
	)
	self.commands:add(KEY_SYM, nil, "Sym",
		"select item with Sym key as shortcut",
		function(sm)
			sm.selected_item = sm:getItemIndexByShortCut("Sym", sm.perpage)
		end
	)
	self.commands:add(KEY_ENTER, nil, "Enter",
		"select item with Enter key as shortcut",
		function(sm)
			sm.selected_item = sm:getItemIndexByShortCut("Ent", sm.perpage)
		end
	)
	self.commands:add(KEY_H,MOD_ALT,"H",
		"show help page",
		function(sm)
		HelpPage:show(0, G_height, sm.commands)
		sm.pagedirty = true
	end)
	self.commands:add({KEY_BACK,KEY_HOME}, nil, "Back, Home",
		"exit menu",
		function(sm)
			return "break"
		end
	)
end

function SelectMenu:clearCommands()
	self.commands = Commands:new{}

	self.commands:add({KEY_BACK,KEY_HOME}, nil, "Back, Home",
		"exit menu",
		function(sm)
			return "break"
		end)
end

------------------------------------------------
-- return the index of selected item
------------------------------------------------
function SelectMenu:choose(ypos, height)
	self.perpage = math.floor(height / self.spacing) - 2
	self.pagedirty = true
	self.markerdirty = false
	self.last_shortcut = 0

	self.current_entry = math.min(self.current_entry,self.items)

	-- now calculating the page & cursor
	self.page = math.floor(self.current_entry / self.perpage) + 1
	self.page = math.max(1, self.page)
	self.current = self.current_entry - (self.page - 1) * self.perpage + 1
	self.current = math.max(1, self.current)
	local own_face

	while true do
		local cface = Font:getFace("cfont", 22)
		local tface = Font:getFace("tfont", 25)
		local fface = Font:getFace("ffont", 16)
		local sface = Font:getFace("scfont", 22)
		
		local lx = self.margin_H + 40
		local fw = fb.bb:getWidth() - lx - self.margin_H
		
		if self.pagedirty then
			fb.bb:paintRect(0, ypos, fb.bb:getWidth(), height, 0)
			self.markerdirty = true
			-- draw menu title
			DrawTitle(self.menu_title,self.margin_H,0,self.title_H,3,tface)
			-- draw items
			fb.bb:paintRect(0, ypos + self.title_H + self.margin_H, fb.bb:getWidth(), height - self.title_H, 0)
			if self.items == 0 then
				y = ypos + self.title_H + (self.spacing * 2)
				renderUtf8Text(fb.bb, self.margin_H + 20, y, cface,
					"Oops...  Bad news for you:", true)
				y = y + self.spacing
				renderUtf8Text(fb.bb, self.margin_H + 20, y, cface,
					self.no_item_msg, true)
				self.markerdirty = false
				self:clearCommands()
			else
				local c
				for c = 1, self.perpage do
					local i = (self.page - 1) * self.perpage + c 
					if i <= self.items then
						y = ypos + self.title_H + (self.spacing * c) + 4

						-- paint shortcut indications
						if c <= 10 or c > 20 then
							blitbuffer.paintBorder(fb.bb, self.margin_H, y-22, 29, 29, 2, 15)
						else
							fb.bb:paintRect(self.margin_H, y-22, 29, 29, 3)
						end
						if self.item_shortcuts[c] ~= nil and 
							string.len(self.item_shortcuts[c]) == 3 then
							-- debug "Del", "Sym and "Ent"
							renderUtf8Text(fb.bb, self.margin_H + 3, y, fface,
								self.item_shortcuts[c], true)
						else
							renderUtf8Text(fb.bb, self.margin_H + 8, y, sface,
								self.item_shortcuts[c], true)
						end

						self.last_shortcut = c
						-- NuPogodi, 30.08.12: improved method to use own fontface for each menu item
						if self.own_glyph == 1 then -- Font.fontmap[_index], like "Droid/DroidSans.ttf"
							own_face = Font:getFace(self.item_array[i], 22)
						elseif self.own_glyph == 2 then -- Font.fontmap._index, like "[cfont] description"
							own_face = Font:getFace(string.sub(string.match(self.item_array[i],"%b[]"), 2, -2), 22)
						else
							own_face = cface
						end
						-- rendering menu items
						if sizeUtf8Text(lx,fb.bb:getWidth(),own_face,self.item_array[i],false).x < (fw - 10) then
							renderUtf8Text(fb.bb,lx,y,own_face,self.item_array[i],false)
						else
							local gapx = sizeUtf8Text(0,fb.bb:getWidth(),own_face,"...", true).x
							gapx = lx + renderUtf8TextWidth(fb.bb,lx,y,own_face,self.item_array[i],false,fw-gapx-15).x
							renderUtf8Text(fb.bb,gapx,y,own_face,"...",true)
						end
						-- end of changes (NuPogodi) 
					end -- if i <= self.items
				end -- for c=1, self.perpage
			end -- if self.items == 0

			local footer = "Page "..self.page.." of "..(math.ceil(self.items / self.perpage)).." - Press Alt-H for help"
			renderUtf8Text(fb.bb, self.margin_H, height-7, fface, footer, true)
		end

		if self.markerdirty then
			if not self.pagedirty then
				if self.oldcurrent > 0 then
					y = ypos + self.title_H + (self.spacing * self.oldcurrent) + 12
					fb.bb:paintRect( lx, y, fw, 3, 0)
					fb:refresh(1, lx, y, fw, 3)
				end
			end
			-- draw new marker line
			y = ypos + self.title_H + (self.spacing * self.current) + 12
			fb.bb:paintRect(lx, y, fw, 3, 15)
			if not self.pagedirty then
				fb:refresh(1, lx, y, fw, 3)
			end
			self.oldcurrent = self.current
			self.markerdirty = false
		end

		if self.pagedirty then
			fb:refresh(0, 0, ypos, fb.bb:getWidth(), height)
			self.pagedirty = false
		end

		local ev = input.saveWaitForEvent()
		ev.code = adjustKeyEvents(ev)
		if ev.type == EV_KEY and ev.value ~= EVENT_VALUE_KEY_RELEASE then
			keydef = Keydef:new(ev.code, getKeyModifier())
			Debug("key pressed: "..tostring(keydef))

			command = self.commands:getByKeydef(keydef)
			if command ~= nil then
				Debug("command to execute: "..tostring(command))
				ret_code = command.func(self, keydef)
			else
				Debug("command not found: "..tostring(command))
			end

			if ret_code == "break" then
				break
			end

			if self.selected_item ~= nil then
				if self.expandable then
					if ret_code == "expand" then
						return nil, self.selected_item
					elseif ret_code == "collapse" then
						return nil, -self.selected_item
					elseif ret_code == "expand all" then
						return nil, self.selected_item, "all"
					end
				elseif self.deletable and ret_code == "delete" then
						return nil, self.selected_item
				end
				Debug("# selected "..self.selected_item)
				return self.selected_item, self.item_array[self.selected_item]
			end
		end -- EOF if
	end -- EOF while
	return nil
end
