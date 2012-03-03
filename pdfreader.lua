require "keys"
require "settings"
--require "tocmenu"
require "selectmenu"

PDFReader = {
	-- "constants":
	ZOOM_BY_VALUE = 0,
	ZOOM_FIT_TO_PAGE = -1,
	ZOOM_FIT_TO_PAGE_WIDTH = -2,
	ZOOM_FIT_TO_PAGE_HEIGHT = -3,
	ZOOM_FIT_TO_CONTENT = -4,
	ZOOM_FIT_TO_CONTENT_WIDTH = -5,
	ZOOM_FIT_TO_CONTENT_HEIGHT = -6,
	ZOOM_FIT_TO_CONTENT_HALF_WIDTH = -7,

	GAMMA_NO_GAMMA = 1.0,

	-- framebuffer update policy state:
	rcount = 5,
	rcountmax = 5,

	-- zoom state:
	globalzoom = 1.0,
	globalzoommode = -1, -- ZOOM_FIT_TO_PAGE

	globalrotate = 0,

	-- gamma setting:
	globalgamma = 1.0,   -- GAMMA_NO_GAMMA

	-- size of current page for current zoom level in pixels
	fullwidth = 0,
	fullheight = 0,
	offset_x = 0,
	offset_y = 0,
	min_offset_x = 0,
	min_offset_y = 0,

	-- set panning distance
	shift_x = 100,
	shift_y = 50,
	pan_by_page = false, -- using shift_[xy] or width/height
	pan_x = 0, -- top-left offset of page when pan activated
	pan_y = 0,
	pan_margin = 20,

	-- the pdf document:
	doc = nil,
	-- the document's setting store:
	settings = nil,

	-- we will use this one often, so keep it "static":
	nulldc = pdf.newDC(),

	-- tile cache configuration:
	cache_max_memsize = 1024*1024*5, -- 5MB tile cache
	cache_item_max_pixels = 1024*1024*2, -- max. size of rendered tiles
	cache_max_ttl = 20, -- time to live
	-- tile cache state:
	cache_current_memsize = 0,
	cache = {},
	jump_stack = {},
}

-- guarantee that we have enough memory in cache
function PDFReader:cacheclaim(size)
	if(size > self.cache_max_memsize) then
		-- we're not allowed to claim this much at all
		error("too much memory claimed")
		return false
	end
	while self.cache_current_memsize + size > self.cache_max_memsize do
		-- repeat this until we have enough free memory
		for k, _ in pairs(self.cache) do
			if self.cache[k].ttl > 0 then
				-- reduce ttl
				self.cache[k].ttl = self.cache[k].ttl - 1
			else
				-- cache slot is at end of life, so kick it out
				self.cache_current_memsize = self.cache_current_memsize - self.cache[k].size
				self.cache[k] = nil
			end
		end
	end
	self.cache_current_memsize = self.cache_current_memsize + size
	return true
end

function PDFReader:draworcache(no, zoom, offset_x, offset_y, width, height, gamma, rotate)
	-- hash draw state
	local hash = self:cachehash(no, zoom, offset_x, offset_y, width, height, gamma, rotate)
	if self.cache[hash] == nil then
		-- not in cache, so prepare cache slot...
		self:cacheclaim(width * height / 2);
		self.cache[hash] = {
			ttl = self.cache_max_ttl,
			size = width * height / 2,
			bb = Blitbuffer.new(width, height)
		}
		-- and draw the page
		local page = self.doc:openPage(no)
		local dc = self:setzoom(page, hash)
		page:draw(dc, self.cache[hash].bb, 0, 0)
		page:close()
	else
		-- we have the page in our cache,
		-- so give it more ttl.
		self.cache[hash].ttl = self.cache_max_ttl
	end
	return hash
end

-- calculate a hash for our current state
function PDFReader:cachehash(no, zoom, offset_x, offset_y, width, height, gamma, rotate)
	-- TODO (?): make this a "real" hash...
	return no..'_'..zoom..'_'..offset_x..','..offset_y..'-'..width..'x'..height..'_'..gamma..'_'..rotate
