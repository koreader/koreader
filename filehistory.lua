require "rendertext"
require "keys"
require "graphics"
require "font"
require "inputbox"
require "dialog"
require "filesearcher"
require "settings"

FileHistory = {
	-- title height
	title_H = 40,
	-- spacing between lines
	spacing = 36,
	-- foot height
	foot_H = 28,
	-- horisontal margin
	margin_H = 10,

	-- state buffer
	history_files = {},
	files = {},
	result = {},
	items = 0,
	page = 0,
	current = 1,
	oldcurrent = 1,
}

function FileHistory:init(history_path)
	if history_path then
		self:setPath(history_path)
	else
		self:setPath("./history")
	end
	self:addAllCommands()
end

function FileHistory:setPath(newPath)
	self.path = newPath
	self:readDir("-c ") 
	self.items = #self.files
	if self.items == 0 then
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
		file_entry = {dir=self.path, name=f}
		table.insert(self.history_files, file_entry)
		-- and corresponding path & file items
		file_entry = {dir=HistoryToPath(f), name=HistoryToName(f)}
		table.insert(self.files, file_entry)
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
	-- search among last documents
	self.commands:add(KEY_S, nil, "S",
		"search among files",
		function(self)
			old_keywords = self.keywords
			self.keywords = InputBox:input(G_height - 100, 100,
				"Search:", old_keywords)
			if self.keywords then
				self:setSearchResult(self.keywords)
			else
				self.keywords = old_keywords
			end
			self.pagedirty = true
		end
	)
	self.commands:add(KEY_L, nil, "L",
		"last documents",
		function(self)
			self:setSearchResult("")
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
	self.commands:add({KEY_FW_RIGHT, KEY_I}, nil, "joypad right",
		"document details",
		function(self)
			file_entry = self.result[self.perpage*(self.page-1)+self.current]
			FileInfo:show(file_entry.dir,file_entry.name)
			self.pagedirty = true
		end
	)
	self.commands:add(KEY_FW_UP, nil, "joypad up",
		"goto previous item",
		function(self)
			self:prevItem()
		end
	)
	self.commands:add(KEY_FW_DOWN, nil, "joypad down",
		"goto next item",
		function(self)
			self:nextItem()
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
	self.commands:add({KEY_F, KEY_AA}, nil, "F",
		"change font faces",
		function(self)
			Font:chooseFonts()
			self.pagedirty = true
		end
	)
	self.commands:add({KEY_ENTER, KEY_FW_PRESS}, nil, "Enter",
		"open selected item",
		function(self)
			if #self.result == 0 then
				showInfoMsgWithDelay("No files to open", 1500, 1)
				return
			end
			file_entry = self.result[self.perpage*(self.page-1)+self.current]
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
	self.commands:add({KEY_DEL}, nil, "Del",
		"delete history entry",
		function(self)
			file_entry = self.result[self.perpage*(self.page-1)+self.current]
			if not file_entry then return end
			local file_to_del = file_entry.dir .. "/" .. file_entry.name
			os.remove(DocToHistory(file_to_del))
			-- to avoid showing just deleted file
			self:init()
			self:setSearchResult(self.keywords)
			self.pagedirty = true
		end
	)
	self.commands:add({KEY_SPACE}, nil, "Space",
		"refresh page manually",
		function(self)
			self.pagedirty = true
		end
	)
	self.commands:add({KEY_BACK, KEY_HOME}, nil, "Back",
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

	self:setSearchResult(keywords)

	while true do
		local cface = Font:getFace("cfont", 22)
		local tface = Font:getFace("tfont", 25)
		local fface = Font:getFace("ffont", 16)

		if self.pagedirty then
			self.markerdirty = true
			fb.bb:paintRect(0, 0, G_width, G_height, 0)

			-- draw header
			local header = "Last Documents"
			if self.keywords ~= "" and self.keywords ~= " " then 
				--header = header .. " (filter: \'" .. string.upper(self.keywords) .. "\')"
				header = "Search Results for \'"..string.upper(self.keywords).."\'"
			end
			DrawTitle(header,self.margin_H,0,self.title_H,4,tface)
			
			-- draw found results
			local c
			if self.items == 0 then -- nothing found
				y = self.title_H + self.spacing * 2
				renderUtf8Text(fb.bb, self.margin_H, y, cface,
					"Sorry, no files found.", true)
				self.markerdirty = false
			else -- found something, draw it
				for c = 1, self.perpage do
					local i = (self.page - 1) * self.perpage + c
					if i <= self.items then
						y = self.title_H + (self.spacing * c) + 4
						local ftype = string.lower(string.match(self.result[i].name, ".+%.([^.]+)") or "")
						DrawFileItem(self.result[i].name,self.margin_H,y,ftype)
					end
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
