require "rendertext"
require "keys"
require "graphics"
require "font"
require "commands"

SelectMenu = {
	-- font for displaying item names
	fsize = 22,
	-- font for page title
	tfsize = 25,
	-- font for paging display
	ffsize = 16,
	-- font for item shortcut
	sface = Font:getFace("scfont", 22),

	-- title height
	title_H = 40,
	-- spacing between lines
	spacing = 36,
	-- foot height
	foot_H = 27,

	menu_title = "No Title",
	no_item_msg = "No items found.",
	item_array = {},
	items = 0,

	item_shortcuts = {
		"Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P",
		"A", "S", "D", "F", "G", "H", "J", "K", "L", "Del",
		"Z", "X", "C", "V", "B", "N", "M", ".", "Sym", "Ent",
		},
	last_shortcut = 0,

	-- state buffer
	page = 1,
	current = 1,
	oldcurrent = 0,
	selected_item = nil,

	commands = nil,
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

	self.commands:add(KEY_FW_UP, nil, "",
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
	self.commands:add(KEY_FW_DOWN, nil, "",
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
	self.commands:add({KEY_PGFWD, KEY_LPGFWD}, nil, "",
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
	self.commands:add({KEY_PGBCK, KEY_LPGBCK}, nil, "",
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
	self.commands:add(KEY_FW_PRESS, nil, "",
		"select menu item",
		function(sm)
			if sm.items == 0 then
				return "break"
			else
				self.selected_item = (sm.perpage * (sm.page - 1) + sm.current)
			end
		end
	)
	local KEY_Q_to_P = {}
	for i = KEY_Q, KEY_P do 
		table.insert(KEY_Q_to_P, Keydef:new(i, nil, ""))
	end
	self.commands:addGroup("Q to P", KEY_Q_to_P, 
		"Select menu item with Q to E key as shortcut",
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
		"Select menu item with A to L key as shortcut",
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
		"Select menu item with Z to M key as shortcut",
		function(sm, keydef)
			sm.selected_item = sm:getItemIndexByShortCut(
				sm.item_shortcuts[ keydef.keycode - KEY_Z + 21 ], sm.perpage)
		end
	)
	self.commands:add(KEY_DEL, nil, "",
		"Select menu item with del key as shortcut",
		function(sm)
			sm.selected_item = sm:getItemIndexByShortCut("Del", sm.perpage)
		end
	)
	self.commands:add(KEY_DOT, nil, "",
		"Select menu item with dot key as shortcut",
		function(sm)
			sm.selected_item = sm:getItemIndexByShortCut(".", sm.perpage)
		end
	)
	self.commands:add({KEY_SYM, KEY_SLASH}, nil, "",
		"Select menu item with sym/slash key as shortcut",
		function(sm)
		-- DXG has slash after dot
			sm.selected_item = sm:getItemIndexByShortCut("Sym", sm.perpage)
		end
	)
	self.commands:add(KEY_ENTER, nil, "",
		"Select menu item with enter key as shortcut",
		function(sm)
			sm.selected_item = sm:getItemIndexByShortCut("Ent", sm.perpage)
		end
	)
	self.commands:add(KEY_BACK, nil, "",
		"Exit menu",
		function(sm)
			return "break"
		end
	)
end

function SelectMenu:clearCommands()
	self.commands = Commands:new{}

	self.commands:add(KEY_BACK, nil, "",
		"Exit menu",
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

	while true do
		local cface = Font:getFace("cfont", 22)
		local tface = Font:getFace("tfont", 25)
		local fface = Font:getFace("ffont", 16)

		if self.pagedirty then
			self.markerdirty = true
			-- draw menu title
			fb.bb:paintRect(0, ypos, fb.bb:getWidth(), self.title_H + 10, 0)
			fb.bb:paintRect(10, ypos + 10, fb.bb:getWidth() - 20, self.title_H, 5)

			local x = 20
			local y = ypos + self.title_H
			renderUtf8Text(fb.bb, x, y, tface, self.menu_title, true)

			-- draw items
			fb.bb:paintRect(0, ypos + self.title_H + 10, fb.bb:getWidth(), height - self.title_H, 0)
			if self.items == 0 then
				y = ypos + self.title_H + (self.spacing * 2)
				renderUtf8Text(fb.bb, 30, y, cface,
					"Oops...  Bad news for you:", true)
				y = y + self.spacing
				renderUtf8Text(fb.bb, 30, y, cface,
					self.no_item_msg, true)
				self.markerdirty = false
				self:clearCommands()
			else
				local c
				for c = 1, self.perpage do
					local i = (self.page - 1) * self.perpage + c 
					if i <= self.items then
						y = ypos + self.title_H + (self.spacing * c)

						-- paint shortcut indications
						if c <= 10 or c > 20 then
							blitbuffer.paintBorder(fb.bb, 10, y-22, 29, 29, 2, 15)
						else
							fb.bb:paintRect(10, y-22, 29, 29, 3)
						end
						if self.item_shortcuts[c] ~= nil and 
							string.len(self.item_shortcuts[c]) == 3 then
							-- debug "Del", "Sym and "Ent"
							renderUtf8Text(fb.bb, 13, y, fface,
								self.item_shortcuts[c], true)
						else
							renderUtf8Text(fb.bb, 18, y, self.sface,
								self.item_shortcuts[c], true)
						end

						self.last_shortcut = c

						renderUtf8Text(fb.bb, 50, y, cface,
							self.item_array[i], true)
					end -- if i <= self.items
				end -- for c=1, self.perpage
			end -- if self.items == 0

			-- draw footer
			y = ypos + self.title_H + (self.spacing * self.perpage)
				+ self.foot_H + 5
			x = (fb.bb:getWidth() / 2) - 50
			renderUtf8Text(fb.bb, x, y, fface,
				"Page "..self.page.." of "..
				(math.ceil(self.items / self.perpage)), true)
		end

		if self.markerdirty then
			if not self.pagedirty then
				if self.oldcurrent > 0 then
					y = ypos + self.title_H + (self.spacing * self.oldcurrent) + 8
					fb.bb:paintRect(45, y, fb.bb:getWidth() - 60, 3, 0)
					fb:refresh(1, 45, y, fb.bb:getWidth() - 60, 3)
				end
			end
			-- draw new marker line
			y = ypos + self.title_H + (self.spacing * self.current) + 8
			fb.bb:paintRect(45, y, fb.bb:getWidth() - 60, 3, 15)
			if not self.pagedirty then
				fb:refresh(1, 45, y, fb.bb:getWidth() - 60, 3)
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
			debug("key pressed: "..tostring(keydef))

			command = self.commands:getByKeydef(keydef)
			if command ~= nil then
				debug("command to execute: "..tostring(command))
				ret_code = command.func(self, keydef)
			else
				debug("command not found: "..tostring(command))
			end

			if ret_code == "break" then
				break
			end

			if self.selected_item ~= nil then
				debug("# selected "..self.selected_item)
				return self.selected_item, self.item_array[self.selected_item]
			end
		end -- EOF if
	end -- EOF while
	return nil
end
