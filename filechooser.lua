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
	exception_message = nil
}
-- to duplicate visual info by speaking
function say(text)
	os.execute("say ".."\""..text.."\"")
end
-- make long headers for fit in title width by removing first characters
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
	local fn, battery = "./data/temporary", "?"
	-- NuPogodi, 18.05.12: This command seems to work even without Amazon Kindle framework 
	os.execute("\(gasgauge-info ".."-s\) ".."> "..fn)
	if io.open(fn,"r") then
		for lines in io.lines(fn) do battery = " " .. lines end
	else
		battery = ""
	end
	return battery
end

function DrawTitle(text,lmargin,y,height,color,font_face)
	fb.bb:paintRect(lmargin, y+10, fb.bb:getWidth() - lmargin*2, height, color)
	-- to have a horisontal gap between text & background rectangle
	lmargin = lmargin + 10
	t = BatteryLevel() .. os.date(" %H:%M")
	local tw = TextWidget:new({ text = t, face = font_face})
	twidth = tw:getSize().w
	renderUtf8Text(fb.bb, fb.bb:getWidth()-twidth-lmargin, y + height, font_face, t, true)
	tw:free()

	tw = TextWidget:new({ text = text, face = font_face})
	local max_width = fb.bb:getWidth() - 2 * lmargin - twidth
	if tw:getSize().w < max_width then
		renderUtf8Text(fb.bb, lmargin, y + height, font_face, text, true)
	else
		tw:free()
		-- separately draw the title prefix = ...
		local tw = TextWidget:new({ text = "...", face = font_face})
		renderUtf8Text(fb.bb, lmargin, y + height, font_face, "...", true)
		-- then define proper text length and draw it
		local txt = getProperTitleLength(text,font_face,max_width-tw:getSize().w)
		renderUtf8Text(fb.bb, lmargin+tw:getSize().w, y + height, font_face, txt, true)
	end
end

function DrawFooter(text,font_face,h)
	y = G_height - 7
	x = (G_width / 2) - 50
	renderUtf8Text(fb.bb, x, y, font_face, text, true)
end

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
		--debug("rel: '"..aPath.."' abs:'"..abs_path.."'")
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
		debug("readDir error: "..tostring(exc))
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
	local xleft = x + iw:getSize().w + 9 -- 8-10 pixels = the gap between icon & filename
	local width = fb.bb:getWidth() - xleft - x
	-- now printing the name
	if sizeUtf8Text(xleft, fb.bb:getWidth() - x, cface, name, true).x < width then
		renderUtf8Text(fb.bb, xleft, y, cface, name, true)
	else 
		local lgap = sizeUtf8Text(0, width, cface, " ...", true).x
		local handle = renderUtf8TextWidth(fb.bb, xleft, y, cface, name, true, width - lgap - x)
		renderUtf8Text(fb.bb, handle.x + lgap + x, y, cface, " ...", true)
	end
end

