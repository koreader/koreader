require "keys"
require "settings"

PDFReader = {
	-- "constants":
	ZOOM_BY_VALUE = 0,
	ZOOM_FIT_TO_PAGE = -1,
	ZOOM_FIT_TO_PAGE_WIDTH = -2,
	ZOOM_FIT_TO_PAGE_HEIGHT = -3,
	ZOOM_FIT_TO_CONTENT = -4,
	ZOOM_FIT_TO_CONTENT_WIDTH = -5,
	ZOOM_FIT_TO_CONTENT_HEIGHT = -6,

	GAMMA_NO_GAMMA = 1.0,

	-- framebuffer update policy state:
	rcount = 5,
	rcountmax = 5,

	-- zoom state:
	globalzoom = 1.0,
	globalzoommode = -1, -- ZOOM_FIT_TO_PAGE

	-- gamma setting:
	globalgamma = 1.0,   -- GAMMA_NO_GAMMA

	-- size of current page for current zoom level in pixels
	fullwidth = 0,
	fullheight = 0,
	offset_x = 0,
	offset_y = 0,

	-- set panning distance
	shift_x = 100,
	shift_y = 50,
	pan_by_page = false, -- using shift_[xy] or width/height

	-- keep track of input state:
	shiftmode = false, -- shift pressed
	altmode = false,   -- alt pressed

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

function PDFReader:draworcache(no, zoom, offset_x, offset_y, width, height, gamma)
	-- hash draw state
	local hash = self:cachehash(no, zoom, offset_x, offset_y, width, height, gamma)
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
function PDFReader:cachehash(no, zoom, offset_x, offset_y, width, height, gamma)
	-- TODO (?): make this a "real" hash...
	return no..'_'..zoom..'_'..offset_x..','..offset_y..'-'..width..'x'..height..'_'..gamma;
end

-- blank the cache
function PDFReader:clearcache()
	self.cache = {}
end

-- open a PDF file and its settings store
function PDFReader:open(filename, password)
	if self.doc ~= nil then
		self.doc:close()
	end
	if self.settings ~= nil then
		self.settings:close()
	end

	self.doc = pdf.openDocument(filename, password or "")
	if self.doc ~= nil then
		self.settings = DocSettings:open(filename)
		self:clearcache()
	end
end

-- set viewer state according to zoom state
function PDFReader:setzoom(page)
	local dc = pdf.newDC()
	local pwidth, pheight = page:getSize(self.nulldc)

	if self.globalzoommode == self.ZOOM_FIT_TO_PAGE then
		self.globalzoom = width / pwidth ----------
		self.offset_x = 0
		self.offset_y = (height - (self.globalzoom * pheight)) / 2
		if height / pheight < self.globalzoom then
			self.globalzoom = height / pheight
			self.offset_x = (width - (self.globalzoom * pwidth)) / 2
			self.offset_y = 0
		end
	elseif self.globalzoommode == self.ZOOM_FIT_TO_PAGE_WIDTH then
		self.globalzoom = width / pwidth
		self.offset_x = 0
		self.offset_y = (height - (self.globalzoom * pheight)) / 2
	elseif self.globalzoommode == self.ZOOM_FIT_TO_PAGE_HEIGHT then
		self.globalzoom = height / pheight
		self.offset_x = (width - (self.globalzoom * pwidth)) / 2
		self.offset_y = 0
	elseif self.globalzoommode == self.ZOOM_FIT_TO_CONTENT then
		local x0, y0, x1, y1 = page:getUsedBBox()
		self.globalzoom = width / (x1 - x0)
		self.offset_x = -1 * x0 * self.globalzoom
		self.offset_y = -1 * y0 * self.globalzoom + (height - (self.globalzoom * (y1 - y0))) / 2
		if height / (y1 - y0) < self.globalzoom then
			self.globalzoom = height / (y1 - y0)
			self.offset_x = -1 * x0 * self.globalzoom + (width - (self.globalzoom * (x1 - x0))) / 2
			self.offset_y = -1 * y0 * self.globalzoom
		end
	elseif self.globalzoommode == self.ZOOM_FIT_TO_CONTENT_WIDTH then
		local x0, y0, x1, y1 = page:getUsedBBox()
		self.globalzoom = width / (x1 - x0)
		self.offset_x = -1 * x0 * self.globalzoom
		self.offset_y = -1 * y0 * self.globalzoom + (height - (self.globalzoom * (y1 - y0))) / 2
	elseif self.globalzoommode == self.ZOOM_FIT_TO_CONTENT_HEIGHT then
		local x0, y0, x1, y1 = page:getUsedBBox()
		self.globalzoom = height / (y1 - y0)
		self.offset_x = -1 * x0 * self.globalzoom + (width - (self.globalzoom * (x1 - x0))) / 2
		self.offset_y = -1 * y0 * self.globalzoom
	end
	dc:setZoom(self.globalzoom)
	dc:setOffset(self.offset_x, self.offset_y)
	self.fullwidth, self.fullheight = page:getSize(dc)

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
		slot = self:draworcache(no,self.globalzoommode,self.offset_x,self.offset_y,width,height,self.globalgamma)
	else
		slot = self:draworcache(no,self.globalzoom,self.offset_x,self.offset_y,width,height,self.globalgamma)
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

-- change current page and cache next page after rendering
function PDFReader:goto(no)
	if no < 1 or no > self.doc:getPages() then
		return
	end
	self.pageno = no
	self:show(no)
	if no < self.doc:getPages() then
		if self.globalzoommode ~= self.ZOOM_BY_VALUE then
			-- pre-cache next page
			self:draworcache(no+1,self.globalzoommode,self.offset_x,self.offset_y,width,height,self.globalgamma)
		else
			self:draworcache(no,self.globalzoom,self.offset_x,self.offset_y,width,height,self.globalgamma)
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

-- wait for input and handle it
function PDFReader:inputloop()
	while 1 do
		local ev = input.waitForEvent()
		if ev.type == EV_KEY and ev.value == EVENT_VALUE_KEY_PRESS then
			local secs, usecs = util.gettime()
			if ev.code == KEY_SHIFT then
				self.shiftmode = true
			elseif ev.code == KEY_ALT then
				self.altmode = true
			elseif ev.code == KEY_PGFWD then
				if self.shiftmode then
					self:setglobalzoom(self.globalzoom*1.2)
				elseif altmode then
					self:setglobalzoom(self.globalzoom*1.1)
				else
					self:goto(self.pageno + 1)
				end
			elseif ev.code == KEY_PGBCK then
				if self.shiftmode then
					self:setglobalzoom(self.globalzoom*0.8)
				elseif altmode then
					self:setglobalzoom(self.globalzoom*0.9)
				else
					self:goto(self.pageno - 1)
				end
			elseif ev.code == KEY_BACK then
				self.settings:savesetting("last_page", self.pageno)
				self.settings:close()
				return
			elseif ev.code == KEY_VPLUS then
				self:modify_gamma( 1.25 )
			elseif ev.code == KEY_VMINUS then
				self:modify_gamma( 0.8 )
			elseif ev.code == KEY_A then
				if self.shiftmode then
					self:setglobalzoommode(self.ZOOM_FIT_TO_CONTENT)
				else
					self:setglobalzoommode(self.ZOOM_FIT_TO_PAGE)
				end
			elseif ev.code == KEY_S then
				if self.shiftmode then
					self:setglobalzoommode(self.ZOOM_FIT_TO_CONTENT_WIDTH)
				else
					self:setglobalzoommode(self.ZOOM_FIT_TO_PAGE_WIDTH)
				end
			elseif ev.code == KEY_D then
				if self.shiftmode then
					self:setglobalzoommode(self.ZOOM_FIT_TO_CONTENT_HEIGHT)
				else
					self:setglobalzoommode(self.ZOOM_FIT_TO_PAGE_HEIGHT)
				end
			end

			if self.globalzoommode == self.ZOOM_BY_VALUE then
				local x
				local y

				if self.shiftmode then -- shift always moves in small steps
					x = self.shift_x / 2
					y = self.shift_y / 2
				elseif self.altmode then
					x = self.shift_x / 5
					y = self.shift_y / 5
				elseif self.pan_by_page then
					x = self.width  - 5; -- small overlap when moving by page
					y = self.height - 5;
				else
					x = self.shift_x
					y = self.shift_y
				end

				print("offset "..self.offset_x.."*"..self.offset_x.." shift "..x.."*"..y.." globalzoom="..self.globalzoom)

				if ev.code == KEY_FW_LEFT then
					self.offset_x = self.offset_x + x
					self:goto(self.pageno)
				elseif ev.code == KEY_FW_RIGHT then
					self.offset_x = self.offset_x - x
					self:goto(self.pageno)
				elseif ev.code == KEY_FW_UP then
					self.offset_y = self.offset_y + y
					self:goto(self.pageno)
				elseif ev.code == KEY_FW_DOWN then
					self.offset_y = self.offset_y - y
					self:goto(self.pageno)
				elseif ev.code == KEY_FW_PRESS then
					if self.shiftmode then
						self.offset_x = 0
						self.offset_y = 0
						self:goto(pageno)
					else
						self.pan_by_page = not self.pan_by_page
					end
				end
			end

			local nsecs, nusecs = util.gettime()
			local dur = (nsecs - secs) * 1000000 + nusecs - usecs
			print("E: T="..ev.type.." V="..ev.value.." C="..ev.code.." DUR="..dur)
		elseif ev.type == EV_KEY and ev.value == EVENT_VALUE_KEY_RELEASE and ev.code == KEY_SHIFT then
			self.shiftmode = false
		elseif ev.type == EV_KEY and ev.value == EVENT_VALUE_KEY_RELEASE and ev.code == KEY_ALT then
			self.altmode = false
		end
	end
end


