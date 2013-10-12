require "cache"
require "ui/geometry"
require "ui/reader/readerconfig"
require "ui/data/koptoptions"
require "document/koptinterface"

PdfDocument = Document:new{
	_document = false,
	-- muPDF manages its own additional cache
	mupdf_cache_size = 5 * 1024 * 1024,
	dc_null = DrawContext.new(),
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

function PdfDocument:getPageTextBoxes(pageno)
	local page = self._document:openPage(pageno)
	local text = page:getPageText()
	page:close()
	return text
end

function PdfDocument:getWordFromPosition(spos)
	return self.koptinterface:getWordFromPosition(self, spos)
end

function PdfDocument:getTextFromPositions(spos0, spos1)
	return self.koptinterface:getTextFromPositions(self, spos0, spos1)
end

function PdfDocument:getPageBoxesFromPositions(pageno, ppos0, ppos1)
	return self.koptinterface:getPageBoxesFromPositions(self, pageno, ppos0, ppos1)
end

function PdfDocument:getOCRWord(pageno, rect)
	return self.koptinterface:getOCRWord(self, pageno, rect)
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
	return self.koptinterface:getPageBBox(self, pageno)
end

function PdfDocument:getPageDimensions(pageno, zoom, rotation)
	return self.koptinterface:getPageDimensions(self, pageno, zoom, rotation)
end

function PdfDocument:renderPage(pageno, rect, zoom, rotation, gamma, render_mode)
	return self.koptinterface:renderPage(self, pageno, rect, zoom, rotation, gamma, render_mode)
end

function PdfDocument:hintPage(pageno, zoom, rotation, gamma, render_mode)
	return self.koptinterface:hintPage(self, pageno, zoom, rotation, gamma, render_mode)
end

function PdfDocument:drawPage(target, x, y, rect, pageno, zoom, rotation, gamma, render_mode)
	return self.koptinterface:drawPage(self, target, x, y, rect, pageno, zoom, rotation, gamma, render_mode)
end

DocumentRegistry:addProvider("pdf", "application/pdf", PdfDocument)
DocumentRegistry:addProvider("cbz", "application/cbz", PdfDocument)
