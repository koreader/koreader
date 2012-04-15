require "rendertext"
require "keys"
require "graphics"
require "font"
require "inputbox"
require "selectmenu"
require "commands"

HelpPage = {
	-- state buffer
	commands = nil,
	items = 0,
	page = 1
}

-- Other Class vars:

-- font for displaying help messages
HelpPage.sFace, HelpPage.sHash = Font:getFaceAndHash(20, "sans")
-- font for displaying keys
HelpPage.mFace, HelpPage.mHash = Font:getFaceAndHash(20, "sans")
-- font for paging display
HelpPage.fFace, HelpPage.fHash = Font:getFaceAndHash(15, "sans")

function HelpPage:show(ypos,height,commands)
	self.commands = {}
	self.items = 0
	local keys = {}
	for k,v in pairs(commands.map) do
		local key = v.keygroup or v.keydef:display()
		--print("order: "..v.order.." command: "..tostring(v.keydef).." - keygroup:"..(v.keygroup or "nil").." -keys[key]:"..(keys[key] or "nil"))
		if keys[key] == nil then
			keys[key] = 1
			table.insert(self.commands,{shortcut=key,help=v.help,order=v.order})
			self.items = self.items + 1
		end
	end
	table.sort(self.commands,function(w1,w2) return w1.order<w2.order end)

	local mFaceHeight, mFaceAscender = self.mFace:getHeightAndAscender();
	local fFaceHeight, fFaceAscender = self.fFace:getHeightAndAscender();
	--print(mFaceHeight.."-"..mFaceAscender)
	--print(fFaceHeight.."-"..fFaceAscender)
	mFaceHeight = math.ceil(mFaceHeight)
	mFaceAscender = math.ceil(mFaceAscender)
	fFaceHeight = math.ceil(fFaceHeight)
	fFaceAscender = math.ceil(fFaceAscender)
	local spacing = mFaceHeight + 5

	local perpage = math.floor( (height - ypos - 1 * (fFaceHeight + 5)) / spacing )
	local pagedirty = true

	while true do
		if pagedirty then
			fb.bb:paintRect(0, ypos, fb.bb:getWidth(), height, 0)
			local c
			local max_x = 0
			for c = 1, perpage do
				local x = 5
				local i = (self.page - 1) * perpage + c
				if i <= self.items then
					local key = self.commands[i].shortcut
					for _k,aMod in pairs(MOD_TABLE) do
						local modStart, modEnd = key:find(aMod.v)
						print("key:"..key.." v:"..aMod.v.." d:"..aMod.d.." modstart:"..(modStart or "nil"))
						if(modStart ~= nil) then
							key = key:sub(1,modStart-1)..key:sub(modEnd+1)
							local box = sizeUtf8Text( x, fb.bb:getWidth(), self.mFace, self.mHash, aMod.d, true)
							fb.bb:paintRect(x, ypos + spacing*c - box.y_top, box.x, box.y_top + box.y_bottom, 4);
							local pen_x = renderUtf8Text(fb.bb, x, ypos + spacing*c, self.mFace, self.mHash, aMod.d.." + ", true)
							x = x + pen_x
							max_x = math.max(max_x, pen_x)
						end
					end
					local box = sizeUtf8Text( x, fb.bb:getWidth(), self.mFace, self.mHash, key , true)
					fb.bb:paintRect(x, ypos + spacing*c - box.y_top, box.x, box.y_top + box.y_bottom, 4);
					local pen_x = renderUtf8Text(fb.bb, x, ypos + spacing*c, self.mFace, self.mHash, key, true)
					x = x + pen_x
					max_x = math.max(max_x, x)
				end
			end
			for c = 1, perpage do
				local i = (self.page - 1) * perpage + c
				if i <= self.items then
					renderUtf8Text(fb.bb, max_x + 20, ypos + spacing*c, self.sFace, self.sHash, self.commands[i].help, true)
				end
			end
			renderUtf8Text(fb.bb, 5, height - fFaceHeight + fFaceAscender - 5, self.fFace, self.fHash,
				"Page "..self.page.." of "..math.ceil(self.items / perpage).."  - click Back to close this page", true)
			markerdirty = true
		end
		if pagedirty then
			fb:refresh(0, 0, ypos, fb.bb:getWidth(), height)
			pagedirty = false
		end

		local ev = input.waitForEvent()
		--print("key code:"..ev.code)
		ev.code = adjustKeyEvents(ev)
		if ev.type == EV_KEY and ev.value == EVENT_VALUE_KEY_PRESS then
			if ev.code == KEY_PGFWD then
				if self.page < (self.items / perpage) then
					self.page = self.page + 1
					pagedirty = true
				end
			elseif ev.code == KEY_PGBCK then
				if self.page > 1 then
					self.page = self.page - 1
					pagedirty = true
				end
			elseif ev.code == KEY_BACK or ev.code == KEY_HOME then
				return nil
			end
		end
	end
end
