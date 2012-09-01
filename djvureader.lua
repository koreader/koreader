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
	self.commands:add(KEY_R, nil, "R",
		"toggle rendering mode: b&w/colour",
		function(DJVUReader)
			DJVUReader:toggle_render_mode()
		end)
end

-------------------------------------------------------
-- toggle rendering mode between colour (0) and b&w (1)
-------------------------------------------------------

function DJVUReader:toggle_render_mode()
	InfoMessage:show("New render_mode = "..self.render_mode, 1)
	Debug("toggle_render_mode, render_mode=", self.render_mode)
	self.render_mode = 1 - self.render_mode
	self:clearCache()
	self.doc:cleanCache()
	self:redrawCurrentPage()
end

----------------------------------------------------
-- highlight support 
----------------------------------------------------
function DJVUReader:getText(pageno)
	return self.doc:getPageText(pageno)
end

-- for incompatible API fixing
function DJVUReader:invertTextYAxel(pageno, text_table)
	local _, height = self.doc:getOriginalPageSize(pageno)
	for _,text in pairs(text_table) do
		for _,line in ipairs(text) do
			line.y0, line.y1 = (height - line.y1), (height - line.y0)
		end
	end
	return text_table
end
