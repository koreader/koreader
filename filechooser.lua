require "rendertext"
require "keys"
require "graphics"
require "font"
require "filesearcher"
require "filehistory"
require "fileinfo"
require "inputbox"
require "selectmenu"
require "dialog"
require "extentions"

FileChooser = {
	-- title height
	title_H = 40,
	-- spacing between lines
	spacing = 36,
	-- foot height
	foot_H = 28,
	-- horisontal margin
	margin_H = 10,

	-- state buffer
	dirs = nil,
	files = nil,
	items = 0,
	path = "",
	page = 1,
	current = 1,
	oldcurrent = 0,
	exception_message = nil,
	-- NuPogodi, 20.05.12: added new parameters to make helppage available
	pagedirty = true,
	markerdirty = false,
	perpage,
	clipboard = lfs.currentdir() .. "/clipboard", -- NO finishing slash
}

function getProperTitleLength(txt,font_face,max_width)
	local tw = TextWidget:new({ text = txt, face = font_face})
	-- 1st approximation for a point where to start title
	local n = math.floor(string.len(txt) * (1 - max_width / tw:getSize().w)) - 2
	n = math.max(n, 1)
	while tw:getSize().w >= max_width do
		tw:free()
		tw = TextWidget:new({ text = string.sub(txt,n,-1), face = font_face})
		n = n + 1
	end
	return string.sub(txt,n-1,-1)
end

function BatteryLevel()
	local fn, battery = "/tmp/kindle-battery-info", "?"
	-- NuPogodi, 18.05.12: This command seems to work even without Amazon Kindle framework 
	os.execute("(gasgauge-info ".."-s) ".."> "..fn)
	if io.open(fn,"r") then
		for lines in io.lines(fn) do battery = " " .. lines end
	else
		battery = ""
	end
	return battery
end

function DrawTitle(text,lmargin,y,height,color,font_face)
	-- radius for round corners
	local r = 6
	-- redefine to ignore the input for background color
	color = 3
	fb.bb:paintRect(1, 1, fb.bb:getWidth() - 2, height - r, color)
	blitbuffer.paintBorder(fb.bb, 1, height/2, fb.bb:getWidth() - 2, height/2, height/2, color, r)
	-- to have a horisontal gap between text & background rectangle
	t = BatteryLevel() .. os.date(" %H:%M")
	local tw = TextWidget:new({ text = t, face = font_face})
	twidth = tw:getSize().w
	renderUtf8Text(fb.bb, fb.bb:getWidth()-twidth-lmargin, height-10, font_face, t, true)
	tw:free()

	tw = TextWidget:new({ text = text, face = font_face})
	local max_width = fb.bb:getWidth() - 2*lmargin - twidth
	if tw:getSize().w < max_width then
		renderUtf8Text(fb.bb, lmargin, height-10, font_face, text, true)
	else
		local w = renderUtf8Text(fb.bb, lmargin, height-10, font_face, "...", true)
		local txt = getProperTitleLength(text, font_face, max_width-w)
		renderUtf8Text(fb.bb, w+lmargin, height-10, font_face, txt, true)
	end
	tw:free()
end

function DrawFooter(text,font_face,h)
	local y = G_height - 7
	local x = (G_width / 2) - 50
	renderUtf8Text(fb.bb, x, y, font_face, text, true)
end

function DrawFileItem(name,x,y,image)
	-- define icon file for
	if name == ".." then image = "upfolder" end
	local fn = "./resources/"..image..".png"
	-- check whether the icon file exists or not
	if not io.open(fn, "r") then fn = "./resources/other.png" end
	local iw = ImageWidget:new({ file = fn })
	iw:paintTo(fb.bb, x, y - iw:getSize().h + 1)
	-- then drawing filenames
	local cface = Font:getFace("cfont", 22)
	local xleft = x + iw:getSize().w + 9 -- the gap between icon & filename
	local width = fb.bb:getWidth() - xleft - x
	-- now printing the name
	if sizeUtf8Text(xleft, fb.bb:getWidth() - x, cface, name, true).x < width then
		renderUtf8Text(fb.bb, xleft, y, cface, name, true)
	else 
		local lgap = sizeUtf8Text(0, width, cface, " ...", true).x
		local handle = renderUtf8TextWidth(fb.bb, xleft, y, cface, name, true, width - lgap - x)
		renderUtf8Text(fb.bb, handle.x + lgap + x, y, cface, " ...", true)
	end
	iw:free()
