require "unireader"
require "inputbox"

PDFReader = UniReader:new{
	-- "reflow state":
	reflow_mode_enable = false,
	
	-- "save/restore states when alternating reflow state ":
	last_mode_states = {}
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

	-- ideally, this should be factored out and only be called when needed (TODO)
	local ok, page = pcall(self.doc.openPage, self.doc, no)
	local width, height = G_width, G_height
	if not ok then
		-- TODO: error handling
		return nil
	end
	
	local dc = self:rfzoom(page, preCache)
	self.globalzoom_orig = self.globalzoom

	-- offset_x_in_page & offset_y_in_page is the offset within zoomed page
	-- they are always positive.
	-- you can see self.offset_x_& self.offset_y as the offset within
	-- draw space, which includes the page. So it can be negative and positive.
	local offset_x_in_page = -self.offset_x
	local offset_y_in_page = -self.offset_y
	if offset_x_in_page < 0 then offset_x_in_page = 0 end
	if offset_y_in_page < 0 then offset_y_in_page = 0 end
	
	-- check if we have relevant cache contents
	local pagehash = no..'_'..(self.reflow_mode_enable and 1 or 0)..'_'..self.globalzoom..'_'..self.globalrotate..'_'..self.globalgamma
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
		
		if self.offset_y < self.min_offset_y then
			self.offset_y = self.min_offset_y
		end
		
		Debug("cached page offset_x",self.offset_x,"offset_y",self.offset_y,"min_offset_x",self.min_offset_x,"min_offset_y",self.min_offset_y)
		-- ...and give it more time to live (ttl), except if we're precaching
		if not preCache then
			self.cache[pagehash].ttl = self.cache_max_ttl
		end
		-- ...and return blitbuffer plus offset into it

		return pagehash,
			--offset_x_in_page - self.cache[pagehash].x,
			--offset_y_in_page - self.cache[pagehash].y
			-self.offset_x - self.cache[pagehash].x,
			-self.offset_y - self.cache[pagehash].y
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
	
	self.fullwidth, self.fullheight = page:reflow(dc, self.globalzoom)
	--self.fullwidth, self.fullheight = page:reflow(dc, self.globalzoom)
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

	-- return hash and offset within blitbuffer
	return pagehash,
		offset_x_in_page - tile.x,
		offset_y_in_page - tile.y
end

-- set viewer state according to zoom state
function PDFReader:rfzoom(page, preCache)

	self.globalzoom_mode = self.ZOOM_BY_VALUE
	
	if(self.min_offset_x > 0) then
		self.min_offset_x = 0
	end
	if(self.min_offset_y > 0) then
		self.min_offset_y = 0
	end
	
	local dc = DrawContext.new()
	if self.globalgamma ~= self.GAMMA_NO_GAMMA then
		Debug("gamma correction: ", self.globalgamma)
		dc:setGamma(self.globalgamma)
	end
	
	return dc
end	

-- "save/restore states when alternating reflow state ":
function PDFReader:restoreReaderStates()
	local tmp_states = {
		globalzoom = self.globalzoom,
		offset_x = self.offset_x,
		offset_y = self.offset_y,
		dest_x = self.dest_x,
		dest_y = self.dest_y,
		min_offset_x = self.min_offset_x,
		min_offset_y = self.min_offset_y,
		pan_x = self.pan_x,
		pan_y = self.pan_y
	}
	
	self.globalzoom = self.last_mode_states.globalzoom
	self.offset_x = self.last_mode_states.offset_x
	self.offset_y = self.last_mode_states.offset_y
	self.dest_x = self.last_mode_states.dest_x
	self.dest_y = self.last_mode_states.dest_y
	self.min_offset_x = self.last_mode_states.min_offset_x
	self.min_offset_y = self.last_mode_states.min_offset_y
	self.pan_x = self.last_mode_states.pan_x
	self.pan_y = self.last_mode_states.pan_y
	
	self.last_mode_states = tmp_states
end

function PDFReader:rfNextView()
	local pageno = self.pageno

	Debug("nextView last_globalzoom_mode=", self.last_globalzoom_mode, " globalzoom_mode=", self.globalzoom_mode)
	Debug("nextView offset_y", self.offset_y, "min_offset_y", self.min_offset_y)
	if self.offset_y <= self.min_offset_y then
		-- hit content bottom, turn to next page top
		self.offset_x = 0
		self.offset_y = 0
		pageno = pageno + 1
	else
		-- goto next view of current page
		local offset_y_dec = self.offset_y - G_height + self.pan_overlap_vertical
		self.offset_y = offset_y_dec > self.min_offset_y and offset_y_dec or self.min_offset_y
	end
	
	return pageno
end

function PDFReader:rfPrevView()
	local pageno = self.pageno

	Debug("prevView last_globalzoom_mode=", self.last_globalzoom_mode, " globalzoom_mode=", self.globalzoom_mode)
	if self.offset_y >= 0 then
		-- hit content top, turn to previous page bottom
		self.offset_x = 0
		self.offset_y = -2012534
		pageno = pageno - 1
	else
		-- goto previous view of current page
		local offset_y_inc = self.offset_y + G_height - self.pan_overlap_vertical
		self.offset_y = offset_y_inc < 0 and offset_y_inc or 0
	end

	return pageno
end

-- command definitions
function PDFReader:init()
	self:addAllCommands()
	self:adjustPDFReaderCommand(self.reflow_mode_enable)
	-- init last_mode_states. maybe somewhere else?
	self.last_mode_states = {
		globalzoom = self.globalzoom,
		offset_x = self.offset_x,
		offset_y = self.offset_y,
		dest_x = self.dest_x,
		dest_y = self.dest_y,
		min_offset_x = self.min_offset_x,
		min_offset_y = self.min_offset_y,
		pan_x = self.pan_x,
		pan_y = self.pan_y
	}
end

function PDFReader:adjustPDFReaderCommand(reflow_mode)
	if reflow_mode then
		self.commands:del(KEY_A, nil,"A")
		self.commands:del(KEY_A, MOD_SHIFT, "A")
		self.commands:del(KEY_D, nil,"D")
		self.commands:del(KEY_D, MOD_SHIFT, "D")
		self.commands:del(KEY_F, nil,"F")
		self.commands:del(KEY_F, MOD_SHIFT, "F")
		self.commands:del(KEY_Z, nil,"Z")
		self.commands:del(KEY_Z, MOD_ALT, "Z")
		self.commands:del(KEY_Z, MOD_SHIFT, "Z")
		self.commands:del(KEY_X, nil,"X")
		self.commands:del(KEY_X, MOD_SHIFT, "X")
		self.commands:del(KEY_N, nil,"N")
		self.commands:del(KEY_N, MOD_SHIFT, "N")
		self.commands:del(KEY_L, nil, "L")
		self.commands:del(KEY_L, MOD_SHIFT, "L")
		self.commands:addGroup("< >",{
			Keydef:new(KEY_PGBCK,nil),Keydef:new(KEY_LPGBCK,nil),
			Keydef:new(KEY_PGFWD,nil),Keydef:new(KEY_LPGFWD,nil)},
			"previous/next page",
			function(pdfreader,keydef)
				pdfreader:goto(
				(keydef.keycode == KEY_PGBCK or keydef.keycode == KEY_LPGBCK)
				and pdfreader:rfPrevView() or pdfreader:rfNextView())
			end)
	else
		self:addAllCommands()
	end
	self.commands:add(KEY_R, nil, "R",
		"toggle reflow mode",
		function(pdfreader)
			pdfreader.reflow_mode_enable = not pdfreader.reflow_mode_enable
			pdfreader:adjustPDFReaderCommand(pdfreader.reflow_mode_enable)
			pdfreader:restoreReaderStates()
			if pdfreader.reflow_mode_enable then
				InfoMessage:inform("Turning reflow ON", nil, 1, MSG_AUX)
			else
				InfoMessage:inform("Turning reflow OFF", nil, 1, MSG_AUX)
			end
			self:redrawCurrentPage()
		end)
end
