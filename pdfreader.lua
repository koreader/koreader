require "unireader"
require "inputbox"

PDFReader = UniReader:new{
	-- "constants":
	REFLOW_MODE_ON = 1,
	REFLOW_MODE_OFF = 0,
	
	-- "pdf page":
	src_page_dpi = 300,
	
	-- "reflow state":
	reflow_mode_enable = true,
}

-- open a PDF file and its settings store
function PDFReader:open(filename)
	-- muPDF manages its own cache, set second parameter
	-- to the maximum size you want it to grow
	local ok
	ok, self.doc = pcall(pdf.openDocument, filename, self.cache_document_size)
	if not ok then
		return false, self.doc -- will contain error message
	end
	if self.doc:needsPassword() then
		local password = InputBox:input(G_height-100, 100, "Pass:")
		if not password or not self.doc:authenticatePassword(password) then
			self.doc:close()
			self.doc = nil
			return false, "wrong or missing password"
		end
		-- password wrong or not entered
	end
	local ok, err = pcall(self.doc.getPages, self.doc)
	if not ok then
		-- for PDFs, they might trigger errors later when accessing page tree
		self.doc:close()
		self.doc = nil
		return false, "damaged page tree"
	end
	return true
end

----------------------------------------------------
-- highlight support 
----------------------------------------------------
function PDFReader:getText(pageno)
	local ok, page = pcall(self.doc.openPage, self.doc, pageno)
	if not ok then
		-- TODO: error handling
		return nil
	end
	local text = page:getPageText()
	--Debug("## page:getPageText "..dump(text)) -- performance impact on device
	page:close()
	return text
end

function PDFReader:getPageLinks(pageno)
	local ok, page = pcall(self.doc.openPage, self.doc, pageno)
	if not ok then
		-- TODO: error handling
		return nil
	end
	local links = page:getPageLinks()
	Debug("## page:getPageLinks ", links)
	page:close()
	return links
end

----------------------------------------------------
-- reflow support
----------------------------------------------------
function PDFReader:drawOrCache(no, preCache)
	-- our general caching strategy is as follows:
	-- #1 goal: we must render the needed area.
	-- #2 goal: we render as much of the requested page as we can
	-- #3 goal: we render the full page
	-- #4 goal: we render next page, too. (TODO)
	
	if not self.reflow_mode_enable then
		return UniReader.drawOrCache(self, no, preCache)
	end
	
	local pg_w = G_width / ( self.doc:getPages() )
	local page_indicator = function()
		if Debug('page_indicator',no) then
			fb.bb:invertRect( pg_w*(no-1),0, pg_w,10)
			fb:refresh(1,     pg_w*(no-1),0, pg_w,10)
		end
	end
	page_indicator()

	-- ideally, this should be factored out and only be called when needed (TODO)
	local ok, page = pcall(self.doc.openPage, self.doc, no)
	local width, height = G_width, G_height
	if not ok then
		-- TODO: error handling
		return nil
	end
	
	local dc = self:rfzoom(page, preCache)

	-- offset_x_in_page & offset_y_in_page is the offset within zoomed page
	-- they are always positive.
	-- you can see self.offset_x_& self.offset_y as the offset within
	-- draw space, which includes the page. So it can be negative and positive.
	local offset_x_in_page = -self.offset_x
	local offset_y_in_page = -self.offset_y
	if offset_x_in_page < 0 then offset_x_in_page = 0 end
	if offset_y_in_page < 0 then offset_y_in_page = 0 end
	
	-- check if we have relevant cache contents
	local reflow_mode
	if reflow_mode_enable then 
		reflow_mode = self.REFLOW_MODE_ON
	else
		reflow_mode = self.REFLOW_MODE_OFF
	end
	local pagehash = no..'_'..reflow_mode..'_'..self.globalzoom..'_'..self.globalrotate..'_'..self.globalgamma
	Debug('page hash', pagehash)
	if self.cache[pagehash] ~= nil then
		-- we have something in cache
		-- requested part is within cached tile
		-- ...so properly clean page
		page:close()
		self.min_offset_x = fb.bb:getWidth() - self.cache[pagehash].w
		self.min_offset_y = fb.bb:getHeight() - self.cache[pagehash].h
		if(self.min_offset_x > 0) then
			self.min_offset_x = 0
		end
		if(self.min_offset_y > 0) then
			self.min_offset_y = 0
		end
		-- ...and give it more time to live (ttl), except if we're precaching
		if not preCache then
			self.cache[pagehash].ttl = self.cache_max_ttl
		end
		-- ...and return blitbuffer plus offset into it

		page_indicator()

		return pagehash,
			offset_x_in_page - self.cache[pagehash].x,
			offset_y_in_page - self.cache[pagehash].y
	end
	
	-- okay, we do not have it in cache yet.
	-- so render now.
	-- start off with the requested area
	local tile = { x = offset_x_in_page, y = offset_y_in_page,
					w = width, h = height }
	-- can we cache the full page?
	local max_cache = self.cache_max_memsize
	if preCache then
		max_cache = max_cache - self.cache[self.pagehash].size
	end
	
	self.fullwidth, self.fullheight = page:reflow(dc)
	Debug("page::reflowPage:", "width:", self.fullwidth, "height:", self.fullheight)
	
	if (self.fullwidth * self.fullheight / 2) <= max_cache then
		-- yes we can, so do this with offset 0, 0
		tile.x = 0
		tile.y = 0
		tile.w = self.fullwidth
		tile.h = self.fullheight
	else
		if not preCache then
			Debug("ERROR not enough memory in cache left, probably a bug.")
		end
		return nil
	end
	self:cacheClaim(tile.w * tile.h / 2);
	self.cache[pagehash] = {
		x = tile.x,
		y = tile.y,
		w = tile.w,
		h = tile.h,
		ttl = self.cache_max_ttl,
		size = tile.w * tile.h / 2,
		bb = Blitbuffer.new(tile.w, tile.h)
	}
	--Debug ("new biltbuffer:"..dump(self.cache[pagehash]))
	dc:setOffset(-tile.x, -tile.y)
	Debug("page::drawReflowedPage:", "rendering page:", no, "width:", self.cache[pagehash].w, "height:", self.cache[pagehash].h)
	page:rfdraw(dc, self.cache[pagehash].bb)
	page:close()

	page_indicator()

	-- return hash and offset within blitbuffer
	return pagehash,
		offset_x_in_page - tile.x,
		offset_y_in_page - tile.y