end
-- end of old NuPogodi's functions

function getAbsolutePath(aPath)
	local abs_path
	if not aPath then
		abs_path = aPath
	elseif aPath:match('^//') then
		abs_path = aPath:sub(2)
	elseif aPath:match('^/') then
		abs_path = aPath
	elseif #aPath == 0 then
		abs_path = '/'
	else
		local curr_dir = lfs.currentdir()
		abs_path = aPath
		if lfs.chdir(aPath) then
			abs_path = lfs.currentdir()
			lfs.chdir(curr_dir)
		end
		--Debug("rel: '"..aPath.."' abs:'"..abs_path.."'")
	end
	return abs_path
end

function FileChooser:readDir()
	self.dirs = {}
	self.files = {}
	for f in lfs.dir(self.path) do
		if lfs.attributes(self.path.."/"..f, "mode") == "directory" and f ~= "." and f~=".."
			and not string.match(f, "^%.[^.]") then
				table.insert(self.dirs, f)
		elseif lfs.attributes(self.path.."/"..f, "mode") == "file"
			and not string.match(f, "^%.[^.]") then
			local file_type = string.lower(string.match(f, ".+%.([^.]+)") or "")
			if ext:getReader(file_type) then
				table.insert(self.files, f)
			end
		end
	end
	table.sort(self.dirs)
	if self.path~="/" then table.insert(self.dirs,1,"..") end
	table.sort(self.files)
end

function FileChooser:setPath(newPath)
	local curr_path = self.path
	self.path = getAbsolutePath(newPath)
	local readdir_ok, exc = pcall(self.readDir,self)
	if(not readdir_ok) then
		Debug("readDir error: "..tostring(exc))
		self.exception_message = exc
		return self:setPath(curr_path)
	else
		self.items = #self.dirs + #self.files
		if self.items == 0 then
			return nil
		end
		self.page = 1
		self.current = 1
		return true
	end
end

-- NuPogodi, 20.05.12: FileChooser:choose is totally rewritten
-- to make helppage with hotkeys available for users

