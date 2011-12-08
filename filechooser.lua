require "rendertext"
require "keys"
require "graphics"

FileChooser = {
	dirs = nil,
	files = nil
}

function FileChooser:readdir(path)
	self.dirs = {}
	self.files = {}
	for f in lfs.dir(path) do
		if lfs.attributes(path.."/"..f, "mode") == "directory" and f ~= "." and not string.match(f, "^%.[^.]") then
			table.insert(self.dirs, f)
		elseif string.match(f, ".+%.[pP][dD][fF]$") then
			table.insert(self.files, f)
		end
	end
	table.sort(self.dirs)
	table.sort(self.files)
end

function FileChooser:choose(startpath, ypos, height)
	local face = freetype.newBuiltinFace("sans", 25)
	local fhash = "s25"
	local sface = freetype.newBuiltinFace("sans", 16)
	local sfhash = "s16"
	local path = startpath
	local spacing = 40
	local perpage = math.floor(height / spacing) - 1
	local pathdirty = true
	local pagedirty = false
	local framebufferdirty = false
	local markerdirty = true
	local oldcurrent = 0
	local page
	local current
	local items
	while true do
		if pathdirty then
			print("showing file chooser in <"..path..">")
			self:readdir(path)
			items = #self.dirs + #self.files
			if items == 0 then
				return nil
			end
			page = 1
			current = 1
			pathdirty = false
			pagedirty = true
		end
		if pagedirty then
			fb.bb:paintRect(0, ypos, fb.bb:getWidth(), height, 0)
			local c
			for c = 1, perpage do
				local i = (page - 1) * perpage + c
				if i <= #self.dirs then
					renderUtf8Text(fb.bb, 39, ypos + spacing*c, face, fhash, "/", true)
					renderUtf8Text(fb.bb, 50, ypos + spacing*c, face, fhash, self.dirs[i], true)
				elseif i <= items then
					renderUtf8Text(fb.bb, 50, ypos + spacing*c, face, fhash, self.files[i-#self.dirs], true)
				end
			end
			renderUtf8Text(fb.bb, 39, ypos + spacing * perpage + 32, sface, sfhash,
				"Page "..page.." of "..(math.floor(items / perpage)+1), true)
			framebufferdirty = true
			markerdirty = true
			pagedirty = false
		end
		if markerdirty then
			if oldcurrent > 0 then
				fb.bb:paintRect(30, ypos + spacing*oldcurrent + 10, fb.bb:getWidth() - 60, 3, 0)
				fb:refresh(1, ypos + spacing*oldcurrent + 10, fb.bb:getWidth() - 60, 3)
			end
			fb.bb:paintRect(30, ypos + spacing*current + 10, fb.bb:getWidth() - 60, 3, 15)
			fb:refresh(1, ypos + spacing*current + 10, fb.bb:getWidth() - 60, 3)
			oldcurrent = current
			markerdirty = false
		end
		local ev = input.waitForEvent()
		if ev.type == EV_KEY and ev.value == EVENT_VALUE_KEY_PRESS then
			if ev.code == KEY_FW_UP then
				if current == 1 then
					if page > 1 then
						current = perpage
						page = page - 1
						pagedirty = true
					end
				else
					current = current - 1
					markerdirty = true
				end
			elseif ev.code == KEY_FW_DOWN then
				if current == perpage then
					if page < (items / perpage) then
						current = 1
						page = page + 1
						pagedirty = true
					end
				else
					if page ~= math.floor(items / perpage) + 1
						or current + (page-1)*perpage < items then
						current = current + 1
						markerdirty = true
					end
				end
			elseif ev.code == KEY_PGFWD then
				if page < (items / perpage) then
					if current + page*perpage > items then
						current = items - page*perpage
					end
					page = page + 1
					pagedirty = true
				else
					current = items - (page-1)*perpage
					markerdirty = true
				end
			elseif ev.code == KEY_PGBCK then
				if page > 1 then
					page = page - 1
					pagedirty = true
				else
					current = 1
					markerdirty = true
				end
			elseif ev.code == KEY_ENTER or ev.code == KEY_FWPRESS then
				local newdir = self.dirs[perpage*(page-1)+current]
				if newdir == ".." then
					path = string.gsub(path, "(.*)/[^/]+/?$", "%1")
					pathdirty = true
				elseif newdir then
					path = path.."/"..newdir
					pathdirty = true
				else
					return path.."/"..self.files[perpage*(page-1)+current - #self.dirs]
				end
			elseif ev.code == KEY_BACK then
				return nil
			end
		end
	end
end
