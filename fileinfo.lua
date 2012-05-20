require "rendertext"
require "keys"
require "graphics"
require "font"
require "inputbox"
require "dialog"
require "settings"
--require "extentions"

FileInfo = {
	-- title height
	title_H = 40,
	-- spacing between lines
	spacing = 36,
	-- foot height
	foot_H = 28,
	-- horisontal margin
	margin_H = 10,

	-- state buffer
	result = {},
	files = {},
	lcolumn_width = 0,
	items = 0,
	page = 1,
	current = 1,
	pathfile = "",
}

function FileInfo:FileCreated(fname,attr)
	return os.date("%d %b %Y, %H:%M:%S", lfs.attributes(fname,attr))
end

function FileInfo:FileSize(fname)
	local size = lfs.attributes(fname,"size")
	if size < 1024 then
		return size.." Bytes"
	elseif size < 1048576 then
		return string.format("%.2f", size/1024).."KB \("..size.." Bytes\)"
	else
		return string.format("%.2f", size/1048576).."MB \("..size.." Bytes\)"
	end
end

function FileInfo:init(path,fname)
	self.pathfile = path.."/"..fname
	self.result = {}
	self:addAllCommands()
	
	local info_entry = {dir = "Name", name = fname}
	table.insert(self.result, info_entry)
	info_entry = {dir = "Path", name = path}
	table.insert(self.result, info_entry)
	info_entry = {dir = "Size", name = FileInfo:FileSize(self.pathfile)}
	table.insert(self.result, info_entry)
	-- empty line
	--info_entry = {dir = " ", name = " "}
	--table.insert(self.result, info_entry)
	info_entry = {dir = "Created", name = FileInfo:FileCreated(self.pathfile,"change")}
	table.insert(self.result, info_entry)
	info_entry = {dir = "Modified", name = FileInfo:FileCreated(self.pathfile,"modification")}
	table.insert(self.result, info_entry)
	
	-- if the document was already opened
	local history = DocToHistory(self.pathfile)
	local file, msg = io.open(history,"r")
	if not file then 
		info_entry = {dir = "Last Read", name = "Never"}
		table.insert(self.result, info_entry)
	else
		info_entry = {dir = "Last Read", name = FileInfo:FileCreated(history,"change")}
		table.insert(self.result, info_entry)
		local file_type = string.lower(string.match(self.pathfile, ".+%.([^.]+)"))
		local to_search, add, factor = "\[\"last_percent\"\]", "\%", 100
		if ext:getReader(file_type) ~= CREReader then
			to_search = "\[\"last_page\"\]"
			add = " pages"
			factor = 1
		end
		for line in io.lines(history) do
			if string.match(line,"%b[]") == to_search then
				local cdc = tonumber(string.match(line, "%d+")) / factor
				info_entry = {dir = "Completed", name = string.format("%d",cdc)..add }
				table.insert(self.result, info_entry)
			end
		end
	end
	
	self.items = #self.result
	-- now calculating the horizontal space for left column
	local tw, width
	for i = 1, self.items do
		tw = TextWidget:new({text = self.result[i].dir, face = Font:getFace("tfont", 22)})
		width = tw:getSize().w
		if width > self.lcolumn_width then self.lcolumn_width = width end
		tw:free()
	end
end

