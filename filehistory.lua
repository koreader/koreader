require "rendertext"
require "keys"
require "graphics"
require "font"
require "inputbox"
require "dialog"
require "filesearcher"
require "settings"
require "dialog"

FileHistory = {
	title_H = 40,	-- title height
	spacing = 36,	-- spacing between lines
	foot_H = 28,	-- foot height
	margin_H = 10,	-- horisontal margin

	-- state buffer
	history_files = {},
	files = {},
	result = {},
	items = 0,
	page = 0,
	current = 1,
	oldcurrent = 1,
	commands = nil,
}

function FileHistory:init(history_path)
	self:setPath("history")
	-- to initialize only once
	if not self.commands then self:addAllCommands() end
end

function FileHistory:setPath(newPath)
	self.path = newPath
	self:readDir("-c ") 
	self.items = #self.files
	if self.items == 1 then
		return nil
	end
	self.page = 1
	self.current = 1
	return true
end

function FileHistory:readDir(order_criteria)
	self.history_files = {}
	self.files = {}
	local p = io.popen("ls "..order_criteria.."-1 "..self.path)
	for f in p:lines() do
		-- insert history files
		table.insert(self.history_files, {dir=self.path, name=f})
		-- and corresponding path & file items
		table.insert(self.files, {dir=HistoryToPath(f), name=HistoryToName(f)})
	end
	p:close()
end

function FileHistory:setSearchResult(keywords)
	self.result = {}
	if keywords == "" or keywords == " " then
		-- show all history
		self.result = self.files
	else 
		-- select history files with keywords in the filename
		for __,f in pairs(self.files) do
			if string.find(string.lower(f.name), keywords) then
				table.insert(self.result,f)
			end
		end
	end
	self.keywords = keywords
	self.items = #self.result
	self.page = 1
	self.current = 1
	return self.items
end

function FileHistory:prevItem()
	if self.current == 1 then
		if self.page > 1 then
			self.current = self.perpage
			self.page = self.page - 1
			self.pagedirty = true
		end
	else
		self.current = self.current - 1
		self.markerdirty = true
	end
end

function FileHistory:nextItem()
	if self.current == self.perpage then
		if self.page < (self.items / self.perpage) then
			self.current = 1
			self.page = self.page + 1
			self.pagedirty = true
		end
	else
		if self.page ~= math.floor(self.items / self.perpage) + 1
			or self.current + (self.page-1)*self.perpage < self.items then
			self.current = self.current + 1
			self.markerdirty = true
		end
	end
end

function FileHistory:addAllCommands()
	self.commands = Commands:new{}
	self.commands:add(KEY_H, nil, "H",
		"show help page",
		function(self)
			HelpPage:show(0, G_height, self.commands)
			self.pagedirty = true
		end
	)
	self.commands:add(KEY_FW_UP, nil, "joypad up",
		"previous item",
		function(self)
			self:prevItem()
		end
	)
	self.commands:add(KEY_FW_DOWN, nil, "joypad down",
		"next item",
		function(self)
			self:nextItem()
		end
	)
	-- NuPogodi, 01.10.12: fast jumps to items at positions 10, 20, .. 90, 0% within the list
	local numeric_keydefs, i = {}
	for i=1, 10 do numeric_keydefs[i]=Keydef:new(KEY_1+i-1, nil, tostring(i%10)) end
	self.commands:addGroup("[1, 2 .. 9, 0]", numeric_keydefs,
		"item at position 0%, 10% .. 90%, 100%",
		function(self)
			local target_item = math.ceil(self.items * (keydef.keycode-KEY_1) / 9)
			self.current, self.page, self.markerdirty, self.pagedirty = 
				gotoTargetItem(target_item, self.items, self.current, self.page, self.perpage)
		end
	)
	self.commands:add({KEY_PGFWD, KEY_LPGFWD}, nil, ">",
		"next page",
		function(self)
			if self.page < (self.items / self.perpage) then
				if self.current + self.page*self.perpage > self.items then
					self.current = self.items - self.page*self.perpage
				end
				self.page = self.page + 1
				self.pagedirty = true
			else
				self.current = self.items - (self.page-1)*self.perpage
				self.markerdirty = true
			end
		end
	)
	self.commands:add({KEY_PGBCK, KEY_LPGBCK}, nil, "<",
		"previous page",
		function(self)
			if self.page > 1 then
				self.page = self.page - 1
				self.pagedirty = true
			else
				self.current = 1
				self.markerdirty = true
			end
		end
	)
	self.commands:add(KEY_G, nil, "G", -- NuPogodi, 01.10.12: goto page No.
		"goto page",
		function(self)
			local n = math.ceil(self.items / self.perpage)
			local page = NumInputBox:input(G_height-100, 100, "Page:", "current page "..self.page.." of "..n, true)
			if pcall(function () page = math.floor(page) end) -- convert string to number
			and page ~= self.page and page > 0 and page <= n then
				self.page = page
				if self.current + (page-1)*self.perpage > self.items then
					self.current = self.items - (page-1)*self.perpage
				end
			end
			self.pagedirty = true
		end
	)
	self.commands:add(KEY_FW_RIGHT, nil, "joypad right",
		"document details",
		function(self)
			local file_entry = self.result[self.perpage*(self.page-1)+self.current]
			if file_entry.name == ".." then 
				warningUnsupportedFunction()
				return
			end -- do not show details
			FileInfo:show(file_entry.dir,file_entry.name)
			self.pagedirty = true
		end
	)
	self.commands:add(KEY_S, nil, "S",
		"invoke search inputbox",
		function(self)
			-- NuPogodi, 30.09.12: be sure that something is found
			local old_keywords = self.keywords
			local old_data = self.result
			local old_page, old_current = self.page, self.current
			self.keywords = InputBox:input(G_height - 100, 100, "Search:", old_keywords)
			if self.keywords then
				self:setSearchResult(self.keywords)
			else
				self.keywords = old_keywords
			end
			if #self.result < 1 then
				InfoMessage:inform("No search hits ", 2000, 1, MSG_WARN,
					"The search has given no results")
				-- restoring the original data
				self.result = old_data
				self.items = #self.result
				self.keywords = old_keywords
				self.page = old_page
				self.current = old_current
			end
			self.pagedirty = true
		end
	)
	self.commands:add({KEY_F, KEY_AA}, nil, "F, Aa",
		"change font faces",
		function(self)
			Font:chooseFonts()
			self.pagedirty = true
		end
	)
	self.commands:add({KEY_ENTER, KEY_FW_PRESS}, nil, "Enter",
		"open selected document",
		function(self)
			local file_entry = self.result[self.perpage*(self.page-1)+self.current]
			file_full_path = file_entry.dir .. "/" .. file_entry.name
			if FileExists(file_full_path) then
				openFile(file_full_path)
				--reset height and item index if screen has been rotated
				local item_no = self.perpage * (self.page - 1) + self.current
				self.perpage = math.floor(G_height / self.spacing) - 2
				self.current = item_no % self.perpage
				self.page = math.floor(item_no / self.perpage) + 1
				self.pagedirty = true
			else
				InfoMessage:inform("File does not exist ", 2000, 1, MSG_ERROR)
			end
		end
	)
	self.commands:add(KEY_DEL, nil, "Del",
		"delete history entry",
		function(self)
			local file_entry = self.result[self.perpage*(self.page-1)+self.current]
			local file_to_del = file_entry.dir .. "/" .. file_entry.name
			if InfoMessage.InfoMethod[MSG_CONFIRM] == 0 then -- silent regime
				os.remove(DocToHistory(file_to_del))
				self:init()
				self:setSearchResult(self.keywords)
			else
				InfoMessage:inform("Press 'Y' to confirm ", nil, 0, MSG_CONFIRM,
					"Please, press key Y to delete the book history")
				if FileChooser:ReturnKey() == KEY_Y then
					os.remove(DocToHistory(file_to_del))
					self:init()
					self:setSearchResult(self.keywords)
				end
			end
			self.pagedirty = true
			if self.items == 0 then
				return "break"
			end
		end
	)
	self.commands:add(KEY_SPACE, nil, "Space",
		"refresh page manually",
		function(self)
			self.pagedirty = true
		end
	)
	self.commands:add(KEY_BACK, nil, "Back",
		"back",
		function(self)
			return "break"
		end
	)
