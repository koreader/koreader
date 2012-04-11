require "unireader"

DJVUReader = UniReader:new{}

-- open a DJVU file and its settings store
-- DJVU does not support password yet
function DJVUReader:open(filename)
	local ok
	ok, self.doc = pcall(djvu.openDocument, filename, self.cache_document_size)
	if not ok then
		return ok, self.doc -- this will be the error message instead
	end
	return ok
end

function DJVUReader:init()
	self:addAllCommands()
	self:adjustDjvuReaderCommand()
end

function DJVUReader:adjustDjvuReaderCommand()
	self.commands:del(KEY_J, MOD_SHIFT, "J")
	self.commands:del(KEY_K, MOD_SHIFT, "K")
end


-----------[ highlight support ]----------

----------------------------------------------------
-- Given coordinates of four conners and return
-- coordinate of upper left conner with with and height
--
-- In djvulibre library, some coordinates starts from
-- down left conner, i.e. y is upside down. This method
-- only transform these coordinates.
----------------------------------------------------
function DJVUReader:rectCoordTransform(x0, y0, x1, y1)
	return 
		self.offset_x + x0 * self.globalzoom,
		self.offset_y + self.cur_full_height - (y1 * self.globalzoom),
		(x1 - x0) * self.globalzoom,
		(y1 - y0) * self.globalzoom
end

function DJVUReader:getText(pageno)
	return self.doc:getPageText(pageno)
end
