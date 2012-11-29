require "cache"
require "ui/geometry"
require "ui/screen"
require "ui/device"

-- Any document processed by K2pdfopt is called a koptdocument
KoptDocument = Document:new{
	_document = false,
	-- muPDF manages its own additional cache
	mupdf_cache_size = 5 * 1024 * 1024,
	djvulibre_cache_size = nil,
	dc_null = DrawContext.new(),
	screen_size = Screen:getSize(),
	screen_dpi = Device:getModel() == "KindlePaperWhite" and 212 or 167,
	configurable = {
		font_size = 1.2,
		page_margin = 0.06,
		line_spacing = 1.2,
		word_spacing = 0.15,
		quality = 1.0,
		text_wrap = 1,
		defect_size = 1.0,
		trim_page = 1,
		detect_indent = 1,
		multi_threads = 0,
		auto_straighten = 0,
		justification = -1,
		max_columns = 2,
		contrast = 1.0,
		screen_rotation = 0,
	}
}

function KoptDocument:init()
	self.file_type = string.lower(string.match(self.file, ".+%.([^.]+)") or "")
	if self.file_type == "pdf" then
		local ok
		ok, self._document = pcall(pdf.openDocument, self.file, self.mupdf_cache_size)
		if not ok then
			self.error_message = self.doc -- will contain error message
			return
		end
		self.is_open = true
		self.info.has_pages = true
		if self._document:needsPassword() then
			self.is_locked = true
		else
			self:_readMetadata()
		end
		
	elseif self.file_type == "djvu" then
		if not validDjvuFile(self.file) then
			self.error_message = "Not a valid DjVu file"
			return
		end
	
		local ok
		ok, self._document = pcall(djvu.openDocument, self.file, self.djvulibre_cache_size)
		if not ok then
			self.error_message = self.doc -- will contain error message
			return
		end
		self.is_open = true
		self.info.has_pages = true
		self:_readMetadata()
	end
end

function KoptDocument:unlock(password)
	if not self._document:authenticatePassword(password) then
		self._document:close()
		return false, "wrong password"
	end
	self.is_locked = false
	return self:_readMetadata()
end

-- check DjVu magic string to validate
function validDjvuFile(filename)
	f = io.open(filename, "r")
	if not f then return false end
	local magic = f:read(8)
	f:close()
	if not magic or magic ~= "AT&TFORM" then return false end
	return true
end

function KoptDocument:getUsedBBox(pageno)
	if self.file_type == "pdf" then
		local hash = "pgubbox|"..self.file.."|"..pageno
		local cached = Cache:check(hash)
		if cached then
			return cached.data
		end
		local page = self._document:openPage(pageno)
		local used = {}
		local native_dim = self:getNativePageDimensions(pageno)
		used.x, used.y, used.w, used.h = 0, 0, native_dim.w, native_dim.h
		Cache:insert(hash, CacheItem:new{ used })
		page:close()
		return used
	elseif self.file_type == "djvu" then
		-- djvu does not support usedbbox, so fake it.
		local used = {}
		local native_dim = self:getNativePageDimensions(pageno)
		used.x, used.y, used.w, used.h = 0, 0, native_dim.w, native_dim.h
		return used
	end
end

-- get reflow context
function KoptDocument:getKOPTContext(pageno)
	local kc = KOPTContext.new()
	kc:setTrim(self.configurable.trim_page)
	kc:setWrap(self.configurable.text_wrap)
	kc:setIndent(self.configurable.detect_indent)
	kc:setRotate(self.configurable.screen_rotation)
	kc:setColumns(self.configurable.max_columns)
	kc:setDeviceDim(self.screen_size.w, self.screen_size.h)
	kc:setDeviceDPI(self.screen_dpi)
	kc:setStraighten(self.configurable.auto_straighten)
	kc:setJustification(self.configurable.justification)
	kc:setZoom(self.configurable.font_size)
	kc:setMargin(self.configurable.page_margin)
	kc:setQuality(self.configurable.quality)
	kc:setContrast(self.configurable.contrast)
	kc:setDefectSize(self.configurable.defect_size)
	kc:setLineSpacing(self.configurable.line_spacing)
	kc:setWordSpacing(self.configurable.word_spacing)
	local bbox = self:getUsedBBox(pageno)
	kc:setBBox(bbox.x, bbox.y, bbox.w, bbox.h)
	return kc
end

-- calculates page dimensions
function KoptDocument:getPageDimensions(pageno, zoom, rotation)
	-- check cached page size
	local hash = "pgrfsize|"..self.file.."|"..pageno
	local cached = Cache:check(hash)
	if not cached then
		DEBUG("Warnning: cannot determine page size before reflowing.")
		return Screen:getSize()
	end
	DEBUG("Found cached page size on page", pageno, cached[1])
	return cached[1]
end

function KoptDocument:renderPage(pageno, rect, zoom, rotation, render_mode)
	local hash = "renderpg|"..self.file.."|"..pageno.."|"..zoom.."|"..rotation
	--local page_size = self:getPageDimensions(pageno, zoom, rotation)
	local kc = self:getKOPTContext(pageno)
	local page = self._document:openPage(pageno)
	-- reflow page
	page:reflow(kc, render_mode)
	local fullwidth, fullheight = kc:getPageDim()
	DEBUG("page::reflowPage:", "fullwidth:", fullwidth, "fullheight:", fullheight)
	local page_size = Geom:new{ w = fullwidth, h = fullheight }
	-- cache reflowed page size
	local pgrfsize_hash = "pgrfsize|"..self.file.."|"..pageno
	if not Cache:check(pgrfsize_hash) then
		Cache:insert(pgrfsize_hash, CacheItem:new{ page_size })
	end
	-- this will be the size we actually render
	local size = page_size
	-- we prefer to render the full page, if it fits into cache
	if not Cache:willAccept(size.w * size.h / 2) then
		-- whole page won't fit into cache
		DEBUG("rendering only part of the page")
		-- TODO: figure out how to better segment the page
		if not rect then
			DEBUG("aborting, since we do not have a specification for that part")
			-- required part not given, so abort
			return
		end
		-- only render required part
		hash = "renderpg|"..self.file.."|"..pageno.."|"..zoom.."|"..rotation.."|"..tostring(rect)
		size = rect
	end

	-- prepare cache item with contained blitbuffer	
	local tile = CacheItem:new{
		size = size.w * size.h / 2 + 64, -- estimation
		excerpt = size,
		pageno = pageno,
		bb = Blitbuffer.new(size.w, size.h)
	}

	-- draw to blitbuffer
	page:rfdraw(kc, tile.bb)
	page:close()
	Cache:insert(hash, tile)

	return tile
end

DocumentRegistry:addProvider("pdf", "application/pdf", KoptDocument)
DocumentRegistry:addProvider("djvu", "application/djvu", KoptDocument)