end

-- blank the cache
function PDFReader:clearcache()
	self.cache = {}
	self.cache_current_memsize = 0
end

-- open a PDF file and its settings store
function PDFReader:open(filename, password)
	self.doc = pdf.openDocument(filename, password or "")
	if self.doc ~= nil then
		self.settings = DocSettings:open(filename)
		local gamma = self.settings:readsetting("gamma")
		if gamma then
			self.globalgamma = gamma
		end
		return true
	end
	return false
end

-- set viewer state according to zoom state
function PDFReader:setzoom(page)
	local dc = pdf.newDC()
	local pwidth, pheight = page:getSize(self.nulldc)

	if self.globalzoommode == self.ZOOM_FIT_TO_PAGE
	or self.globalzoommode == self.ZOOM_FIT_TO_CONTENT then
		self.globalzoom = width / pwidth
		self.offset_x = 0
		self.offset_y = (height - (self.globalzoom * pheight)) / 2
		if height / pheight < self.globalzoom then
			self.globalzoom = height / pheight
			self.offset_x = (width - (self.globalzoom * pwidth)) / 2
			self.offset_y = 0
		end
	elseif self.globalzoommode == self.ZOOM_FIT_TO_PAGE_WIDTH
	or self.globalzoommode == self.ZOOM_FIT_TO_CONTENT_WIDTH then
		self.globalzoom = width / pwidth
		self.offset_x = 0
		self.offset_y = (height - (self.globalzoom * pheight)) / 2
	elseif self.globalzoommode == self.ZOOM_FIT_TO_PAGE_HEIGHT
	or self.globalzoommode == self.ZOOM_FIT_TO_CONTENT_HEIGHT then
		self.globalzoom = height / pheight
		self.offset_x = (width - (self.globalzoom * pwidth)) / 2
		self.offset_y = 0
	end
	if self.globalzoommode == self.ZOOM_FIT_TO_CONTENT then
		local x0, y0, x1, y1 = page:getUsedBBox()
		if (x1 - x0) < pwidth then
			self.globalzoom = width / (x1 - x0)
			self.offset_x = -1 * x0 * self.globalzoom
			self.offset_y = -1 * y0 * self.globalzoom + (height - (self.globalzoom * (y1 - y0))) / 2
			if height / (y1 - y0) < self.globalzoom then
				self.globalzoom = height / (y1 - y0)
				self.offset_x = -1 * x0 * self.globalzoom + (width - (self.globalzoom * (x1 - x0))) / 2
				self.offset_y = -1 * y0 * self.globalzoom
			end
		end
	elseif self.globalzoommode == self.ZOOM_FIT_TO_CONTENT_WIDTH then
		local x0, y0, x1, y1 = page:getUsedBBox()
		if (x1 - x0) < pwidth then
			self.globalzoom = width / (x1 - x0)
			self.offset_x = -1 * x0 * self.globalzoom
			self.offset_y = -1 * y0 * self.globalzoom + (height - (self.globalzoom * (y1 - y0))) / 2
		end
	elseif self.globalzoommode == self.ZOOM_FIT_TO_CONTENT_HEIGHT then
		local x0, y0, x1, y1 = page:getUsedBBox()
		if (y1 - y0) < pheight then
			self.globalzoom = height / (y1 - y0)
			self.offset_x = -1 * x0 * self.globalzoom + (width - (self.globalzoom * (x1 - x0))) / 2
			self.offset_y = -1 * y0 * self.globalzoom
		end
	elseif self.globalzoommode == self.ZOOM_FIT_TO_CONTENT_HALF_WIDTH then
		local x0, y0, x1, y1 = page:getUsedBBox()
		self.globalzoom = width / (x1 - x0 + self.pan_margin)
		self.offset_x = -1 * x0 * self.globalzoom * 2 + self.pan_margin
		self.globalzoom = height / (y1 - y0)
		self.offset_y = -1 * y0 * self.globalzoom * 2 + self.pan_margin
		self.globalzoom = width / (x1 - x0 + self.pan_margin) * 2
		print("column mode offset:"..self.offset_x.."*"..self.offset_y.." zoom:"..self.globalzoom);
		self.globalzoommode = self.ZOOM_BY_VALUE -- enable pan mode
		self.pan_x = self.offset_x
		self.pan_y = self.offset_y
		self.pan_by_page = true
	end
	dc:setZoom(self.globalzoom)
	dc:setRotate(self.globalrotate);
	dc:setOffset(self.offset_x, self.offset_y)
	self.fullwidth, self.fullheight = page:getSize(dc)
	self.min_offset_x = fb.bb:getWidth() - self.fullwidth
	self.min_offset_y = fb.bb:getHeight() - self.fullheight
	if(self.min_offset_x > 0) then
		self.min_offset_x = 0
	end
	if(self.min_offset_y > 0) then
		self.min_offset_y = 0
	end

	-- set gamma here, we don't have any other good place for this right now:
	if self.globalgamma ~= self.GAMMA_NO_GAMMA then
		print("gamma correction: "..self.globalgamma)
		dc:setGamma(self.globalgamma)
	end
	return dc
