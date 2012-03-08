require "rendertext"
require "keys"
require "graphics"
require "fontchooser"

FileSearcher = {
	-- font for displaying toc item names
	fsize = 25,
	face = nil,
	fhash = nil,
	-- font for page title
	tfsize = 30,
	tface = nil,
	tfhash = nil,
	-- font for paging display
	ffsize = 16,
	fface = nil,
	ffhash = nil,

	-- title height
	title_H = 45,
	-- spacing between lines
	spacing = 40,
	-- foot height
	foot_H = 27,

	-- state buffer
	dirs = {},
	files = {},
	result = {},
	items = 0,
	page = 0,
	current = 1,
	oldcurrent = 1,
}

function FileSearcher:readdir()
	self.dirs = {self.path}
	self.files = {}
	while #self.dirs ~= 0 do
		new_dirs = {}
		-- handle each dir
		for __, d in pairs(self.dirs) do
			-- handle files in d
			for f in lfs.dir(d) do
				if lfs.attributes(d.."/"..f, "mode") == "directory"
				and f ~= "." and f~= ".." and not string.match(f, "^%.[^.]") then
					table.insert(new_dirs, d.."/"..f)
				elseif string.match(f, ".+%.[pP][dD][fF]$") or string.match(f, ".+%.[dD][jJ][vV][uU]$") then
					file_entry = {dir=d, name=f,}
					table.insert(self.files, file_entry)
					--print("file:"..d.."/"..f)
				end
			end
		end
		self.dirs = new_dirs
	end
end

function FileSearcher:setPath(newPath)
	self.path = newPath
	self:readdir()
	self.items = #self.files
	--@TODO check none found  19.02 2012
	if self.items == 0 then
		return nil
	end
	self.page = 1
	self.current = 1
	return true
end

function FileSearcher:updateFont()
	if self.fhash ~= FontChooser.cfont..self.fsize then
		self.face = freetype.newBuiltinFace(FontChooser.cfont, self.fsize)
		self.fhash = FontChooser.cfont..self.fsize
	end

	if self.tfhash ~= FontChooser.tfont..self.tfsize then
		self.tface = freetype.newBuiltinFace(FontChooser.tfont, self.tfsize)
		self.tfhash = FontChooser.tfont..self.tfsize
	end

	if self.ffhash ~= FontChooser.ffont..self.ffsize then
		self.fface = freetype.newBuiltinFace(FontChooser.ffont, self.ffsize)
		self.ffhash = FontChooser.ffont..self.ffsize
	end
end

function FileSearcher:setSearchResult(keywords)
	self.result = {}
	if keywords == " " then -- one space to show all files
		self.result = self.files
	else
		for __,f in pairs(self.files) do
			if string.find(string.lower(f.name), keywords) then
				table.insert(self.result, f)
			end
		end
	end
	self.items = #self.result
	self.page = 1
	self.current = 1
end

function FileSearcher:init(search_path)
	if search_path then
		self:setPath(search_path)
	else
		self:setPath("/mnt/us/documents")
	end
end


function FileSearcher:choose(ypos, height, keywords)
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

	-- if given keywords, set new result according to keywords. 
	-- Otherwise, display the previous search result.
	if keywords then 
		self:setSearchResult(keywords)
	end

	while true do
		self:updateFont()
		if pagedirty then
			markerdirty = true
			fb.bb:paintRect(0, ypos, fb.bb:getWidth(), height, 0)

			-- draw menu title
			renderUtf8Text(fb.bb, 30, ypos + self.title_H, self.tface, self.tfhash,
				"Search Result for: "..keywords, true)

			-- draw results
			local c
			if self.items == 0 then -- nothing found
				y = ypos + self.title_H + self.spacing * 2
				renderUtf8Text(fb.bb, 20, y, self.face, self.fhash, 
					"Sorry, no match found.", true) 
				renderUtf8Text(fb.bb, 20, y + self.spacing, self.face, self.fhash, 
					"Please try a different keyword.", true)
				markerdirty = false
			else -- found something, draw it
				for c = 1, perpage do
					local i = (self.page - 1) * perpage + c 
					if i <= self.items then
						y = ypos + self.title_H + (self.spacing * c)
						renderUtf8Text(fb.bb, 50, y, self.face, self.fhash, 
							self.result[i].name, true)
					end
				end
			end

			-- draw footer
			y = ypos + self.title_H + (self.spacing * perpage) + self.foot_H
			x = (fb.bb:getWidth() / 2) - 50
			all_page = (math.floor(self.items / perpage)+1)
			renderUtf8Text(fb.bb, x, y, self.fface, self.ffhash,
				"Page "..self.page.." of "..all_page, true)
		end

		if markerdirty then
			if not pagedirty then
				if self.oldcurrent > 0 then
					y = ypos + self.title_H + (self.spacing * self.oldcurrent) + 10
					fb.bb:paintRect(30, y, fb.bb:getWidth() - 60, 3, 0)
					fb:refresh(1, 30, y, fb.bb:getWidth() - 60, 3)
				end
			end
			-- draw new marker line
			y = ypos + self.title_H + (self.spacing * self.current) + 10
			fb.bb:paintRect(30, y, fb.bb:getWidth() - 60, 3, 15)
			if not pagedirty then
				fb:refresh(1, 30, y, fb.bb:getWidth() - 60, 3)
			end
			self.oldcurrent = self.current
			markerdirty = false
		end

		if pagedirty then
			fb:refresh(0, 0, ypos, fb.bb:getWidth(), height)
			pagedirty = false
		end

		local ev = input.waitForEvent()
		ev.code = adjustKeyEvents(ev)
		if ev.type == EV_KEY and ev.value == EVENT_VALUE_KEY_PRESS then
			if ev.code == KEY_FW_UP then
				prevItem()
			elseif ev.code == KEY_FW_DOWN then
				nextItem()
			elseif ev.code == KEY_PGFWD then
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
			elseif ev.code == KEY_PGBCK then
				if self.page > 1 then
					self.page = self.page - 1
					pagedirty = true
				else
					self.current = 1
					markerdirty = true
				end
			elseif ev.code == KEY_S then
				old_keywords = keywords
				keywords = InputBox:input(height-100, 100, "Search:", old_keywords)
				if keywords then
					self:setSearchResult(keywords)
				else
					keywords = old_keywords
				end
				pagedirty = true
			elseif ev.code == KEY_F then -- invoke fontchooser menu
				fonts_menu = SelectMenu:new{
					menu_title = "Fonts Menu",
					item_array = FontChooser.fonts,
				}
				local re = fonts_menu:choose(0, height)
				if re then
					FontChooser.cfont = FontChooser.fonts[re]
					FontChooser:init()
				end
				pagedirty = true
			elseif ev.code == KEY_ENTER or ev.code == KEY_FW_PRESS then
				file_entry = self.result[perpage*(self.page-1)+self.current]
				file_full_path = file_entry.dir .. "/" .. file_entry.name

				-- rotation mode might be changed while reading, so 
				-- record height_percent here
				local height_percent = height/fb.bb:getHeight()
				openFile(file_full_path)

				--reset height and item index if screen has been rotated
				local old_perpage = perpage
				height = math.floor(fb.bb:getHeight()*height_percent)
				perpage = math.floor(height / self.spacing) - 2
				self.current = (old_perpage * (self.page - 1) +
								self.current) % perpage
				self.page = math.floor(self.items / perpage) + 1

				pagedirty = true
			elseif ev.code == KEY_BACK or ev.code == KEY_HOME then
				return nil
			end
		end
	end
end