function FileChooser:choose(ypos, height)
	self.perpage = math.floor(height / self.spacing) - 2
	self.pagedirty = true
	self.markerdirty = false

	self:addAllCommands()

	while true do
		local tface = Font:getFace("tfont", 25)
		local fface = Font:getFace("ffont", 16)
		local cface = Font:getFace("cfont", 22)

		if self.pagedirty then
			fb.bb:paintRect(0, ypos, fb.bb:getWidth(), height, 0)
			local c
			for c = 1, self.perpage do
				local i = (self.page - 1) * self.perpage + c
				if i <= #self.dirs then
					DrawFileItem(self.dirs[i],self.margin_H,ypos+self.title_H+self.spacing*c,"folder")
				elseif i <= self.items then
					local file_type = string.lower(string.match(self.files[i-#self.dirs], ".+%.([^.]+)") or "")
					DrawFileItem(self.files[i-#self.dirs],self.margin_H,ypos+self.title_H+self.spacing*c,file_type)
				end
			end
			-- draw footer
			all_page = math.ceil(self.items/self.perpage)
			DrawFooter("Page "..self.page.." of "..all_page,fface,self.foot_H)
			-- draw menu title
			local msg = self.exception_message and self.exception_message:match("[^%:]+:%d+: (.*)") or self.path
			self.exception_message = nil
			-- draw header
			DrawTitle(msg,self.margin_H,ypos,self.title_H,4,tface)
			self.markerdirty = true
		end

		if self.markerdirty then
			local ymarker = ypos + 8 + self.title_H
			if not self.pagedirty then
				if self.oldcurrent > 0 then
					fb.bb:paintRect(self.margin_H, ymarker+self.spacing*self.oldcurrent, fb.bb:getWidth()-2*self.margin_H, 3, 0)
					fb:refresh(1, self.margin_H, ymarker+self.spacing*self.oldcurrent, fb.bb:getWidth() - 2*self.margin_H, 3)
				end
			end
			fb.bb:paintRect(self.margin_H, ymarker+self.spacing*self.current, fb.bb:getWidth()-2*self.margin_H, 3, 15)
			if not self.pagedirty then
				fb:refresh(1, self.margin_H, ymarker+self.spacing*self.current, fb.bb:getWidth()-2*self.margin_H, 3)
			end
			self.oldcurrent = self.current
			self.markerdirty = false
		end

		if self.pagedirty then
			fb:refresh(0, 0, ypos, fb.bb:getWidth(), height)
			self.pagedirty = false
		end

		local ev = input.saveWaitForEvent()
		--Debug("key code:"..ev.code)
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

			if ret_code == "break" then break end

			if self.selected_item ~= nil then
				Debug("# selected "..self.selected_item)
				return self.selected_item
			end
		end -- if ev.type ==
	end -- while
end

-- NuPogodi, 20.05.12: add available commands
function FileChooser:addAllCommands()
	self.commands = Commands:new{}

	self.commands:add({KEY_SPACE}, nil, "Space",
		"refresh page manually",
		function(self)
			self.pagedirty = true
		end
	)
	self.commands:add({KEY_PGFWD, KEY_LPGFWD}, nil, ">",
		"goto next page",
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
		"goto previous page",
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
	self.commands:add(KEY_FW_DOWN, nil, "joypad down",
		"goto next item",
		function(self)
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
	)
	self.commands:add(KEY_FW_UP, nil, "joypad up",
		"goto previous item",
		function(self)
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
	)
	self.commands:add({KEY_FW_RIGHT, KEY_I}, nil, "joypad right",
		"show document information",
		function(self)
			if self:FullFileName() then
				FileInfo:show(self.path,self.files[self.perpage*(self.page-1)+self.current - #self.dirs])
				self.pagedirty = true
			end
		end
	)
	self.commands:add({KEY_ENTER, KEY_FW_PRESS}, nil, "Enter",
		"open document / goto folder",
		function(self)
			local newdir = self.dirs[self.perpage*(self.page-1)+self.current]
			if newdir == ".." then
				local path = string.gsub(self.path, "(.*)/[^/]+/?$", "%1")
				self:setPath(path)
			elseif newdir then
				self:setPath(self.path.."/"..newdir)
			else
				self.pathfile = self.path.."/"..self.files[self.perpage*(self.page-1)+self.current - #self.dirs]
				openFile(self.pathfile)
			end
			self.pagedirty = true
		end
	)
-- NuPogodi, 23.05.12: modified to delete both files and empty folders
	self.commands:add(KEY_DEL, nil, "Del",
		"delete selected item",
		function(self)
			local pos = self.perpage*(self.page-1)+self.current
			local folder = self.dirs[pos]
			if folder == ".." then
				showInfoMsgWithDelay("<UP-DIR> can not be deleted! ",2000,1)
			elseif folder then
				InfoMessage:show("Press \'Y\' to confirm deleting... ",0)
				if self:ReturnKey() == KEY_Y then
					if lfs.rmdir(self.path.."/"..folder) then
						self.pagedirty = true
						table.remove(self.dirs, offset)
						self.items = self.items - 1
						self.current = self.current - 1
					else
						showInfoMsgWithDelay("This folder can not be deleted! ",2000,1)
					end
				end
			else
				InfoMessage:show("Press \'Y\' to confirm deleting... ",0)
				if self:ReturnKey() == KEY_Y then
					pos = pos - #self.dirs
					local fullpath = self.path.."/"..self.files[pos]
					-- delete the file itself
					os.remove(fullpath)
					-- and its history file, if any
					os.remove(DocToHistory(fullpath))
					-- to avoid showing just deleted file
					table.remove(self.files, pos)
					self.items = self.items - 1
					self.current = self.current - 1
					self.pagedirty = true
				end
			end -- if folder == ".."
		end -- function
	)
-- NuPogodi, 24.05.12: Added function to rename documents (extention comes from the old file)
-- Tigran, 18/08/12: corrected the rename operation to include extension.
	self.commands:add(KEY_R, MOD_SHIFT, "R",
		"rename file",
		function(self)
			local oldname = self:FullFileName()
			if oldname then
				local newname = InputBox:input(0, 0, "New filename:", "including extension", true)
				if newname then
					newname = self.path.."/"..newname
					os.rename(oldname, newname)
					os.rename(DocToHistory(oldname), DocToHistory(newname))
					self:setPath(self.path)
				end
				self.pagedirty = true
			end
		end
	)
-- end of changes (NuPogodi)
	self.commands:add({KEY_F, KEY_AA}, nil, "F",
		"goto font menu",
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
	self.commands:add(KEY_H,nil,"H",
		"show help page",
		function(self)
			HelpPage:show(0, G_height, self.commands)
			self.pagedirty = true
		end
	) 
	self.commands:add(KEY_L, nil, "L",
		"show last documents",
		function(self)
			lfs.mkdir("./history/")
			FileHistory:init()
			FileHistory:choose("")
			self.pagedirty = true
			return nil
		end
	)
	self.commands:add(KEY_S, nil, "S",
		"search among files",
		function(self)
			local keywords = InputBox:input(0, 0, "Search:")
			if keywords then
				InfoMessage:show("Searching... ",0)
				FileSearcher:init( self.path )
				FileSearcher:choose(keywords)
			end
			self.pagedirty = true
		end -- function
	)
	
-- NuPogodi, 23.05.12: new functions to manipulate (copy & move) files via clipboard
	self.commands:add(KEY_C, MOD_SHIFT, "C",
		"copy file to \'clipboard\'",
		function(self)
			local file = self:FullFileName()
			if file then
				lfs.mkdir(self.clipboard)
				os.execute("cp "..self:InQuotes(file).." "..self.clipboard)
				local fn = self.files[self.perpage*(self.page-1)+self.current - #self.dirs]
				os.execute("cp "..self:InQuotes(DocToHistory(file)).." "
					..self:InQuotes(DocToHistory(self.clipboard.."/"..fn)) )
				showInfoMsgWithDelay("File copied to clipboard ", 1000, 1)
			end
		end
	) 
	self.commands:add(KEY_X, MOD_SHIFT, "X",
		"move file to \'clipboard\'",
		function(self)
			local file = self:FullFileName()
			if file then
				lfs.mkdir(self.clipboard)
				os.rename(file, self.clipboard.."/"..file)
				local fn = self.files[self.perpage*(self.page-1)+self.current - #self.dirs]
				os.rename(DocToHistory(file), DocToHistory(self.clipboard.."/"..fn))
				InfoMessage:show("File moved to clipboard ", 0)
				self:setPath(self.path)
				self.pagedirty = true
			end
		end
	)
	self.commands:add(KEY_V, MOD_SHIFT, "V",
		"paste file(s) from \'clipboard\'",
		function(self)
			InfoMessage:show("moving file(s) from clipboard ", 0)
			for f in lfs.dir(self.clipboard) do
				if lfs.attributes(self.clipboard.."/"..f, "mode") == "file" then
					os.rename(self.clipboard.."/"..f, self.path.."/"..f)
					os.rename(DocToHistory(self.clipboard.."/"..f), DocToHistory(self.path.."/"..f))
				end
			end
			self:setPath(self.path)
			self.pagedirty = true
		end
	)
	self.commands:add(KEY_B, MOD_SHIFT, "B",
		"show content of \'clipboard\'",
		function(self)
			lfs.mkdir(self.clipboard)
			self:setPath(self.clipboard)
			-- TODO: exit back from clipboard to last folder - Redefine Exit on FW_Right?
			self.pagedirty = true
		end
	)
	self.commands:add(KEY_N, MOD_SHIFT, "N",
		"make new folder",
		function(self)
			local folder = InputBox:input(0, 0, "New Folder:")
			if folder then
				if lfs.mkdir(self.path.."/"..folder) then
					self:setPath(self.path)
				end
			end
			self.pagedirty = true
		end
	)
-- end of changes (NuPogodi)
	self.commands:add(KEY_P, MOD_SHIFT, "P",
		"make screenshot",
		function(self)
			Screen:screenshot()
		end
	) 
	self.commands:add({KEY_BACK, KEY_HOME}, nil, "Back",
		"exit",
		function(self)
			return "break"
		end
	)
end

-- NuPogodi, 23.05.12: returns full filename or nil (if folder)
function FileChooser:FullFileName()
	local file
	local folder = self.dirs[self.perpage*(self.page-1)+self.current]
	if folder == ".." then
		showInfoMsgWithDelay("<UP-DIR> ",1000,1)
	elseif folder then
		showInfoMsgWithDelay("<DIR> ",1000,1)
	else
		file=self.path.."/"..self.files[self.perpage*(self.page-1)+self.current - #self.dirs]
	end
	return file
end
-- returns the keycode of released key and (if debug) shows the keycode on screen
function FileChooser:ReturnKey(debug)
	while true do
		ev = input.saveWaitForEvent()
		ev.code = adjustKeyEvents(ev)
		if ev.type == EV_KEY and ev.value ~= EVENT_VALUE_KEY_RELEASE then
			break
		end
	end
	if debug then showInfoMsgWithDelay("Keycode = "..ev.code,1000,1) end
	return ev.code
end

function FileChooser:InQuotes(text)
	return "\""..text.."\""
end