end

-- render and blit a page
function PDFReader:show(no)
	local slot
	if self.globalzoommode ~= self.ZOOM_BY_VALUE then
		slot = self:draworcache(no,self.globalzoommode,self.offset_x,self.offset_y,width,height,self.globalgamma,self.globalrotate)
	else
		slot = self:draworcache(no,self.globalzoom,self.offset_x,self.offset_y,width,height,self.globalgamma,self.globalrotate)
	end
	fb.bb:blitFullFrom(self.cache[slot].bb)
	if self.rcount == self.rcountmax then
		print("full refresh")
		self.rcount = 1
		fb:refresh(0)
	else
		print("partial refresh")
		self.rcount = self.rcount + 1
		fb:refresh(1)
	end
	self.slot_visible = slot;
end

function PDFReader:add_jump(pageno)
	local jump_item = nil
	-- add current page to jump_stack if no in
	for _t,_v in ipairs(self.jump_stack) do
		if _v.page == pageno then
			jump_item = _v
			table.remove(self.jump_stack, _t)
		elseif _v.page == no then
			-- the page we jumped to should not be show in stack
			table.remove(self.jump_stack, _t)
		end
	end
	-- create a new one if not found
	if not jump_item then
		jump_item = {
			page = pageno,
			datetime = os.date("%Y-%m-%d %H:%M:%S"),
		}
	end
	-- insert at the start
	table.insert(self.jump_stack, 1, jump_item)
	if #self.jump_stack > 10 then
		-- remove the last element to keep the size less than 10
		table.remove(self.jump_stack)
	end
end

-- change current page and cache next page after rendering
function PDFReader:goto(no)
	if no < 1 or no > self.doc:getPages() then
		return
	end

	-- for jump_stack
	if self.pageno and math.abs(self.pageno - no) > 1 then
		self:add_jump(self.pageno)
	end

	self.pageno = no
	self:show(no)
	if no < self.doc:getPages() then
		if self.globalzoommode ~= self.ZOOM_BY_VALUE then
			-- pre-cache next page
			self:draworcache(no+1,self.globalzoommode,self.offset_x,self.offset_y,width,height,self.globalgamma,self.globalrotate)
		else
			self:draworcache(no,self.globalzoom,self.offset_x,self.offset_y,width,height,self.globalgamma,self.globalrotate)
		end
	end
end

-- adjust global gamma setting
function PDFReader:modify_gamma(factor)
	print("modify_gamma, gamma="..self.globalgamma.." factor="..factor)
	self.globalgamma = self.globalgamma * factor;
	self:goto(self.pageno)
end

