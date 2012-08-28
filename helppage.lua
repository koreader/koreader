require "rendertext"
require "keys"
require "graphics"
require "font"
require "inputbox"
require "selectmenu"
require "commands"

HelpPage = {
	-- Other Class vars:

	-- title height
	title_H = 40,
	-- horisontal margin
	margin_H = 10,
	-- foot height
	foot_H = 28,
	-- background color
	bg_color = 4,
	-- spacing between lines
	spacing = 25,

	-- state buffer
	commands = nil,
	items = 0,
	page = 1,

	-- font for displaying keys
	fsize = 20,
	face = Font:getFace("hpkfont", 20),

	-- font for displaying help messages
	hfsize = 20,
	hface = Font:getFace("hfont", 20),

	-- font for paging display
	ffsize = 15,
	fface = Font:getFace("pgfont", 15)
}

-- Other Class vars:

-- 02.06.12: added parameter 'title' for the header to make this function usable for various documentation purposes
function HelpPage:show(ypos, height, commands, title)
	self.commands = {}
	self.items = 0
	local keys = {}
	for k,v in pairs(commands.map) do
		local key = v.keygroup or v.keydef:display()
		--Debug("order: "..v.order.." command: "..tostring(v.keydef).." - keygroup:"..(v.keygroup or "nil").." -keys[key]:"..(keys[key] or "nil"))
		if keys[key] == nil then
			keys[key] = 1
			table.insert(self.commands,{shortcut=key,help=v.help,order=v.order})
			self.items = self.items + 1
		end
	end
	table.sort(self.commands,function(w1,w2) return w1.order<w2.order end)

	local face_height, face_ascender = self.face.ftface:getHeightAndAscender()
	--local hface_height, hface_ascender = self.hface.ftface:getHeightAndAscender()
	local fface_height, fface_ascender = self.fface.ftface:getHeightAndAscender()
	--Debug(face_height.."-"..face_ascender)
	--Debug(fface_height.."-"..fface_ascender)
	face_height = math.ceil(face_height)
	face_ascender = math.ceil(face_ascender)
	fface_height = math.ceil(fface_height)
	fface_ascender = math.ceil(fface_ascender)
	local spacing = face_height + 5
	-- 02.06.12: minor correction to vertical position of displayed items
	local vert_S = self.title_H + 3

	local perpage = math.floor( (height - ypos - 1 * (fface_height + 5) - vert_S) / spacing )
	self.page = 1
	local is_pagedirty = true

	while true do
		if is_pagedirty then
			fb.bb:paintRect(0, ypos, fb.bb:getWidth(), height, 0)
			-- 02.06.12: one should use it here
			DrawTitle(title or "Active Hotkeys",self.margin_H,0,self.title_H,self.bg_color,Font:getFace("tfont", 25))
			local c
			local max_x = 0
			for c = 1, perpage do
				local x = self.margin_H
				local i = (self.page - 1) * perpage + c
				if i <= self.items then
					local key = self.commands[i].shortcut
					for _k,aMod in pairs(MOD_TABLE) do
						local modStart, modEnd = key:find(aMod.v)
						Debug("key:"..key.." v:"..aMod.v.." d:"..aMod.d.." modstart:"..(modStart or "nil"))
						if(modStart ~= nil) then
							key = key:sub(1,modStart-1)..key:sub(modEnd+1)
							local box = sizeUtf8Text( x, fb.bb:getWidth(), self.face, aMod.d, true)
							fb.bb:paintRect(x, ypos + spacing*c - box.y_top + vert_S, box.x + self.title_H, box.y_top + box.y_bottom, self.bg_color)
							local pen_x = renderUtf8Text(fb.bb, x, ypos + spacing*c + vert_S, self.face, aMod.d.." + ", true)
							x = x + pen_x
							max_x = math.max(max_x, pen_x)
						end
					end
					Debug("key:"..key)
					local box = sizeUtf8Text( x, fb.bb:getWidth(), self.face, key , true)
					fb.bb:paintRect(x, ypos + spacing*c - box.y_top + vert_S, box.x, box.y_top + box.y_bottom, self.bg_color)
					local pen_x = renderUtf8Text(fb.bb, x, ypos + spacing*c  + vert_S, self.face, key, true)
					x = x + pen_x
					max_x = math.max(max_x, x)
				end
			end
			for c = 1, perpage do
				local i = (self.page - 1) * perpage + c
				if i <= self.items then
					renderUtf8Text(fb.bb, max_x + 20, ypos + spacing*c + vert_S, self.hface, self.commands[i].help, true)
				end
			end
			-- draw footer
			local footer = "Page "..self.page.." of "..math.ceil(self.items / perpage).."  - Back to close this page"
			-- DrawFooter(footer,Font:getFace("ffont", 16),self.foot_H) --
			renderUtf8Text(fb.bb, self.margin_H, height-7, self.fface, footer, true)
		end
		if is_pagedirty then
			fb:refresh(0, 0, ypos, fb.bb:getWidth(), height)
			is_pagedirty = false
		end

		local ev = input.saveWaitForEvent()
		--Debug("key code:"..ev.code)
		ev.code = adjustKeyEvents(ev)
		if ev.type == EV_KEY and ev.value == EVENT_VALUE_KEY_PRESS then
			if ev.code == KEY_PGFWD or ev.code == KEY_LPGFWD then
				if self.page < (self.items / perpage) then
					self.page = self.page + 1
					is_pagedirty = true
				end
			elseif ev.code == KEY_PGBCK or ev.code == KEY_LPGBCK then
				if self.page > 1 then
					self.page = self.page - 1
					is_pagedirty = true
				end
			elseif ev.code == KEY_BACK or ev.code == KEY_HOME then
				return nil
			end
		end
	end
end
