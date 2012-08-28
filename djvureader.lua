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
		"colour/b&w/colouronly/maskonly/backg/foreg",
		function(self)
			self:cycle_render_mode()
	end) 
end

-- cycle through all rendering modes supported by djvulibre:
--  0	(color page or stencil)
--  1	(stencil or color page)
--  2	(color page or fail)
--  3	(stencil or fail)
--  4	(color background layer)
--  5	(color foreground layer)
--  Note that if the values in the definition of ddjvu_render_mode_t in djvulibre/libdjvu/ddjvuapi.h change,
--  then we should update our values here also. This is a bit risky, but these values never change, so it should be ok :)
function DJVUReader:cycle_render_mode()
	self.render_mode = (self.render_mode + 1)%6
	Debug("cycle_render_mode, render_mode=", self.render_mode)
	self:clearCache()
	self.doc:cleanCache()
	local render_mode_name
	if self.render_mode == 0 then
		render_mode_name = "COLOUR"
	elseif self.render_mode == 1 then
		render_mode_name = "BLACK & WHITE"
	elseif self.render_mode == 2 then
		render_mode_name = "COLOUR ONLY"
	elseif self.render_mode == 3 then
		render_mode_name = "MASK ONLY"
	elseif self.render_mode == 4 then
		render_mode_name = "COLOUR BACKGROUND"
	elseif self.render_mode == 5 then
		render_mode_name = "COLOUR FOREGROUND"
	else
		render_mode_name = "UNKNOWN"
	end
	showInfoMsgWithDelay("("..self.render_mode..") "..render_mode_name, 1000, 1)
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