end

-- set viewer state according to zoom state
function PDFReader:rfzoom(page, preCache)
	--self.fullwidth_orig, self.fullheight_orig = self.fullwidth, self.fullheight
	-- Bugfix: self.cur_bbox is set with unflowed page size
	--local dc = UniReader.setzoom(self, page, preCache)
	local dc = DrawContext.new()
	--self.fullwidth, self.fullheight = self.fullwidth_orig, self.fullheight_orig
	--self.globalzoom_mode = self.ZOOM_BY_VALUE
	self.globalzoom_mode = self.ZOOM_FIT_TO_PAGE_WIDTH
	self.globalzoom = 1
	
	Debug("rfzoom: fullheight", self.fullheight)
	if(self.min_offset_x > 0) then
		self.min_offset_x = 0
	end
	if(self.min_offset_y > 0) then
		self.min_offset_y = 0
	end
	
	if self.globalgamma ~= self.GAMMA_NO_GAMMA then
		Debug("gamma correction: ", self.globalgamma)
		dc:setGamma(self.globalgamma)
	end
	
	return dc
end

-- command definitions
function PDFReader:addAllCommands()
	UniReader.addAllCommands(self)
	self.commands:addGroup("< >",{
		Keydef:new(KEY_PGBCK,nil),Keydef:new(KEY_LPGBCK,nil),
		Keydef:new(KEY_PGFWD,nil),Keydef:new(KEY_LPGFWD,nil)},
		"previous/next page",
		function(unireader,keydef)
			self.offset_y = 0
			unireader:goto(
			(keydef.keycode == KEY_PGBCK or keydef.keycode == KEY_LPGBCK)
			and unireader:prevView() or unireader:nextView())
		end)
		
	self.commands:add(KEY_R, nil, "R",
		"toggle reflow page",
		function(pdfreader)
			pdfreader.reflow_mode_enable = not pdfreader.reflow_mode_enable
			if pdfreader.reflow_mode_enable then
				InfoMessage:inform("Turning reflow ON", nil, 1, MSG_AUX)
			else
				InfoMessage:inform("Turning reflow OFF", nil, 1, MSG_AUX)
			end
			self.settings:saveSetting("reflow_mode_enable", pdfreader.reflow_mode_enable)
			self:redrawCurrentPage()
		end)
end
