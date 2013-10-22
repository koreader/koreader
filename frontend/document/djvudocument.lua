local Geom = require("ui/geometry")
local Cache = require("cache")
local CacheItem = require("cacheitem")
local KoptOptions = require("ui/data/koptoptions")
local KoptInterface = require("document/koptinterface")
local Document = require("document/document")
local Configurable = require("ui/reader/configurable")
-- TBD: DrawContext

local DjvuDocument = Document:new{
	_document = false,
	-- libdjvulibre manages its own additional cache, default value is hard written in c module.
	djvulibre_cache_size = nil,
	dc_null = DrawContext.new(),
	options = KoptOptions,
	koptinterface = KoptInterface,
}

-- check DjVu magic string to validate
local function validDjvuFile(filename)
	f = io.open(filename, "r")
	if not f then return false end
	local magic = f:read(8)
	f:close()
	if not magic or magic ~= "AT&TFORM" then return false end
	return true
end

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

function DjvuDocument:invertTextYAxel(pageno, text_table)
	local _, height = self.doc:getOriginalPageSize(pageno)
	for _,text in pairs(text_table) do
		for _,line in ipairs(text) do
			line.y0, line.y1 = (height - line.y1), (height - line.y0)
		end
	end
	return text_table
end

function DjvuDocument:getPageTextBoxes(pageno)
	return self._document:getPageText(pageno)
end

function DjvuDocument:getWordFromPosition(spos)
	return self.koptinterface:getWordFromPosition(self, spos)
end

function DjvuDocument:getTextFromPositions(spos0, spos1)
	return self.koptinterface:getTextFromPositions(self, spos0, spos1)
end

function DjvuDocument:getPageBoxesFromPositions(pageno, ppos0, ppos1)
	return self.koptinterface:getPageBoxesFromPositions(self, pageno, ppos0, ppos1)
end

function DjvuDocument:getOCRWord(pageno, wbox)
	return self.koptinterface:getOCRWord(self, pageno, wbox)
end

function DjvuDocument:getOCRText(pageno, tboxes)
	return self.koptinterface:getOCRText(self, pageno, tboxes)
end

function DjvuDocument:getUsedBBox(pageno)
	-- djvu does not support usedbbox, so fake it.
	local used = {}
	local native_dim = self:getNativePageDimensions(pageno)
	used.x0, used.y0, used.x1, used.y1 = 0, 0, native_dim.w, native_dim.h
	return used
end

function DjvuDocument:getPageBBox(pageno)
	return self.koptinterface:getPageBBox(self, pageno)
end

function DjvuDocument:getPageDimensions(pageno, zoom, rotation)
	return self.koptinterface:getPageDimensions(self, pageno, zoom, rotation)
end

function DjvuDocument:renderPage(pageno, rect, zoom, rotation, gamma, render_mode)
	return self.koptinterface:renderPage(self, pageno, rect, zoom, rotation, gamma, render_mode)
end

function DjvuDocument:hintPage(pageno, zoom, rotation, gamma, render_mode)
	return self.koptinterface:hintPage(self, pageno, zoom, rotation, gamma, render_mode)
end

function DjvuDocument:drawPage(target, x, y, rect, pageno, zoom, rotation, gamma, render_mode)
	return self.koptinterface:drawPage(self, target, x, y, rect, pageno, zoom, rotation, gamma, render_mode)
end

function DjvuDocument:register(registry)
	registry:addProvider("djvu", "application/djvu", self)
end

return DjvuDocument
