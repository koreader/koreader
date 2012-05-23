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

