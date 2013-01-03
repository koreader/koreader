require "cache"
require "ui/geometry"
require "ui/screen"
require "ui/device"
require "ui/reader/readerconfig"
require "document/koptinterface"

PdfDocument = Document:new{
	_document = false,
	-- muPDF manages its own additional cache
	mupdf_cache_size = 5 * 1024 * 1024,
	dc_null = DrawContext.new(),
	screen_size = Screen:getSize(),
	screen_dpi = Device:getModel() == "KindlePaperWhite" and 212 or 167,
	configurable = Configurable,
	koptinterface = KoptInterface,
}

function PdfDocument:init()
	self.configurable:loadDefaults()
	local ok
	ok, self._document = pcall(pdf.openDocument, self.file, self.mupdf_cache_size)
	if not ok then
		self.error_message = self.doc -- will contain error message
		return
	end
	self.is_open = true
	self.info.has_pages = true
	self.info.configurable = true
	if self._document:needsPassword() then
		self.is_locked = true
	else
		self:_readMetadata()
	end
end

function PdfDocument:unlock(password)
	if not self._document:authenticatePassword(password) then
		self._document:close()
		return false, "wrong password"
	end
	self.is_locked = false
	return self:_readMetadata()
end

function PdfDocument:getUsedBBox(pageno)
	local hash = "pgubbox|"..self.file.."|"..pageno
	local cached = Cache:check(hash)
	if cached then
		return cached.ubbox
	end
	local page = self._document:openPage(pageno)
	local used = {}
	used.x0, used.y0, used.x1, used.y1 = page:getUsedBBox()
	--@TODO give size for cacheitem?  02.12 2012 (houqp)
	Cache:insert(hash, CacheItem:new{ 
		ubbox = used,
	})
	page:close()
	return used
end

function PdfDocument:getPageDimensions(pageno, zoom, rotation)
	if self.configurable.text_wrap == 1 then
		return self.koptinterface:getPageDimensions(self, pageno, zoom, rotation)
	else
		return Document.getPageDimensions(self, pageno, zoom, rotation)
	end
end

function PdfDocument:renderPage(pageno, rect, zoom, rotation, render_mode)
	if self.configurable.text_wrap == 1 then
		return self.koptinterface:renderPage(self, pageno, rect, zoom, rotation, render_mode)
	else
		return Document.renderPage(self, pageno, rect, zoom, rotation, render_mode)
	end
end

function PdfDocument:drawPage(target, x, y, rect, pageno, zoom, rotation, render_mode)
	if self.configurable.text_wrap == 1 then
		self.koptinterface:drawPage(self, target, x, y, rect, pageno, zoom, rotation, render_mode)
	else
		Document.drawPage(self, target, x, y, rect, pageno, zoom, rotation, render_mode)
	end
end

DocumentRegistry:addProvider("pdf", "application/pdf", PdfDocument)
