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


----------------------------------------------------
-- highlight support 
----------------------------------------------------
function DJVUReader:getText(pageno)
	return self.doc:getPageText(pageno)
end

----------------------------------------------------
-- In djvulibre library, some coordinates starts from
-- lower left conner, i.e. y is upside down in kpv's
-- coordinate. So y0 should be taken with special care.
----------------------------------------------------
function DJVUReader:zoomedRectCoordTransform(x0, y0, x1, y1)
	local x,y = self:screenOffset()
	return 
		x0 * self.globalzoom + x,
		self.cur_full_height - (y1 * self.globalzoom) + y,
		(x1 - x0) * self.globalzoom,
		(y1 - y0) * self.globalzoom
end

-- y axel in djvulibre starts from bottom
function DJVUReader:_isEntireWordInScreenHeightRange(w)
	return	(w ~= nil) and
			(self.cur_full_height - (w.y1 * self.globalzoom) >=
				-self.offset_y) and
			(self.cur_full_height - (w.y0 * self.globalzoom) <= 
				-self.offset_y + G_height)
end

-- y axel in djvulibre starts from bottom
function DJVUReader:_isEntireLineInScreenHeightRange(l)
	return	(l ~= nil) and
			(self.cur_full_height - (l.y1 * self.globalzoom) >=
				-self.offset_y) and
			(self.cur_full_height - (l.y0 * self.globalzoom) <= 
				-self.offset_y + G_height)
end

-- y axel in djvulibre starts from bottom
function DJVUReader:_isWordInScreenRange(w)
	if not w then
		return false
	end

	is_entire_word_out_of_screen_height = 
		(self.cur_full_height - (w.y0 * self.globalzoom) <=
											-self.offset_y)
		or (self.cur_full_height - (w.y1 * self.globalzoom) >=
											-self.offset_y + G_height)

	is_entire_word_out_of_screen_width = 
			(w.x0 * self.globalzoom >= -self.offset_x + G_width
			or w.x1 * self.globalzoom <= -self.offset_x)

	return	(not is_entire_word_out_of_screen_height) and
			(not is_entire_word_out_of_screen_width)
end