end

function FileHistory:choose(keywords)
	self.perpage = math.floor(G_height / self.spacing) - 2
	self.pagedirty = true
	self.markerdirty = false

	-- NuPogodi, 30.09.12: immediate quit (no redraw), if empty
	if self:setSearchResult(keywords) < 1 then
		InfoMessage:inform("No reading history ", 2000, 1, MSG_WARN, "The reading history is empty!")
		return nil
	end

	while true do
		local cface = Font:getFace("cfont", 22)
		local tface = Font:getFace("tfont", 25)
		local fface = Font:getFace("ffont", 16)

		if self.pagedirty then
			self.markerdirty = true
			fb.bb:paintRect(0, 0, G_width, G_height, 0)
			-- draw header
			local header = "Last Documents ("..tostring(self.items).." items)"
			if self.keywords ~= "" and self.keywords ~= " " then 
				--header = header .. " (filter: \'" .. string.upper(self.keywords) .. "\')"
				header = "Search Results for \'"..string.upper(self.keywords).."\'"
			end
			DrawTitle(header,self.margin_H,0,self.title_H,3,tface)
			-- draw found results
			for c = 1, self.perpage do
				local i = (self.page - 1) * self.perpage + c
				if i <= self.items then
					y = self.title_H + (self.spacing * c) + 4
					local ftype = string.lower(string.match(self.result[i].name, ".+%.([^.]+)") or "")
					DrawFileItem(self.result[i].name,self.margin_H,y,ftype)
				end
			end
			-- draw footer
			all_page = math.ceil(self.items/self.perpage)
			DrawFooter("Page "..self.page.." of "..all_page,fface,self.foot_H)
		end

		if self.markerdirty then
			if not self.pagedirty then
				if self.oldcurrent > 0 then
					y = self.title_H + (self.spacing * self.oldcurrent) + 12
					fb.bb:paintRect(self.margin_H, y, G_width - 2 * self.margin_H, 3, 0)
					fb:refresh(1, self.margin_H, y, G_width - 2 * self.margin_H, 3)
				end
			end
			-- draw new marker line
			y = self.title_H + (self.spacing * self.current) + 12
			fb.bb:paintRect(self.margin_H, y, G_width - 2 * self.margin_H, 3, 15)
			if not self.pagedirty then
				fb:refresh(1, self.margin_H, y, G_width - 2 * self.margin_H, 3)
			end
			self.oldcurrent = self.current
			self.markerdirty = false
		end

		if self.pagedirty then
			fb:refresh(0)
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
				Debug("# selected "..self.selected_item)
				return self.selected_item
			end
		end -- if
	end -- while true
	return nil
end
