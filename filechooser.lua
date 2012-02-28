require "rendertext"
require "keys"
require "graphics"
require "fontchooser"
require "filesearcher"
require "inputbox"
require "selectmenu"

FileChooser = {
	-- Class vars:
	-- font for displaying toc item names
	fsize = 25,
	face = nil,
	fhash = nil,
	--face = freetype.newBuiltinFace("sans", 25),
	--fhash = "s25",

	-- font for paging display
	ffsize = 16,
	fface = nil,
	ffhash = nil,
	--sface = freetype.newBuiltinFace("sans", 16),
	--sfhash = "s16",
	
	-- spacing between lines
	spacing = 40,

	-- state buffer
	dirs = nil,
	files = nil,
	items = 0,
	path = "",
	page = 1,
	current = 1,
	oldcurrent = 0,
}

function FileChooser:readdir()
	self.dirs = {}
	self.files = {}
	for f in lfs.dir(self.path) do
		if lfs.attributes(self.path.."/"..f, "mode") == "directory" and f ~= "." and not string.match(f, "^%.[^.]") then
			table.insert(self.dirs, f)
		elseif string.match(f, ".+%.[pP][dD][fF]$") then
			table.insert(self.files, f)
		end
	end
	--@TODO make sure .. is sortted to the first item  16.02 2012
	table.sort(self.dirs)
	table.sort(self.files)
end

function FileChooser:setPath(newPath)
	self.path = newPath
	self:readdir()
	self.items = #self.dirs + #self.files
	if self.items == 0 then
		return nil
	end
	self.page = 1
	self.current = 1
	return true
end

function FileChooser:updateFont()
	if self.fhash ~= FontChooser.cfont..self.fsize then
		self.face = freetype.newBuiltinFace(FontChooser.cfont, self.fsize)
		self.fhash = FontChooser.cfont..self.fsize
	end
	if self.ffhash ~= FontChooser.ffont..self.ffsize then
		self.fface = freetype.newBuiltinFace(FontChooser.ffont, self.ffsize)
		self.ffhash = FontChooser.ffont..self.ffsize
	end
end

function FileChooser:choose(ypos, height)
	local perpage = math.floor(height / self.spacing) - 1
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
		self:updateFont()
		if pagedirty then
			fb.bb:paintRect(0, ypos, fb.bb:getWidth(), height, 0)
			local c
			for c = 1, perpage do
				local i = (self.page - 1) * perpage + c
				if i <= #self.dirs then
					-- resembles display in midnight commander: adds "/" prefix for directories
					renderUtf8Text(fb.bb, 39, ypos + self.spacing*c, self.face, self.fhash, "/", true)
					renderUtf8Text(fb.bb, 50, ypos + self.spacing*c, self.face, self.fhash, self.dirs[i], true)
				elseif i <= self.items then
					renderUtf8Text(fb.bb, 50, ypos + self.spacing*c, self.face, self.fhash, self.files[i-#self.dirs], true)
				end
			end
			renderUtf8Text(fb.bb, 39, ypos + self.spacing * perpage + 32, self.fface, self.ffhash,
				"Page "..self.page.." of "..(math.floor(self.items / perpage)+1), true)
			markerdirty = true
		end
		if markerdirty then
			if not pagedirty then
				if self.oldcurrent > 0 then
					fb.bb:paintRect(30, ypos + self.spacing*self.oldcurrent + 10, fb.bb:getWidth() - 60, 3, 0)
						fb:refresh(1, 30, ypos + self.spacing*self.oldcurrent + 10, fb.bb:getWidth() - 60, 3)
				end
			end
			fb.bb:paintRect(30, ypos + self.spacing*self.current + 10, fb.bb:getWidth() - 60, 3, 15)
			if not pagedirty then
				fb:refresh(1, 30, ypos + self.spacing*self.current + 10, fb.bb:getWidth() - 60, 3)
			end
			self.oldcurrent = self.current
			markerdirty = false
		end
		if pagedirty then
			fb:refresh(0, 0, ypos, fb.bb:getWidth(), height)
			pagedirty = false
		end
		local ev = input.waitForEvent()
		if ev.type == EV_KEY and ev.value == EVENT_VALUE_KEY_PRESS then
			--print("key code:"..ev.code)
			ev.code = adjustFWKey(ev.code)
			if ev.code == KEY_FW_UP then
				prevItem()
			elseif ev.code == KEY_FW_DOWN then
				nextItem()
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
			elseif ev.code == KEY_S then -- invoke search input
				keywords = InputBox:input(height-100, 100, "Search:")
				if keywords then -- display search result according to keywords
					--[[
						----------------------------------------------------------------
						|| uncomment following line and set the correct path if you want
						|| to test search feature in EMU mode
						----------------------------------------------------------------
					--]]
					FileSearcher:init("/home/dave/documents/kindle/backup/documents")
					--FileSearcher:init()
					file = FileSearcher:choose(ypos, height, keywords)
					if file then
						return file
					end
				end
				pagedirty = true
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
			elseif ev.code == KEY_BACK then
				return nil
			end
		end
	end
end
