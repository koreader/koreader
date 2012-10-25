require "unireader"
require "inputbox"
require "koptconfig"

konfig = {
	width = G_width,
	height = G_height,
	font_size = 1.0,
	page_margin = 0.06,
	line_spacing = 1.2,
	word_spacing = 0.375,
}

KOPTReader = UniReader:new{}

-- open a PDF/DJVU file and its settings store
function KOPTReader:open(filename)
	-- muPDF manages its own cache, set second parameter
	-- to the maximum size you want it to grow
	local file_type = string.lower(string.match(filename, ".+%.([^.]+)") or "")
	
	if file_type == "pdf" then
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
		
	elseif file_type == "djvu" then
		if not validDJVUFile(filename) then
			return false, "Not a valid DjVu file"
		end

		local ok
		ok, self.doc = pcall(djvu.openDocument, filename, self.cache_document_size)
		if not ok then
			return ok, self.doc -- this will be the error message instead
		end
		return ok
	end
end

function KOPTReader:drawOrCache(no, preCache)
	-- our general caching strategy is as follows:
	-- #1 goal: we must render the needed area.
	-- #2 goal: we render as much of the requested page as we can
	-- #3 goal: we render the full page
	-- #4 goal: we render next page, too. (TODO)

	-- ideally, this should be factored out and only be called when needed (TODO)
	local ok, page = pcall(self.doc.openPage, self.doc, no)
	local width, height = fb.bb:getWidth(), fb.bb:getHeight()
	if not ok then
		-- TODO: error handling
		return nil
	end
	
	local dc = self:setzoom(page, preCache)
	
	-- check if we have relevant cache contents
	local pagehash = no..'_'..self.kopt_zoom..'_'..self.globalrotate..'_'..self.kopt_gamma..'_'..konfig.line_spacing..'_'..konfig.word_spacing..'K'
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
		
		if self.offset_x < self.min_offset_x then
			self.offset_x = self.min_offset_x
		end
		
		if self.offset_y < self.min_offset_y then
			self.offset_y = self.min_offset_y
		end
		
		-- offset_x_in_page & offset_y_in_page is the offset within zoomed page
		-- they are always positive.
		-- you can see self.offset_x_& self.offset_y as the offset within
		-- draw space, which includes the page. So it can be negative and positive.
		local offset_x_in_page = -self.offset_x
		local offset_y_in_page = -self.offset_y
		if offset_x_in_page < 0 then offset_x_in_page = 0 end
		if offset_y_in_page < 0 then offset_y_in_page = 0 end
		
		Debug("cached page offset_x",self.offset_x,"offset_y",self.offset_y,"min_offset_x",self.min_offset_x,"min_offset_y",self.min_offset_y)
		-- ...and give it more time to live (ttl), except if we're precaching
		if not preCache then
			self.cache[pagehash].ttl = self.cache_max_ttl
		end
		-- ...and return blitbuffer plus offset into it

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
	
	Debug("page::reflowPage:", "width:", width, "height:", height)
	self.fullwidth, self.fullheight, self.kopt_zoom = page:reflow(dc, self.render_mode, width, height, konfig.line_spacing, konfig.word_spacing)
	self.globalzoom_orig = self.kopt_zoom
	Debug("page::reflowPage:", "fullwidth:", self.fullwidth, "fullheight:", self.fullheight, "zoom:", self.kopt_zoom)
	
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
	
	self.min_offset_x = fb.bb:getWidth() - self.cache[pagehash].w
	self.min_offset_y = fb.bb:getHeight() - self.cache[pagehash].h
	if(self.min_offset_x > 0) then
			self.min_offset_x = 0
		end
	if(self.min_offset_y > 0) then
		self.min_offset_y = 0
	end
	
	if self.offset_x < self.min_offset_x then
		self.offset_x = self.min_offset_x
	end
	
	if self.offset_y < self.min_offset_y then
		self.offset_y = self.min_offset_y
	end
	
	local offset_x_in_page = -self.offset_x
	local offset_y_in_page = -self.offset_y
	if offset_x_in_page < 0 then offset_x_in_page = 0 end
	if offset_y_in_page < 0 then offset_y_in_page = 0 end
	
	-- return hash and offset within blitbuffer
	return pagehash,
		offset_x_in_page - tile.x,
		offset_y_in_page - tile.y
