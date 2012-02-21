require "rendertext"
require "keys"
require "graphics"

TOCMenu = {
	-- font for displaying file/dir names
	face = freetype.newBuiltinFace("cjk", 25),
	fhash = "s25",
	-- font for page title
	tface = freetype.newBuiltinFace("Helvetica-BoldOblique", 25),
	tfhash = "hbo25",
	-- font for paging display
	sface = freetype.newBuiltinFace("sans", 16),
	sfhash = "s16",
	-- title height
	title_H = 40,
	-- spacing between lines
	spacing = 40,
	-- foot height
	foot_H = 27,

	-- state buffer
	toc = {},
	items = 14,
	page = 1,
	current = 1,
	oldcurrent = 0,
}

function TOCMenu:new(toc)
	--@TODO set font here in the future  21.02 2012
	--clearglyphcache()
	instance = self
	instance.toc = toc
	instance.items = #toc
	return instance
end

function TOCMenu:dump()
	for k,v in pairs(self.toc) do
		print("TOC item: "..k)
		for key,value in pairs(v) do
			print("    "..key..": "..value)
		end
	end
end

function TOCMenu:choose(ypos, height)
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
		if pagedirty then
			-- draw menu title
			fb.bb:paintRect(0, ypos, fb.bb:getWidth(), self.title_H + 10, 0)
			fb.bb:paintRect(30, ypos + 10, fb.bb:getWidth() - 60, self.title_H, 5)
			x = fb.bb:getWidth() - 260 -- move text to the right
			y = ypos + self.title_H
			renderUtf8Text(fb.bb, x, y, self.tface, self.tfhash,
				"Table of Contents", true)

			-- draw font items
			fb.bb:paintRect(0, ypos + self.title_H + 10, fb.bb:getWidth(), height - self.title_H, 0)
			local c
			for c = 1, perpage do
				local i = (self.page - 1) * perpage + c 
				if i <= self.items then
					y = ypos + self.title_H + (self.spacing * c)
					renderUtf8Text(fb.bb, 50, y, self.face, self.fhash,
						self.toc[i]["title"], true)
				end
			end

			-- draw footer
			y = ypos + self.title_H + (self.spacing * perpage) + self.foot_H
			x = (fb.bb:getWidth() / 2) - 50
			renderUtf8Text(fb.bb, x, y, self.sface, self.sfhash,
				"Page "..self.page.." of "..(math.floor(self.items / perpage)+1), true)
			markerdirty = true
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
		if ev.type == EV_KEY and ev.value == EVENT_VALUE_KEY_PRESS then
			ev.code = adjustFWKey(ev.code)
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
			elseif ev.code == KEY_ENTER or ev.code == KEY_FW_PRESS then
				return self.toc[perpage*(self.page-1)+self.current]["page"]
			elseif ev.code == KEY_BACK then
				return nil
			end
		end
	end
end
