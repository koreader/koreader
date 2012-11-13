require "unireader"
require "inputbox"
require "koptconfig"

Configurable = {
	font_size = 1.2,
	page_margin = 0.06,
	line_spacing = 1.2,
	word_spacing = 0.375,
	quality = 1.0,
	text_wrap = 1,
	defect_size = 1.0,
	trim_page = 1,
	detect_indent = 1,
	multi_threads = 1,
	auto_straighten = 0,
	justification = -1,
	max_columns = 2,
	contrast = 1.0,
	screen_rotation = 0,
}

function Configurable:hash(sep)
	local hash = ""
	for key,value in pairs(self) do
		if type(value) == "number" then
			hash = hash..sep..value
		end
	end
	return hash
end

function Configurable:loadDefaults()
	-- Configurable = {}
	for i=1,#KOPTOptions do
		local key = KOPTOptions[i].name
		local default_item = KOPTOptions[i].default_item
		self[key] = KOPTOptions[i].value[default_item]
	end
end

function Configurable:loadSettings(settings, prefix)
	for key,value in pairs(self) do
		if type(value) == "number" then
			saved_value = settings:readSetting(prefix..key)
			self[key] = (saved_value == nil) and self[key] or saved_value
			--Debug("Configurable:loadSettings", "key", key, "saved value", saved_value,"Configurable.key", self[key])
		end
	end
	--Debug("loaded config:", dump(Configurable))
end

function Configurable:saveSettings(settings, prefix)
	for key,value in pairs(self) do
		if type(value) == "number" then
			settings:saveSetting(prefix..key, value)
		end
	end
end

KOPTReader = UniReader:new{
	configurable = {}
}

function KOPTReader:makeContext()
	local kc = KOPTContext.new()
	kc:setTrim(self.configurable.trim_page)
	kc:setWrap(self.configurable.text_wrap)
	kc:setIndent(self.configurable.detect_indent)
	kc:setRotate(self.configurable.screen_rotation)
	kc:setColumns(self.configurable.max_columns)
	kc:setDeviceDim(G_width, G_height)
	kc:setStraighten(self.configurable.auto_straighten)
	kc:setJustification(self.configurable.justification)
	kc:setZoom(self.configurable.font_size)
	kc:setMargin(self.configurable.page_margin)
	kc:setQuality(self.configurable.quality)
	kc:setContrast(self.configurable.contrast)
	kc:setDefectSize(self.configurable.defect_size)
	kc:setLineSpacing(self.configurable.line_spacing)
	kc:setWordSpacing(self.configurable.word_spacing)
	
	return kc
end

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

-- draw original page
function KOPTReader:showOrigPage()
	local no = self.pageno
	local ok, page = pcall(self.doc.openPage, self.doc, no)
	local width, height = G_width, G_height
	local pwidth, pheight = page:getSize(self.nulldc)
	if not ok then
		-- TODO: error handling
		return nil
	end
	
	local dc = DrawContext.new()
	self.globalzoom = width / pwidth
	if height / pheight < self.globalzoom then
		self.globalzoom = height / pheight
	end
	dc:setZoom(self.globalzoom)
	
	self.offset_x = 0
	self.offset_y = 0
	
	local pagehash = no..'_orig_full_page'
	if self.cache[pagehash] ~= nil then
		page:close()
		
		local bb = self.cache[pagehash].bb
		self.dest_x = 0
		self.dest_y = 0
		if bb:getWidth() < width then
			self.dest_x = (width - (bb:getWidth())) / 2
		end
		if bb:getHeight() < height then
			self.dest_y = (height - (bb:getHeight())) / 2
		end
		if self.dest_x or self.dest_y then
			fb.bb:paintRect(0, 0, width, height, DBACKGROUND_COLOR)
		end
		fb.bb:blitFrom(self.cache[pagehash].bb, self.dest_x, self.dest_y, 0, 0, width, height)
		fb:refresh(1)
		return
	end
	
	local tile = { x = 0, y = 0, w = width, h = height }
	-- can we cache the full page?
	local max_cache = self.cache_max_memsize
	local fullwidth, fullheight = page:getSize(dc)
	if (fullwidth * fullheight / 2) <= max_cache then
		-- yes we can, so do this with offset 0, 0
		tile.x = 0
		tile.y = 0
		tile.w = fullwidth
		tile.h = fullheight
	else
		Debug("ERROR not enough memory in cache left, probably a bug.")
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
	--debug ("# new biltbuffer:"..dump(self.cache[pagehash]))
	dc:setOffset(-tile.x, -tile.y)
	Debug("rendering page", no)
	page:draw(dc, self.cache[pagehash].bb, 0, 0, self.render_mode)
	page:close()
	
	local bb = self.cache[pagehash].bb
	self.dest_x = 0
	self.dest_y = 0
	if bb:getWidth() < width then
		self.dest_x = (width - (bb:getWidth())) / 2
	end
	if bb:getHeight() < height then
		self.dest_y = (height - (bb:getHeight())) / 2
	end
	if self.dest_x or self.dest_y then
		fb.bb:paintRect(0, 0, width, height, DBACKGROUND_COLOR)
	end
	fb.bb:blitFrom(bb, self.dest_x, self.dest_y, 0, 0, width, height)
	fb:refresh(1)