end

-- set viewer state according to zoom state
function KOPTReader:setzoom(page, preCache)
	local dc = DrawContext.new()
		
	if(self.min_offset_x > 0) then
		self.min_offset_x = 0
	end
	if(self.min_offset_y > 0) then
		self.min_offset_y = 0
	end
	
	dc:setZoom(self.kopt_zoom)
	Debug("setzoom:", "globalzoom_orig", self.globalzoom_orig)
	
	if self.kopt_gamma ~= self.GAMMA_NO_GAMMA then
		Debug("gamma correction: ", self.kopt_gamma)
		dc:setGamma(self.kopt_gamma)
	end
	
	return dc
end	

-- adjust zoom state and trigger re-rendering
function KOPTReader:setGlobalZoom(zoom)
	if self.kopt_zoom ~= zoom then
		local last_zoom = self.kopt_zoom
		self.kopt_zoom = zoom
		-- we will guess the offset_y in zoomed view.
		-- it is not a good enough guess but simple enough.
		self.offset_x = 0
		self.offset_y = self.offset_y*zoom/last_zoom
		self:redrawCurrentPage()
	end
end

-- adjust global gamma setting
function KOPTReader:modifyGamma(factor)
	Debug("modifyGamma, gamma=", self.kopt_gamma, " factor=", factor)
	self.kopt_gamma = self.kopt_gamma * factor * factor;
	InfoMessage:inform(string.format("New gamma is %.2f", self.kopt_gamma), nil, 1, MSG_AUX)
	self:redrawCurrentPage()
end

function KOPTReader:nextView()
	local pageno = self.pageno

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

function KOPTReader:prevView()
	local pageno = self.pageno
	
	Debug("preView offset_y", self.offset_y, "min_offset_y", self.min_offset_y)
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

function KOPTReader:setDefaults()
    self.show_overlap_enable = true
    self.show_links_enable = false
end

-- backup global variables from UniReader
function KOPTReader:loadSettings(filename)
	UniReader.loadSettings(self,filename)
	self.kopt_zoom = self.settings:readSetting("kopt_zoom") or 1.0
	self.kopt_gamma = self.settings:readSetting("kopt_gamma") or 1.0
end

function KOPTReader:saveSpecialSettings()
	self.settings:saveSetting("kopt_zoom", self.kopt_zoom)
	self.settings:saveSetting("kopt_gamma", self.kopt_gamma)
end

function KOPTReader:init()
	self:addAllCommands()
	self:adjustCommands()
end

function KOPTReader:reconfigure(configurable)
	konfig.font_size = configurable.font_size
	konfig.page_margin = configurable.page_margin
	konfig.line_spacing = configurable.line_spacing
	konfig.word_spacing = configurable.word_spacing
	self:redrawCurrentPage()
end

function KOPTReader:adjustCommands()
	self.commands:del(KEY_A, nil,"A")
	self.commands:del(KEY_A, MOD_SHIFT, "A")
	self.commands:del(KEY_D, nil,"D")
	self.commands:del(KEY_D, MOD_SHIFT, "D")
	self.commands:del(KEY_S, nil,"S")
	self.commands:del(KEY_S, MOD_SHIFT, "S")
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
	self.commands:del(KEY_M, nil, "M")
	self.commands:add({KEY_F,KEY_AA}, nil, "F",
		"change koptreader configuration",
		function(self)
			KOPTConfig:config(KOPTReader.reconfigure, self)
			self:redrawCurrentPage()
		end
	)
end