-- adjust zoom state and trigger re-rendering
function PDFReader:setglobalzoommode(newzoommode)
	if self.globalzoommode ~= newzoommode then
		self.globalzoommode = newzoommode
		self:goto(self.pageno)
	end
end

-- adjust zoom state and trigger re-rendering
function PDFReader:setglobalzoom(zoom)
	if self.globalzoom ~= zoom then
		self.globalzoommode = self.ZOOM_BY_VALUE
		self.globalzoom = zoom
		self:goto(self.pageno)
	end
end

function PDFReader:setrotate(rotate)
	self.globalrotate = rotate
	self:goto(self.pageno)
end

function PDFReader:showTOC()
	toc = self.doc:getTOC()
	local menu_items = {}
	-- build menu items
	for _k,_v in ipairs(toc) do
		table.insert(menu_items,
		("        "):rep(_v.depth-1).._v.title)
	end
	toc_menu = SelectMenu:new{
		menu_title = "Table of Contents",
		item_array = menu_items,
		no_item_msg = "This document does not have a Table of Contents.",
	}
	item_no = toc_menu:choose(0, fb.bb:getHeight())
	if item_no then
		self:goto(toc[item_no].page)
	else
		self:goto(self.pageno)
	end
end

function PDFReader:showJumpStack()
	local menu_items = {}
	for _k,_v in ipairs(self.jump_stack) do
		table.insert(menu_items, 
			_v.datetime.." -> Page ".._v.page)
	end
	jump_menu = SelectMenu:new{
		menu_title = "Jump Keeper      (current page: "..self.pageno..")", 
		item_array = menu_items,
		no_item_msg = "No jump history.",
	}
	item_no = jump_menu:choose(0, fb.bb:getHeight())
	if item_no then
		local jump_item = self.jump_stack[item_no]
		self:goto(jump_item.page)
	else
		self:goto(self.pageno)
	end
end


