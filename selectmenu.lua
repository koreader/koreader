require "rendertext"
require "keys"
require "graphics"
require "font"

SelectMenu = {
	-- font for displaying item names
	fsize = 22,
	-- font for page title
	tfsize = 25,
	-- font for paging display
	ffsize = 16,
	-- font for item shortcut
	sface = freetype.newBuiltinFace("mono", 22),
	sfhash = "mono22",

	-- title height
	title_H = 40,
	-- spacing between lines
	spacing = 36,
	-- foot height
	foot_H = 27,

	menu_title = "None Titled",
	no_item_msg = "No items found.",
	item_array = {},
	items = 0,

	item_shortcuts = {
		"Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P",
		"A", "S", "D", "F", "G", "H", "J", "K", "L", "Del",
		"Z", "X", "C", "V", "B", "N", "M", ".", "Sym", "Ent",
		},
	last_shortcut = 0,
	-- state buffer
	page = 1,
	current = 1,
	oldcurrent = 0,
}

function SelectMenu:new(o)
	o = o or {}
	setmetatable(o, self)
	self.__index = self
	o.items = #o.item_array
	o.page = 1
	o.current = 1
	o.oldcurrent = 0
	-- increase spacing for DXG so we don't have more than 30 shortcuts
	if fb.bb:getHeight() == 1200 then
		o.spacing = 37
	end
	return o
end

function SelectMenu:getItemIndexByShortCut(c, perpage)
	if c == nil then return end -- unused key
	for _k,_v in ipairs(self.item_shortcuts) do
		if _v == c and _k <= self.last_shortcut then
			return (perpage * (self.page - 1) + _k)
		end
	end
end

--[
-- return the index of selected item
--]
function SelectMenu:choose(ypos, height)
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

	self.last_shortcut = 0

	while true do
		local cface, cfhash = Font:getFaceAndHash(22)
		local tface, tfhash = Font:getFaceAndHash(25, Font.tfont)
		local fface, ffhash = Font:getFaceAndHash(16, Font.ffont)

		if pagedirty then
			markerdirty = true
			-- draw menu title
			fb.bb:paintRect(0, ypos, fb.bb:getWidth(), self.title_H + 10, 0)
			fb.bb:paintRect(10, ypos + 10, fb.bb:getWidth() - 20, self.title_H, 5)

			local x = 20
			local y = ypos + self.title_H
			renderUtf8Text(fb.bb, x, y, tface, tfhash, self.menu_title, true)

			-- draw items
			fb.bb:paintRect(0, ypos + self.title_H + 10, fb.bb:getWidth(), height - self.title_H, 0)
			if self.items == 0 then
				y = ypos + self.title_H + (self.spacing * 2)
				renderUtf8Text(fb.bb, 30, y, cface, cfhash,
					"Oops...  Bad news for you:", true)
				y = y + self.spacing
				renderUtf8Text(fb.bb, 30, y, cface, cfhash,
					self.no_item_msg, true)
				markerdirty = false
			else
				local c
				for c = 1, perpage do
					local i = (self.page - 1) * perpage + c 
					if i <= self.items then
						y = ypos + self.title_H + (self.spacing * c)

						-- paint shortcut indications
						if c <= 10 or c > 20 then
							blitbuffer.paintBorder(fb.bb, 10, y-22, 29, 29, 2, 15)
						else
							fb.bb:paintRect(10, y-22, 29, 29, 3)
						end
						if self.item_shortcuts[c] ~= nil and 
							string.len(self.item_shortcuts[c]) == 3 then
							-- print "Del", "Sym and "Ent"
							renderUtf8Text(fb.bb, 13, y, fface, ffhash,
								self.item_shortcuts[c], true)
						else
							renderUtf8Text(fb.bb, 18, y, self.sface, self.sfhash,
								self.item_shortcuts[c], true)
						end

						self.last_shortcut = c

						renderUtf8Text(fb.bb, 50, y, cface, cfhash,
							self.item_array[i], true)
					end
				end
			end

			-- draw footer
			y = ypos + self.title_H + (self.spacing * perpage) + self.foot_H + 5
			x = (fb.bb:getWidth() / 2) - 50
			renderUtf8Text(fb.bb, x, y, fface, ffhash,
				"Page "..self.page.." of "..(math.floor(self.items / perpage)+1), true)
		end

		if markerdirty then
			if not pagedirty then
				if self.oldcurrent > 0 then
					y = ypos + self.title_H + (self.spacing * self.oldcurrent) + 8
					fb.bb:paintRect(45, y, fb.bb:getWidth() - 60, 3, 0)
					fb:refresh(1, 45, y, fb.bb:getWidth() - 60, 3)
				end
			end
			-- draw new marker line
			y = ypos + self.title_H + (self.spacing * self.current) + 8
			fb.bb:paintRect(45, y, fb.bb:getWidth() - 60, 3, 15)
			if not pagedirty then
				fb:refresh(1, 45, y, fb.bb:getWidth() - 60, 3)
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
			local selected = nil
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
			elseif ev.code == KEY_FW_PRESS or ev.code == KEY_ENTER and self.last_shortcut < 30 then
				if self.items == 0 then
					return nil
				else
					return (perpage*(self.page-1) + self.current)
				end
			elseif ev.code >= KEY_Q and ev.code <= KEY_P then
				selected = self:getItemIndexByShortCut(self.item_shortcuts[ ev.code - KEY_Q + 1 ], perpage)
			elseif ev.code >= KEY_A and ev.code <= KEY_L then
				selected = self:getItemIndexByShortCut(self.item_shortcuts[ ev.code - KEY_A + 11], perpage)
			elseif ev.code >= KEY_Z and ev.code <= KEY_M then
				selected = self:getItemIndexByShortCut(self.item_shortcuts[ ev.code - KEY_Z + 21], perpage)
			elseif ev.code == KEY_DEL then
				selected = self:getItemIndexByShortCut("Del", perpage)
			elseif ev.code == KEY_DOT then
				selected = self:getItemIndexByShortCut(".", perpage)
			elseif ev.code == KEY_SYM or ev.code == KEY_SLASH then -- DXG has slash after dot
				selected = self:getItemIndexByShortCut("Sym", perpage)
			elseif ev.code == KEY_ENTER then
				selected = self:getItemIndexByShortCut("Ent", perpage)
			elseif ev.code == KEY_BACK then
				return nil
			end
			if selected ~= nil then
				print("# selected "..selected)
				return selected
			end
		end
	end
end
