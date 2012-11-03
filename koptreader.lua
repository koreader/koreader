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
	detect_indent = 1,
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
	local width, height = G_width, G_height
	if not ok then
		-- TODO: error handling
		return nil
	end
	
	local dc = self:setzoom(page, preCache)
	
	-- check if we have relevant cache contents
	local pagehash = no..self.configurable:hash('_')
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
	local font_size, page_margin = self.configurable.font_size, self.configurable.page_margin
	local line_spacing, word_spacing = self.configurable.line_spacing, self.configurable.word_spacing
	local text_wrap, justification = self.configurable.text_wrap, self.configurable.justification
	local max_columns, contrast = self.configurable.max_columns, self.configurable.contrast
	local auto_straighten = self.configurable.auto_straighten
	local screen_rotation = self.configurable.screen_rotation
	local detect_indent = self.configurable.detect_indent
	local quality = self.configurable.quality
	self.fullwidth, self.fullheight, self.reflow_zoom = page:reflow(dc, self.render_mode, width, height, font_size, page_margin, line_spacing, word_spacing, text_wrap, auto_straighten, justification, detect_indent, max_columns, contrast, screen_rotation, quality)
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
	
	return dc
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
		if pageno > 1 then
			self.offset_x = 0
			self.offset_y = -2012534
		end
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
    self.comics_mode_enable = false
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
end

function KOPTReader:saveSpecialSettings()
	self.settings:saveSetting("kopt_offset_y", self.offset_y)
	self.configurable:saveSettings(self.settings, 'kopt_')
	--Debug("saved configurable:", dump(self.configurable))
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
	
	self.commands:add({KEY_F,KEY_AA}, nil, "F",
		"change koptreader configuration",
		function(self)
			KOPTConfig:config(KOPTReader.redrawWithoutPrecache, self, self.configurable)
			self:redrawCurrentPage()
		end
	)
end