-- wait for input and handle it
function PDFReader:inputloop()
	while 1 do
		local ev = input.waitForEvent()
		ev.code = adjustKeyEvents(ev)
		if ev.type == EV_KEY and ev.value == EVENT_VALUE_KEY_PRESS then
			local secs, usecs = util.gettime()
			if ev.code == KEY_PGFWD or ev.code == KEY_LPGFWD then
				if Keys.shiftmode then
					self:setglobalzoom(self.globalzoom+0.2)
				elseif Keys.altmode then
					self:setglobalzoom(self.globalzoom+0.1)
				else
					if self.pan_by_page then
						self.offset_x = self.pan_x
						self.offset_y = self.pan_y
					end
					self:goto(self.pageno + 1)
				end
			elseif ev.code == KEY_PGBCK or ev.code == KEY_LPGBCK then
				if Keys.shiftmode then
					self:setglobalzoom(self.globalzoom-0.2)
				elseif Keys.altmode then
					self:setglobalzoom(self.globalzoom-0.1)
				else
					if self.pan_by_page then
						self.offset_x = self.pan_x
						self.offset_y = self.pan_y
					end
					self:goto(self.pageno - 1)
				end
			elseif ev.code == KEY_BACK then
				if Keys.altmode then
					-- altmode, exit pdfreader
					self:clearcache()
					if self.doc ~= nil then
						self.doc:close()
					end
					if self.settings ~= nil then
						self.settings:savesetting("last_page", self.pageno)
						self.settings:savesetting("gamma", self.globalgamma)
						self.settings:close()
					end
					return
				else
					-- not altmode, back to last jump
					if #self.jump_stack ~= 0 then
						self:goto(self.jump_stack[1].page)
					end
				end
			elseif ev.code == KEY_VPLUS then
				self:modify_gamma( 1.25 )
			elseif ev.code == KEY_VMINUS then
				self:modify_gamma( 0.8 )
			elseif ev.code == KEY_A then
				if Keys.shiftmode then
					self:setglobalzoommode(self.ZOOM_FIT_TO_CONTENT)
				else
					self:setglobalzoommode(self.ZOOM_FIT_TO_PAGE)
				end
			elseif ev.code == KEY_S then
				if Keys.shiftmode then
					self:setglobalzoommode(self.ZOOM_FIT_TO_CONTENT_WIDTH)
				else
					self:setglobalzoommode(self.ZOOM_FIT_TO_PAGE_WIDTH)
				end
			elseif ev.code == KEY_D then
				if Keys.shiftmode then
					self:setglobalzoommode(self.ZOOM_FIT_TO_CONTENT_HEIGHT)
				else
					self:setglobalzoommode(self.ZOOM_FIT_TO_PAGE_HEIGHT)
				end
			elseif ev.code == KEY_F then
				self:setglobalzoommode(self.ZOOM_FIT_TO_CONTENT_HALF_WIDTH)
			elseif ev.code == KEY_T then
				self:showTOC()
			elseif ev.code == KEY_B then
				if Keys.shiftmode then
					self:add_jump(self.pageno)
				else
					self:showJumpStack()
				end
			elseif ev.code == KEY_J then
				self:setrotate( self.globalrotate + 10 )
			elseif ev.code == KEY_K then
				self:setrotate( self.globalrotate - 10 )
			end

			if self.globalzoommode == self.ZOOM_BY_VALUE then
				local x
				local y

				if Keys.shiftmode then -- shift always moves in small steps
					x = self.shift_x / 2
					y = self.shift_y / 2
				elseif Keys.altmode then
					x = self.shift_x / 5
					y = self.shift_y / 5
				elseif self.pan_by_page then
					x = width;
					y = height - self.pan_margin; -- overlap for lines which didn't fit
				else
					x = self.shift_x
					y = self.shift_y
				end

				print("offset "..self.offset_x.."*"..self.offset_x.." shift "..x.."*"..y.." globalzoom="..self.globalzoom)
				local old_offset_x = self.offset_x
				local old_offset_y = self.offset_y

				if ev.code == KEY_FW_LEFT then
					self.offset_x = self.offset_x + x
					if self.offset_x > 0 then
						self.offset_x = 0
						if self.pan_by_page and self.pageno > 1 then
							self.offset_x = self.pan_x
							self.offset_y = self.min_offset_y -- bottom
							self:goto(self.pageno - 1)
						end
					end
					if self.pan_by_page then
						self.offset_y = self.min_offset_y
					end
				elseif ev.code == KEY_FW_RIGHT then
					self.offset_x = self.offset_x - x
					if self.offset_x < self.min_offset_x then
						self.offset_x = self.min_offset_x
						if self.pan_by_page and self.pageno < self.doc:getPages() then
							self.offset_x = self.pan_x
							self.offset_y = self.pan_y
							self:goto(self.pageno + 1)
						end
					end
					if self.pan_by_page then
						self.offset_y = self.pan_y
					end
				elseif ev.code == KEY_FW_UP then
					self.offset_y = self.offset_y + y
					if self.offset_y > 0 then
						self.offset_y = 0
					end
				elseif ev.code == KEY_FW_DOWN then
					self.offset_y = self.offset_y - y
					if self.offset_y < self.min_offset_y then
						self.offset_y = self.min_offset_y
					end
				elseif ev.code == KEY_FW_PRESS then
					if Keys.shiftmode then
						if self.pan_by_page then
							self.offset_x = self.pan_x
							self.offset_y = self.pan_y
						else
							self.offset_x = 0
							self.offset_y = 0
						end
					else
						self.pan_by_page = not self.pan_by_page
						if self.pan_by_page then
							self.pan_x = self.offset_x
							self.pan_y = self.offset_y
						end
					end
				end
				if old_offset_x ~= self.offset_x
				or old_offset_y ~= self.offset_y then
						self:goto(self.pageno)
				end
			end

			local nsecs, nusecs = util.gettime()
			local dur = (nsecs - secs) * 1000000 + nusecs - usecs
			print("E: T="..ev.type.." V="..ev.value.." C="..ev.code.." DUR="..dur)
		end
	end
end