function FileInfo:show(path,name)
	-- at first, one has to test whether the file still exists or not
	-- it's necessary for last documents
	if not io.open(path.."/"..name,"r") then return nil end
	-- then goto main functions
		self.perpage = math.floor(G_height / self.spacing) - 2
	self.pagedirty = true
	self.markerdirty = false
	FileInfo:init(path,name)


	while true do
		local cface = Font:getFace("cfont", 22)
		local lface = Font:getFace("tfont", 22)
		local tface = Font:getFace("tfont", 25)
		local fface = Font:getFace("ffont", 16)

		if self.pagedirty then
			self.markerdirty = true
			-- gap between title rectangle left & left text drawing point
			local xgap = 10
			fb.bb:paintRect(0, 0, G_width, G_height, 0)
			-- draw menu title
			DrawTitle("Document Information",self.margin_H,0,self.title_H,3,tface)
			local c
			-- position of left column
			local x1 = self.margin_H + xgap
			-- position of right column + its width + a small gap between columns
			local x2 = x1 + self.lcolumn_width + 15
			-- y-position correction because of the multiline drawing 
			local dy = 5
			for c = 1, self.perpage do
				local i = (self.page - 1) * self.perpage + c
				if i <= self.items then
					y = self.title_H + self.spacing * c + dy
					renderUtf8Text(fb.bb, x1, y, lface, self.result[i].dir, true)
					-- set interline spacing = 1.65 of the char height 
					-- or directly in pixels (if it exceeds 5)
					dy = dy + renderUtf8Multiline(fb.bb, x2, y, cface, self.result[i].name, true,
						G_width - self.margin_H - x2 - xgap, 1.65).y - y
				end
			end
			-- draw footer
			all_page = math.ceil(self.items/self.perpage)
			DrawFooter("Page "..self.page.." of "..all_page,fface,self.foot_H)
		end
		
--[[	-- may be used in future for selecting some of displayed items	
		if self.markerdirty then
			if not self.pagedirty then
				if self.oldcurrent > 0 then
					y = self.title_H + (self.spacing * self.oldcurrent) + 12
					fb.bb:paintRect(self.margin_H, y, G_width - 2 * self.margin_H, 3, 15)
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
		end ]]

		if self.pagedirty then
			fb:refresh(0)
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

			if ret_code == "break" then break end

			if self.selected_item ~= nil then
				debug("# selected "..self.selected_item)
				return self.selected_item
			end
		end -- if
	end -- while true
	return nil
end

function FileInfo:addAllCommands()
	self.commands = Commands:new{}
	-- show help page
	self.commands:add(KEY_H,nil,"H",
		"show help page",
		function(self)
			HelpPage:show(0, G_height, self.commands)
			self.pagedirty = true
		end
	) 
	-- make screenshot
	self.commands:add(KEY_P, MOD_SHIFT, "P",
		"make screenshot",
		function(self)
			Screen:screenshot()
		end
	) 
	-- recent documents
	self.commands:add(KEY_L, nil, "L",
		"last documents",
		function(self)
			FileHistory:init()
			FileHistory:choose("")
			self.pagedirty = true
		end
	) 
	-- fonts 
	self.commands:add({KEY_F, KEY_AA}, nil, "F",
		"font menu",
		function(self)
			-- NuPogodi, 18.05.12: define the number of the current font in face_list 
			local item_no = 0
			local face_list = Font:getFontList() 
			while face_list[item_no] ~= Font.fontmap.cfont and item_no < #face_list do 
				item_no = item_no + 1 
			end
				
			local fonts_menu = SelectMenu:new{
				menu_title = "Fonts Menu",
				item_array = face_list,
				-- NuPogodi, 18.05.12: define selected item
				current_entry = item_no - 1,
				}
			local re, font = fonts_menu:choose(0, G_height)
			if re then
				Font.fontmap["cfont"] = font
				Font:update()
			end
			self.pagedirty = true
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
	self.commands:add({KEY_ENTER, KEY_FW_PRESS}, nil, "Enter",
		"open document",
		function(self)
			openFile(self.pathfile)
			self.pagedirty = true
		end
	)
	self.commands:add({KEY_BACK, KEY_HOME, KEY_FW_LEFT}, nil, "Back",
		"back",
		function(self)
			return "break"
		end
	)
	self.commands:add({KEY_SPACE}, nil, "Space",
		"refresh page manually",
		function(self)
			self.pagedirty = true
		end
	)
--[[	self.commands:add({KEY_B}, nil, "B",
		"file browser",
		function(self)
			--FileChooser:setPath(".")
			FileChooser:choose(0, G_height)
			self.pagedirty = true
		end
	)]]
end
