require "rendertext"
require "keys"
require "graphics"
require "font"
require "inputbox"
require "dialog"
require "readerchooser"

FileSearcher = {
	title_H = 40,	-- title height
	spacing = 36,	-- spacing between lines
	foot_H = 28,	-- foot height
	margin_H = 10,	-- horisontal margin

	-- state buffer
	dirs = {},
	files = {},
	result = {},
	items = 0,
	page = 0,
	current = 1,
	oldcurrent = 1,
	commands = nil,
}

function FileSearcher:readDir()
	self.dirs = {self.path}
	self.files = {}
	while #self.dirs ~= 0 do
		new_dirs = {}
		-- handle each dir
		for __, d in pairs(self.dirs) do
			-- handle files in d
			for f in lfs.dir(d) do
				local file_type = string.lower(string.match(f, ".+%.([^.]+)") or "")
				if lfs.attributes(d.."/"..f, "mode") == "directory" and f ~= "." and f~= ".." then
					table.insert(new_dirs, d.."/"..f)
				elseif ReaderChooser:getReaderByType(file_type) then
					file_entry = {dir=d, name=f,}
					table.insert(self.files, file_entry)
					--Debug("file:"..d.."/"..f)
				end
			end
		end
		self.dirs = new_dirs
	end
end

function FileSearcher:setPath(newPath)
	self.path = newPath
	self:readDir()
	self.items = #self.files
	--@TODO check none found  19.02 2012
	if self.items == 0 then
		return nil
	end
	self.page = 1
	self.current = 1
	return true
end

function FileSearcher:setSearchResult(keywords)
	self.result = {}
	if keywords == " " then -- one space to show all files
		self.result = self.files
	else
		for __,f in pairs(self.files) do
			if string.find(string.lower(f.name), string.lower(keywords)) then
				table.insert(self.result, f)
			end
		end
	end
	self.keywords = keywords
	self.items = #self.result
	self.page = 1
	self.current = 1
end

function FileSearcher:init(search_path)
	self:setPath(search_path or "/mnt/us/documents")
	self:addAllCommands()
	if not self.commands then self:addAllCommands() end
end

function FileSearcher:prevItem()
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

function FileSearcher:nextItem()
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

function FileSearcher:addAllCommands()
	self.commands = Commands:new{}
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
	self.commands:add(KEY_G, nil, "G",
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
	self.commands:add(KEY_L, nil, "L",
		"last documents",
		function(self)
			FileHistory:init()
			FileHistory:choose("")
			self.pagedirty = true
		end
	)
	self.commands:add(KEY_H, nil, "H",
		"show help page",
		function(self)
			HelpPage:show(0, G_height, self.commands)
			self.pagedirty = true
		end
	) 
	self.commands:add(KEY_FW_RIGHT, nil, "joypad right",
		"document details",
		function(self)
			local file_entry = self.result[self.perpage*(self.page-1)+self.current]
			FileInfo:show(file_entry.dir,file_entry.name)
			self.pagedirty = true
		end
	) 
	self.commands:add(KEY_S, nil, "S",
		"invoke search inputbox",
		function(self)
			local old_keywords = self.keywords
			self.keywords = InputBox:input(G_height - 100, 100, "Search:", old_keywords)
			if self.keywords then
				local old_data = self.result -- be sure that something is found, otherwise restore
				local old_page, old_current = self.page, self.current
				self:setSearchResult(self.keywords)
				if #self.result < 1 then
					InfoMessage:inform("No search hits ", DINFO_DELAY, 1, MSG_WARN)
					-- restoring the original data
					self.result = old_data
					self.items = #self.result
					self.page = old_page
					self.current = old_current
					self.keywords = old_keywords
				end
			else
				self.keywords = old_keywords
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
		"open selected item",
		function(self)
			local file_entry = self.result[self.perpage*(self.page-1)+self.current]
			file_full_path = file_entry.dir .. "/" .. file_entry.name

			openFile(file_full_path)
			--reset height and item index if screen has been rotated
			local item_no = self.perpage * (self.page - 1) + self.current
			self.perpage = math.floor(G_height / self.spacing) - 2
			self.current = item_no % self.perpage
			self.page = math.floor(item_no / self.perpage) + 1

			self.pagedirty = true
		end
	)
	self.commands:add(KEY_DEL, nil, "Del",
		"delete document",
		function(self)
			local pos = self.perpage*(self.page-1)+self.current
			local file_entry = self.result[pos]
			local file_to_del = file_entry.dir .. "/" .. file_entry.name
			if InfoMessage.InfoMethod[MSG_CONFIRM] == 0 then -- silent regime
				self:deleteFoundFile(file_to_del)
			else
				InfoMessage:inform("Press 'Y' to confirm ", DINFO_NODELAY, 0, MSG_CONFIRM)
				if ReturnKey() == KEY_Y then
					self:deleteFoundFile(file_to_del)
				end
			self.pagedirty = true
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

function FileSearcher:choose(keywords)
	self.perpage = math.floor(G_height / self.spacing) - 2
	self.pagedirty = true
	self.markerdirty = false

	-- if given keywords, set new result according to keywords.
	-- Otherwise, display the previous search result.
	if keywords then
		self:setSearchResult(keywords)
	end
	-- NuPogodi, 30.09.12: immediate quit (no redraw), if empty -- there is nothing to do in empty list anyway
	if #self.result < 1 then
		InfoMessage:inform("No search hits found ", DINFO_DELAY, 1, MSG_WARN)
		return nil
	end

	while true do
		local cface = Font:getFace("cfont", 22)
		local tface = Font:getFace("tfont", 25)
		local fface = Font:getFace("ffont", 16)

		if self.pagedirty then
			self.markerdirty = true
			fb.bb:paintRect(0, 0, G_width, G_height, 0)

			DrawTitle("Search Results for \'"..self.keywords.."\'".." ("..tostring(self.items).." hits)",self.margin_H,0,self.title_H,3,tface)
			-- draw results
			local c
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

function FileSearcher:deleteFoundFile(file_to_del)
	os.remove(file_to_del)
	os.remove(DocToHistory(file_to_del))
	-- NuPogodi, 02.10.12: remove file from self.files WITHOUT rescanning folders
	local i = 1
	while i <= #self.files and self.files[i].dir.."/"..self.files[i].name ~= file_to_del do
		i = i + 1
	end
	if i <= #self.files then
		table.remove(self.files, i)
		self.items = #self.files
	end
	i = self.current - 1 + (self.page-1)*self.perpage
	self.page = math.ceil(i/self.perpage)
	self.current = i - (self.page-1)*self.perpage
end