function FileChooser:choose(ypos, height)
	local perpage = math.floor(height / self.spacing) - 2
	local pagedirty = true
	local markerdirty = false

	local prevItem = function ()
		if self.current == 1 then
			if self.page > 1 then
				self.current = perpage
				self.page = self.page - 1
				pagedirty = true
			end
		else
			self.current = self.current - 1
			markerdirty = true
		end
	end

	local nextItem = function ()
		if self.current == perpage then
			if self.page < (self.items / perpage) then
				self.current = 1
				self.page = self.page + 1
				pagedirty = true
			end
		else
			if self.page ~= math.floor(self.items / perpage) + 1
				or self.current + (self.page-1)*perpage < self.items then
				self.current = self.current + 1
				markerdirty = true
			end
		end
	end

	while true do
		local tface = Font:getFace("tfont", 25)
		local fface = Font:getFace("ffont", 16)
		local cface = Font:getFace("cfont", 22)

		if pagedirty then
			-- starttime was to optimize drawing process
			--local starttime = os.clock()
			fb.bb:paintRect(0, ypos, fb.bb:getWidth(), height, 0)
			local c
			for c = 1, perpage do
				local i = (self.page - 1) * perpage + c
				if i <= #self.dirs then
					DrawFileItem(self.dirs[i],self.margin_H,ypos+self.title_H+self.spacing*c,"folder")
				elseif i <= self.items then
					local file_type = string.lower(string.match(self.files[i-#self.dirs], ".+%.([^.]+)") or "")
					DrawFileItem(self.files[i-#self.dirs],self.margin_H,ypos+self.title_H+self.spacing*c,file_type)
				end
			end
			-- draw footer
			all_page = math.ceil(self.items/perpage)
			DrawFooter("Page "..self.page.." of "..all_page,fface,self.foot_H)
			-- draw menu title
			local msg = self.exception_message and self.exception_message:match("[^%:]+:%d+: (.*)") or self.path
			self.exception_message = nil
			-- draw header
			DrawTitle(msg,self.margin_H,ypos,self.title_H,4,tface)
			--say("The page was drawn in "..string.format("%.2f",os.clock()-starttime).." seconds.")
			markerdirty = true
		end
		if markerdirty then
			local ymarker = ypos + 8 + self.title_H
			if not pagedirty then
				if self.oldcurrent > 0 then
					fb.bb:paintRect(self.margin_H, ymarker+self.spacing*self.oldcurrent, fb.bb:getWidth()-2*self.margin_H, 3, 0)
					fb:refresh(1, self.margin_H, ymarker+self.spacing*self.oldcurrent, fb.bb:getWidth() - 2*self.margin_H, 3)
				end
			end
			fb.bb:paintRect(self.margin_H, ymarker+self.spacing*self.current, fb.bb:getWidth()-2*self.margin_H, 3, 15)
			if not pagedirty then
				fb:refresh(1, self.margin_H, ymarker+self.spacing*self.current, fb.bb:getWidth()-2*self.margin_H, 3)
			end
			self.oldcurrent = self.current
			markerdirty = false
		end
		if pagedirty then
			fb:refresh(0, 0, ypos, fb.bb:getWidth(), height)
			pagedirty = false
		end

		local ev = input.saveWaitForEvent()
		--debug("key code:"..ev.code)
		ev.code = adjustKeyEvents(ev)
		if ev.type == EV_KEY and ev.value ~= EVENT_VALUE_KEY_RELEASE then
			if ev.code == KEY_FW_UP then
				prevItem()
			elseif ev.code == KEY_FW_DOWN then
				nextItem()
			elseif ev.code == KEY_F or ev.code == KEY_AA then -- invoke fontchooser menu
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
				local re, font = fonts_menu:choose(0, height)
				if re then
					Font.fontmap["cfont"] = font
					Font:update()
				end
				pagedirty = true
			elseif ev.code == KEY_S then -- invoke search input
				keywords = InputBox:input(height-100, 100, "Search:")
				if keywords then
					-- call FileSearcher
					--[[
					This might looks a little bit dirty for using callback.
					But I cannot come up with a better solution for renewing
					the height argument according to screen rotation mode.

					The callback might also be useful for calling system
					settings menu in the future.
					--]]
					return nil, function()
						InfoMessage:show("Searching... ",0)
						FileSearcher:init( self.path )
						FileSearcher:choose(keywords)
					end
				end
				pagedirty = true
			elseif ev.code == KEY_L then -- last opened files
				InfoMessage:show("Searching last docs... ",0)
				if true then
					return nil, function()
						FileHistory:init()
						FileHistory:choose("") -- show all files
					end
				end
				pagedirty = true
			elseif ev.code == KEY_PGFWD or ev.code == KEY_LPGFWD then
				if self.page < (self.items / perpage) then
					if self.current + self.page*perpage > self.items then
						self.current = self.items - self.page*perpage
					end
					self.page = self.page + 1
					pagedirty = true
				else
					self.current = self.items - (self.page-1)*perpage
					markerdirty = true
				end
			elseif ev.code == KEY_PGBCK or ev.code == KEY_LPGBCK then
				if self.page > 1 then
					self.page = self.page - 1
					pagedirty = true
				else
					self.current = 1
					markerdirty = true
				end
			elseif ev.code == KEY_ENTER or ev.code == KEY_FW_PRESS then
				local newdir = self.dirs[perpage*(self.page-1)+self.current]
				if newdir == ".." then
					local path = string.gsub(self.path, "(.*)/[^/]+/?$", "%1")
					self:setPath(path)
				elseif newdir then
					local path = self.path.."/"..newdir
					self:setPath(path)
				else
					return self.path.."/"..self.files[perpage*(self.page-1)+self.current - #self.dirs]
				end
				pagedirty = true
			elseif ev.code == KEY_P then	-- make screenshot
				Screen:screenshot()
			elseif ev.code == KEY_FW_RIGHT or ev.code == KEY_I then	-- show file info
				return nil, function()
						local newdir = self.dirs[perpage*(self.page-1)+self.current]
						if newdir == ".." then
							showInfoMsgWithDelay("<UP-DIR>",1000,1)
						elseif newdir then
							showInfoMsgWithDelay("<DIR>",1000,1)
						else
							FileInfo:show(self.path,self.files[perpage*(self.page-1)+self.current - #self.dirs])
							pagedirty = true
						end
					end
			elseif ev.code == KEY_SPACE then	-- manual refresh
				pagedirty = true
			elseif ev.code == KEY_DEL then
				local dir_to_del = self.dirs[perpage*(self.page-1)+self.current]
				if dir_to_del == ".." then
					showInfoMsgWithDelay("<UP-DIR>",1000,1)
				elseif dir_to_del then
					showInfoMsgWithDelay("<DIR>",1000,1)
				else
					local file_to_del=self.path.."/"..self.files[perpage*(self.page-1)+self.current - #self.dirs]
					InfoMessage:show("Press \'Y\' to confirm deleting... ",0)
					while true do
						ev = input.saveWaitForEvent()
						ev.code = adjustKeyEvents(ev)
						if ev.type == EV_KEY and ev.value ~= EVENT_VALUE_KEY_RELEASE then
							if ev.code == KEY_Y then
								-- delete the file itself
								os.execute("rm \""..file_to_del.."\"")
								-- and its history file, if any
								os.execute("rm \""..DocToHistory(file_to_del).."\"")
								 -- to avoid showing just deleted file
								self:setPath(self.path)
							end
							pagedirty = true
							break
						end
					end -- while
				end
			elseif ev.code == KEY_BACK or ev.code == KEY_HOME then
				return nil
			end
		end
	end
end