end

function KOPTReader:drawOrCache(no, preCache)
	-- our general caching strategy is as follows:
	-- #1 goal: we must render the needed area.
	-- #2 goal: we render as much of the requested page as we can
	-- #3 goal: we render the full page
	-- #4 goal: we render next page, too. (TODO)

	-- ideally, this should be factored out and only be called when needed (TODO)
	local ok, page = pcall(self.doc.openPage, self.doc, no)
	local width, height = G_width, G_height
	if not ok then
		-- TODO: error handling
		return nil
	end
	
	local kc = self:getContext(page, no, preCache)
	self.globalzoom_mode = self.ZOOM_FIT_TO_CONTENT_WIDTH_PAN
	-- check if we have relevant cache contents
	local bbox = self.cur_bbox
	local pagehash = no..self.configurable:hash('_')..'_'..bbox.x0..'_'..bbox.y0..'_'..bbox.x1..'_'..bbox.y1
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
		
		if self.offset_y == -2012534 then
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
		self.cached_pagehash = pagehash
		self.cached_offset_x = offset_x_in_page - self.cache[pagehash].x
		self.cached_offset_y = offset_y_in_page - self.cache[pagehash].y
		return pagehash,
			offset_x_in_page - self.cache[pagehash].x,
			offset_y_in_page - self.cache[pagehash].y
	end
	
	-- okay, we do not have it in cache yet.
	-- so render now.
	-- start off with the requested area
	
	if preCache and self.configurable.multi_threads == 1 then
		Debug("start precache on page", no)
		if self.precache_kc ~= nil then
			if self.precache_kc:isPreCache() == 1 then
				Debug("waiting threaded precache to finish.")
				return
			else
				Debug("threaded preCache is finished.")
				return self:drawToCache(self.precache_kc, page, pagehash, preCache)
			end
		else
			self.precache_kc = kc
			self.precache_kc:setPreCache()
			page:reflow(self.precache_kc, self.render_mode)
			Debug("threaded preCache is returned.")
		end
	else
		if self.precache_kc and self.cache[self.cached_pagehash] then
			Debug("How about stay here and wait?")
			return self.cached_pagehash, self.cached_offset_x, self.cached_offset_y
		else
			page:reflow(kc, self.render_mode)
			return self:drawToCache(kc, page, pagehash, preCache)
		end
	end
end

function KOPTReader:drawToCache(kc, page, pagehash, preCache)
	local tile = { x = offset_x_in_page, y = offset_y_in_page,
					w = width, h = height }
	-- can we cache the full page?
	local max_cache = self.cache_max_memsize
	if preCache then
		max_cache = max_cache - self.cache[self.pagehash].size
	end
	
	self.fullwidth, self.fullheight = kc:getPageDim()
	self.reflow_zoom = kc:getZoom()
	Debug("page::reflowPage:", "fullwidth:", self.fullwidth, "fullheight:", self.fullheight)
	
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
	Debug("page::drawReflowedPage:", "rendering page:", no, "width:", self.cache[pagehash].w, "height:", self.cache[pagehash].h)
	page:rfdraw(kc, self.cache[pagehash].bb)
	page:close()
	
	if preCache then
		self.precache_kc = nil
	end
	
	self.min_offset_x = fb.bb:getWidth() - self.cache[pagehash].w
	self.min_offset_y = fb.bb:getHeight() - self.cache[pagehash].h
	if(self.min_offset_x > 0) then
			self.min_offset_x = 0
		end
	if(self.min_offset_y > 0) then
		self.min_offset_y = 0
	end

	if self.offset_y == -2012534 then
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

