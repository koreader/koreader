require "rendertext"
require "keys"
require "graphics"
require "font"
require "filesearcher"
require "inputbox"
require "selectmenu"

FileChooser = {
	-- Class vars:

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
	exception_message = nil
}

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
		--print("rel: '"..aPath.."' abs:'"..abs_path.."'")
	end
	return abs_path
end

function FileChooser:readDir()
	self.dirs = {}
	self.files = {}
	for f in lfs.dir(self.path) do
		if lfs.attributes(self.path.."/"..f, "mode") == "directory" and f ~= "." and not (f==".." and self.path=="/") and not string.match(f, "^%.[^.]") then
			--print(self.path.." -> adding: '"..f.."'")
			table.insert(self.dirs, f)
		else
			local file_type = string.lower(string.match(f, ".+%.([^.]+)") or "")
			if file_type == "djvu"
			or file_type == "pdf" or file_type == "xps" or file_type == "cbz" 
			or file_type == "epub" or file_type == "txt" or file_type == "rtf"
			or file_type == "htm" or file_type == "html"
			or file_type == "fb2" or file_type == "chm" then
				table.insert(self.files, f)
			end
		end
	end
	--@TODO make sure .. is sortted to the first item  16.02 2012
	table.sort(self.dirs)
	table.sort(self.files)
end

function FileChooser:setPath(newPath)
	local curr_path = self.path
	self.path = getAbsolutePath(newPath)
	local readdir_ok, exc = pcall(self.readDir,self)
	if(not readdir_ok) then
		print("readDir error: "..tostring(exc))
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
		local cface, cfhash= Font:getFaceAndHash(25)
		local fface, ffhash = Font:getFaceAndHash(16, Font.ffont)

		if pagedirty then
			fb.bb:paintRect(0, ypos, fb.bb:getWidth(), height, 0)
			local c
			for c = 1, perpage do
				local i = (self.page - 1) * perpage + c
				if i <= #self.dirs then
					-- resembles display in midnight commander: adds "/" prefix for directories
					renderUtf8Text(fb.bb, 39, ypos + self.spacing*c, cface, cfhash, "/", true)
					renderUtf8Text(fb.bb, 50, ypos + self.spacing*c, cface, cfhash, self.dirs[i], true)
				elseif i <= self.items then
					renderUtf8Text(fb.bb, 50, ypos + self.spacing*c, cface, cfhash, self.files[i-#self.dirs], true)
				end
			end
			renderUtf8Text(fb.bb, 5, ypos + self.spacing * perpage + 42, fface, ffhash,
				"Page "..self.page.." of "..(math.floor(self.items / perpage)+1), true)
			local msg = self.exception_message and self.exception_message:match("[^%:]+:%d+: (.*)") or "Path: "..self.path
			self.exception_message = nil
			renderUtf8Text(fb.bb, 5, ypos + self.spacing * (perpage+1) + 27, fface, ffhash, msg, true)
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
		--print("key code:"..ev.code)
		ev.code = adjustKeyEvents(ev)
		if ev.type == EV_KEY and ev.value == EVENT_VALUE_KEY_PRESS then
			if ev.code == KEY_FW_UP then
				prevItem()
			elseif ev.code == KEY_FW_DOWN then
				nextItem()
			elseif ev.code == KEY_F then -- invoke fontchooser menu
				fonts_menu = SelectMenu:new{
					menu_title = "Fonts Menu",
					item_array = Font.fonts,
				}
				local re = fonts_menu:choose(0, height)
				if re then
					Font.cfont = Font.fonts[re]
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
					the height arguemtn according to screen rotation mode.

					The callback might also be useful for calling system
					settings menu in the future.
					--]]
					return nil, function()
						FileSearcher:init( self.path )
						FileSearcher:choose(keywords)
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
			elseif ev.code == KEY_BACK or ev.code == KEY_HOME then
				return nil
			end
		end
	end
end
