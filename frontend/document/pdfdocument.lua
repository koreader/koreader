require "cache"
require "ui/geometry"
require "ui/screen"
require "ui/reader/readerconfig"
require "ui/data/koptoptions"
require "document/koptinterface"

PdfDocument = Document:new{
	_document = false,
	-- muPDF manages its own additional cache
	mupdf_cache_size = 5 * 1024 * 1024,
	dc_null = DrawContext.new(),
	screen_size = Screen:getSize(),
	screen_dpi = Screen:getDPI(),
	options = KoptOptions,
	configurable = Configurable,
	koptinterface = KoptInterface,
}

function PdfDocument:init()
	self.configurable:loadDefaults(self.options)
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

function PdfDocument:getTextBoxes(pageno)
	if self.configurable.text_wrap == 1 then
		return self.koptinterface:getReflewTextBoxes(self, pageno)
	else
		local page = self._document:openPage(pageno)
		local text = page:getPageText()
		page:close()
		if not text or #text == 0 then
			return self.koptinterface:getTextBoxes(self, pageno)
		else
			return text
		end
	end
end

function PdfDocument:getOCRWord(pageno, rect)
	if self.configurable.text_wrap == 1 then
		return self.koptinterface:getReflewOCRWord(self, pageno, rect)
	else
		return self.koptinterface:getOCRWord(self, pageno, rect)
	end
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
	local pwidth, pheight = page:getSize(self.dc_null)
	-- clamp to page BBox
	if used.x0 < 0 then used.x0 = 0 end
	if used.x1 > pwidth then used.x1 = pwidth end
	if used.y0 < 0 then used.y0 = 0 end
	if used.y1 > pheight then used.y1 = pheight end
	--@TODO give size for cacheitem?  02.12 2012 (houqp)
	Cache:insert(hash, CacheItem:new{ 
		ubbox = used,
	})
	page:close()
	return used
end

function PdfDocument:getPageBBox(pageno)
	if self.configurable.text_wrap ~= 1 and self.configurable.trim_page == 1 then
		-- auto bbox finding
		return self.koptinterface:getAutoBBox(self, pageno)
	elseif self.configurable.text_wrap ~= 1 and self.configurable.trim_page == 2 then
		-- semi-auto bbox finding
		return self.koptinterface:getSemiAutoBBox(self, pageno)
	else
		-- get saved manual bbox
		return Document.getPageBBox(self, pageno)
	end
end

function PdfDocument:getPageDimensions(pageno, zoom, rotation)
	if self.configurable.text_wrap == 1 then
		return self.koptinterface:getPageDimensions(self, pageno, zoom, rotation)
	else
		return Document.getPageDimensions(self, pageno, zoom, rotation)
	end
end

function PdfDocument:renderPage(pageno, rect, zoom, rotation, gamma, render_mode)
	if self.configurable.text_wrap == 1 then
		return self.koptinterface:renderPage(self, pageno, rect, zoom, rotation, render_mode)
	else
		return Document.renderPage(self, pageno, rect, zoom, rotation, gamma, render_mode)
	end
end

function PdfDocument:hintPage(pageno, zoom, rotation, gamma, render_mode)
	if self.configurable.text_wrap == 1 then
		self.koptinterface:hintPage(self, pageno, zoom, rotation, gamma, render_mode)
	else
		Document.hintPage(self, pageno, zoom, rotation, gamma, render_mode)
	end
end

function PdfDocument:drawPage(target, x, y, rect, pageno, zoom, rotation, gamma, render_mode)
	if self.configurable.text_wrap == 1 then
		self.koptinterface:drawPage(self, target, x, y, rect, pageno, zoom, rotation, render_mode)
	else
		Document.drawPage(self, target, x, y, rect, pageno, zoom, rotation, gamma, render_mode)
	end
end

DocumentRegistry:addProvider("pdf", "application/pdf", PdfDocument)
DocumentRegistry:addProvider("cbz", "application/cbz", PdfDocument)
