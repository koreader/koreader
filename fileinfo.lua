require "rendertext"
require "keys"
require "graphics"
require "font"
require "inputbox"
require "dialog"
require "settings"

FileInfo = {
	title_H = 40,	-- title height
	spacing = 36,	-- spacing between lines
	foot_H = 28,	-- foot height
	margin_H = 10,	-- horisontal margin
	-- state buffer
	pagedirty = true,
	result = {},
	commands = nil,
	items = 0,
	pathfile = "",
}

function FileInfo:FileCreated(fname, attr)
	return os.date("%d %b %Y, %H:%M:%S", lfs.attributes(fname,attr))
end

function FileInfo:FileSize(size)
	if size < 1024 then		return size.." Bytes"
	elseif size < 2^20 then	return string.format("%.2f", size/2^10).."KB ("..size.." Bytes)"
	else				return string.format("%.2f", size/2^20).."MB ("..size.." Bytes)"
	end
end

function FileInfo:init(path, fname)
	self.pathfile = path.."/"..fname
	-- add commands only once
	if not self.commands then
		self:addAllCommands()
	end

	local info_entry = {dir = "Name", name = fname}
	table.insert(self.result, info_entry)
	info_entry = {dir = "Path", name = path}
	table.insert(self.result, info_entry)

	info_entry = {dir = "Size", name = FileInfo:FileSize(lfs.attributes(self.pathfile, "size"))}
	table.insert(self.result, info_entry)
	-- size & filename of unzipped entry for zips 
	if string.lower(string.match(fname, ".+%.([^.]+)")) == "zip" then
		local outfile = "./data/zip_content"
		local l, s = 1
		os.execute("unzip -l \""..self.pathfile.."\" > "..outfile)
		if io.open(outfile, "r") then
			for lines in io.lines(outfile) do 
				if l == 4 then s = lines break else l = l + 1 end
			end
			if s then
				info_entry = { dir = "Unpacked", name = FileInfo:FileSize(tonumber(string.sub(s,1,11))) }
				table.insert(self.result, info_entry)
			end
			--[[ TODO: When the fileentry inside zips is encoded as ANSI (codes 128-255)
			any attempt to print such fileentry causes crash by drawing!!! When fileentries
			are encoded as UTF8, everything seems fine
			info_entry = { dir = "Content", name = string.sub(s,29,-1) }
			table.insert(self.result, info_entry) ]]
		end
	end

	info_entry = {dir = "Created", name = FileInfo:FileCreated(self.pathfile, "change")}
	table.insert(self.result, info_entry)
	info_entry = {dir = "Modified", name = FileInfo:FileCreated(self.pathfile, "modification")}
	table.insert(self.result, info_entry)

	-- if the document was already opened
	local history = DocToHistory(self.pathfile)
	local file, msg = io.open(history, "r")
	if not file then 
		info_entry = {dir = "Last Read", name = "Never"}
		table.insert(self.result, info_entry)
	else
		info_entry = {dir = "Last Read", name = FileInfo:FileCreated(history, "change")}
		table.insert(self.result, info_entry)
		local file_type = string.lower(string.match(self.pathfile, ".+%.([^.]+)"))
		local to_search, add, factor = "[\"last_percent\"]", "%", 100
		if ext:getReader(file_type) ~= CREReader then
			to_search = "[\"last_page\"]"
			add = " pages"
			factor = 1
		end
		for line in io.lines(history) do
			if string.match(line, "%b[]") == to_search then
				local cdc = tonumber(string.match(line, "%d+")) / factor
				info_entry = {dir = "Completed", name = string.format("%d", cdc)..add }
				table.insert(self.result, info_entry)
			end
		end
	end
	self.items = #self.result
end

function FileInfo:show(path, name)
	-- at first, one has to test whether the file still exists or not: necessary for last documents
	if not io.open(path.."/"..name,"r") then return nil end
	-- then goto main functions
	FileInfo:init(path,name)
	-- local variables
	local cface, lface, tface, fface, width, xrcol, c, dy, ev, keydef, ret_code
	while true do
		if self.pagedirty then
			-- refresh the fonts, if not yet defined or updated via 'F'
			cface = Font:getFace("cfont", 22)
			lface = Font:getFace("tfont", 22)
			tface = Font:getFace("tfont", 25)
			fface = Font:getFace("ffont", 16)
			-- drawing
			fb.bb:paintRect(0, 0, G_width, G_height, 0)
			DrawTitle("Document Information", self.margin_H, 0, self.title_H, 3, tface)
			-- now calculating xrcol-position for the right column
			width = 0
			for c = 1, self.items do
				width = math.max(sizeUtf8Text(0, G_width, lface, self.result[c].dir, true).x, width)
			end
			xrcol = self.margin_H + width + 25
			dy = 5 -- to store the y-position correction 'cause of the multiline drawing
			for c = 1, self.items do
				y = self.title_H + self.spacing * c + dy
				renderUtf8Text(fb.bb, self.margin_H, y, lface, self.result[c].dir, true)
				dy = dy + renderUtf8Multiline(fb.bb, xrcol, y, cface, self.result[c].name, true,
						G_width - self.margin_H - xrcol, 1.65).y - y
			end
			fb:refresh(0)
			self.pagedirty = false
		end
		-- waiting for user's commands
		ev = input.saveWaitForEvent()
		ev.code = adjustKeyEvents(ev)
		if ev.type == EV_KEY and ev.value ~= EVENT_VALUE_KEY_RELEASE then
			keydef = Keydef:new(ev.code, getKeyModifier())
			--Debug("key pressed: "..tostring(keydef))
			command = self.commands:getByKeydef(keydef)
			if command ~= nil then
				--Debug("command to execute: "..tostring(command))
				ret_code = command.func(self, keydef)
			else
				--Debug("command not found: "..tostring(command))
			end
			if ret_code == "break" then break end
		end -- if ev.type
	end -- while true
	-- clear results
	self.pagedirty = true
	result = {}
	return nil
end

function FileInfo:addAllCommands()
	self.commands = Commands:new{}
	self.commands:add({KEY_SPACE}, nil, "Space",
		"refresh page manually",
		function(self)
			self.pagedirty = true
		end
	)
	self.commands:add(KEY_H,nil,"H",
		"show help page",
		function(self)
			HelpPage:show(0, G_height, self.commands)
			self.pagedirty = true
		end
	)
	self.commands:add({KEY_F, KEY_AA}, nil, "F",
		"change font faces",
		function(self)
			Font:chooseFonts()
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
	self.commands:add({KEY_ENTER, KEY_FW_PRESS}, nil, "Enter",
		"open document",
		function(self)
			openFile(self.pathfile)
			self.pagedirty = true
		end
	)
	self.commands:add({KEY_BACK, KEY_FW_LEFT}, nil, "Back",
		"back",
		function(self)
			return "break"
		end
	)
end
