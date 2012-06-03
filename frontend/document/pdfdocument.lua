require "cache"
require "ui/geometry"

PdfDocument = Document:new{
	_document = false,
	-- muPDF manages its own additional cache
	mupdf_cache_size = 5 * 1024 * 1024,
	dc_null = DrawContext.new()
}

function PdfDocument:init()
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
		return cached.data
	end
	local page = self._document:openPage(pageno)
	local used = {}
	used.x, used.y, used.w, used.h = page:getUsedBBox()
	Cache:insert(hash, CacheItem:new{ used })
	page:close()
	return used
end

DocumentRegistry:addProvider("pdf", "application/pdf", PdfDocument)