-- get reflow context
function KOPTReader:getContext(page, pnumber, preCache)
	local kc = self:makeContext()
	local pwidth, pheight = page:getSize(self.nulldc)
	local width, height = G_width, G_height
	-- rounds down pwidth and pheight to 2 decimals, because page:getUsedBBox() returns only 2 decimals.
	-- without it, later check whether to use margins will fail for some documents
	pwidth = math.floor(pwidth * 100) / 100
	pheight = math.floor(pheight * 100) / 100
	Debug("preCache:", preCache and "true" or "false")
	Debug("page::getSize",pwidth,pheight)
	
	local x0, y0, x1, y1 = page:getUsedBBox()
	if x0 == 0.01 and y0 == 0.01 and x1 == -0.01 and y1 == -0.01 then
		x0 = 0
		y0 = 0
		x1 = pwidth
		y1 = pheight
	end
	if x1 == 0 then x1 = pwidth end
	if y1 == 0 then y1 = pheight end
	-- clamp to page BBox
	if x0 < 0 then x0 = 0 end
	if x1 > pwidth then x1 = pwidth end
	if y0 < 0 then y0 = 0 end
	if y1 > pheight then y1 = pheight end

	if self.bbox.enabled then
		Debug("ORIGINAL page::getUsedBBox", x0,y0, x1,y1 )
		local bbox = self.bbox[pnumber] -- exact

		local oddEven = self:oddEven(pnumber)
		if bbox ~= nil then
			Debug("bbox from", pnumber)
		else
			bbox = self.bbox[oddEven] -- odd/even
		end
		if bbox ~= nil then -- last used up to this page
			Debug("bbox from", oddEven)
		else
			for i = 0,pnumber do
				bbox = self.bbox[ pnumber - i ]
				if bbox ~= nil then
					Debug("bbox from", pnumber - i)
					break
				end
			end
		end
		if bbox ~= nil then
			x0 = bbox["x0"]
			y0 = bbox["y0"]
			x1 = bbox["x1"]
			y1 = bbox["y1"]
		end
	end

	Debug("page::getUsedBBox", x0, y0, x1, y1 ) 
	if kc:getTrim() == 1 then
		kc:setBBox(0, 0, pwidth, pheight)
	else
		kc:setBBox(x0, y0, x1, y1)
	end

	self.cur_bbox = {
		["x0"] = x0,
		["y0"] = y0,
		["x1"] = x1,
		["y1"] = y1,
	}
	Debug("cur_bbox", self.cur_bbox)
	
	return kc
end

function KOPTReader:nextView()
	local pageno = self.pageno

	Debug("nextView offset_y", self.offset_y, "min_offset_y", self.min_offset_y)
	if self.offset_y <= self.min_offset_y then
		-- hit content bottom, turn to next page top
		local numpages = self.doc:getPages()
		if pageno < numpages then
			self.offset_x = 0
			self.offset_y = 0
		end
		pageno = pageno + 1
	else
		-- goto next view of current page
		self.offset_y = self.offset_y - G_height + self.pan_overlap_vertical
	end
	
	return pageno
end

function KOPTReader:prevView()
	local pageno = self.pageno
	
	Debug("preView offset_y", self.offset_y, "min_offset_y", self.min_offset_y)
	if self.offset_y >= 0 then
		-- hit content top, turn to previous page bottom
		if pageno > 1 then
			self.offset_x = 0
			self.offset_y = -2012534
		end
		pageno = pageno - 1
	else
		-- goto previous view of current page
		self.offset_y = self.offset_y + G_height - self.pan_overlap_vertical
	end

	return pageno
end

function KOPTReader:setDefaults()
    self.show_overlap_enable = DKOPTREADER_SHOW_OVERLAP_ENABLE
    self.show_links_enable = DKOPTREADER_SHOW_LINKS_ENABLE
    self.comics_mode_enable = DKOPTREADER_COMICS_MODE_ENABLE
    self.rtl_mode_enable = DKOPTREADER_RTL_MODE_ENABLE
    self.page_mode_enable = DKOPTREADER_PAGE_MODE_ENABLE
end

-- backup global variables from UniReader
function KOPTReader:loadSettings(filename)
	UniReader.loadSettings(self,filename)
	self.offset_y = self.settings:readSetting("kopt_offset_y") or 0
	self.configurable = Configurable
	self.configurable:loadDefaults()
    --Debug("default configurable:", dump(self.configurable))
	self.configurable:loadSettings(self.settings, 'kopt_')
	--Debug("loaded configurable:", dump(self.configurable))
	-- backup global variable that may be changed in koptreader
	self.orig_globalzoom_mode = self.settings:readSetting("globalzoom_mode") or -1
end

function KOPTReader:saveSpecialSettings()
	self.settings:saveSetting("kopt_offset_y", self.offset_y)
	self.configurable:saveSettings(self.settings, 'kopt_')
	--Debug("saved configurable:", dump(self.configurable))
	-- restore global variable from backups
	self.settings:saveSetting("globalzoom_mode", self.orig_globalzoom_mode)
end

function KOPTReader:init()
	self:addAllCommands()
	self:adjustCommands()
end

function KOPTReader:redrawWithoutPrecache()
	self:show(self.pageno)
end

function KOPTReader:adjustCommands()
	self.commands:del(KEY_A, nil,"A")
	self.commands:del(KEY_A, MOD_SHIFT, "A")
	self.commands:del(KEY_C, nil,"C")
	self.commands:del(KEY_U, nil,"U")
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
	self.commands:delGroup(MOD_ALT.."< >")
	self.commands:delGroup(MOD_SHIFT.."< >")
	self.commands:delGroup("vol-/+")
	self.commands:del(KEY_P, nil, "P")
	
	self.commands:add({KEY_F,KEY_AA}, nil, "F",
		"change koptreader configuration",
		function(self)
			KOPTConfig:config(self)
			self:redrawCurrentPage()
		end
	)
end
