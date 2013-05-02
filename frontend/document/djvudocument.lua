require "cache"
require "ui/geometry"
require "ui/screen"
require "ui/device"
require "ui/reader/readerconfig"
require "ui/data/koptoptions"
require "document/koptinterface"

DjvuDocument = Document:new{
	_document = false,
	-- libdjvulibre manages its own additional cache, default value is hard written in c module.
	djvulibre_cache_size = nil,
	dc_null = DrawContext.new(),
	screen_size = Screen:getSize(),
	screen_dpi = Device:getModel() == "KindlePaperWhite" and 212 or 167,
	options = KoptOptions,
	configurable = Configurable,
	koptinterface = KoptInterface,
}

function DjvuDocument:init()
	self.configurable:loadDefaults(self.options)
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
	self.info.configurable = true
	self:_readMetadata()
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

function DjvuDocument:getTextBoxes(pageno)
	if self.configurable.text_wrap == 1 then
		return self.koptinterface:getReflewTextBoxes(self, pageno)
	else
		local text = self._document:getPageText(pageno)
		if not text or #text == 0 then
			return self.koptinterface:getTextBoxes(self, pageno)
		else
			return text
		end
	end
end

function DjvuDocument:getOCRWord(pageno, rect)
	if self.configurable.text_wrap == 1 then
		return self.koptinterface:getReflewOCRWord(self, pageno, rect)
	else
		return self.koptinterface:getOCRWord(self, pageno, rect)
	end
end

function DjvuDocument:getUsedBBox(pageno)
	-- djvu does not support usedbbox, so fake it.
	local used = {}
	local native_dim = self:getNativePageDimensions(pageno)
	used.x0, used.y0, used.x1, used.y1 = 0, 0, native_dim.w, native_dim.h
	return used
end

function DjvuDocument:invertTextYAxel(pageno, text_table)
	local _, height = self.doc:getOriginalPageSize(pageno)
	for _,text in pairs(text_table) do
		for _,line in ipairs(text) do
			line.y0, line.y1 = (height - line.y1), (height - line.y0)
		end
	end
	return text_table
end

function DjvuDocument:getPageBBox(pageno)
	if self.configurable.text_wrap ~= 1 and self.configurable.trim_page == 1 then
		return self.koptinterface:getAutoBBox(self, pageno)
	else
		return Document.getPageBBox(self, pageno)
	end
end

function DjvuDocument:getPageDimensions(pageno, zoom, rotation)
	if self.configurable.text_wrap == 1 then
		return self.koptinterface:getPageDimensions(self, pageno, zoom, rotation)
	else
		return Document.getPageDimensions(self, pageno, zoom, rotation)
	end
end

function DjvuDocument:renderPage(pageno, rect, zoom, rotation, gamma, render_mode)
	if self.configurable.text_wrap == 1 then
		return self.koptinterface:renderPage(self, pageno, rect, zoom, rotation, render_mode)
	else
		return Document.renderPage(self, pageno, rect, zoom, rotation, gamma, render_mode)
	end
end

function DjvuDocument:hintPage(pageno, zoom, rotation, gamma, render_mode)
	if self.configurable.text_wrap == 1 then
		self.koptinterface:hintPage(self, pageno, zoom, rotation, gamma, render_mode)
	else
		Document.hintPage(self, pageno, zoom, rotation, gamma, render_mode)
	end
end

function DjvuDocument:drawPage(target, x, y, rect, pageno, zoom, rotation, gamma, render_mode)
	if self.configurable.text_wrap == 1 then
		self.koptinterface:drawPage(self, target, x, y, rect, pageno, zoom, rotation, render_mode)
	else
		Document.drawPage(self, target, x, y, rect, pageno, zoom, rotation, gamma, render_mode)
	end
end

DocumentRegistry:addProvider("djvu", "application/djvu", DjvuDocument)
