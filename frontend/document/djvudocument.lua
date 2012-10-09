require "cache"
require "ui/geometry"

DjvuDocument = Document:new{
	_document = false,
	-- libdjvulibre manages its own additional cache, default value is hard written in c module.
	djvulibre_cache_size = nil,
	dc_null = DrawContext.new()
}

function DjvuDocument:init()
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

-- check DjVu magic string to validate
function validDjvuFile(filename)
	f = io.open(filename, "r")
	if not f then return false end
	local magic = f:read(8)
	f:close()
	if not magic or magic ~= "AT&TFORM" then return false end
	return true
end

function DjvuDocument:getUsedBBox(pageno)
	-- djvu does not support usedbbox, so fake it.
	local used = {}
	used.x, used.y, used.w, used.h = 0.01, 0.01, -0.01, -0.01
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

DocumentRegistry:addProvider("djvu", "application/djvu", DjvuDocument)
