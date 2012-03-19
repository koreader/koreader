require "unireader"

DJVUReader = UniReader:new{
	newDC = function()
		print("djvu.newDC")
		return djvu.newDC()
	end,
}

function DJVUReader:init()
	self.nulldc = self.newDC()
end

-- open a DJVU file and its settings store
-- DJVU does not support password yet
function DJVUReader:open(filename)
	self.doc = djvu.openDocument(filename)
	return self:loadSettings(filename)
end

function DJVUReader:_isWordInScreenRange(w)
	return	(self.cur_full_height-(w.y0*self.globalzoom) <= 
				-self.offset_y + width) and
			(self.cur_full_height-(w.y1*self.globalzoom) >=
				-self.offset_y)
end

function DJVUReader:_genTextIter(text, l0, w0, l1, w1)
	local word_items = {}
	local count = 0
	local l = l0
	local w = w0
	local tmp_w1 = 0

	-- build item table
	while l <= l1 do
		local words = text[l].words

		if l == l1 then 
			tmp_w1 = w1 
		else
			tmp_w1 = #words
		end

		while w <= tmp_w1 do
			if self:_isWordInScreenRange(words[w]) then
				table.insert(word_items, words[w])
			end -- EOF if isInScreenRange
			w = w + 1
		end -- EOF while words
		-- goto next line, reset j
		w = 1
		l = l + 1
	end -- EOF for while

	return function() count = count + 1 return word_items[count] end
end

function DJVUReader:_drawTextHighLight(text_iter)
	for i in text_iter do
		fb.bb:paintRect(
			i.x0*self.globalzoom,
			self.offset_y+self.cur_full_height-(i.y1*self.globalzoom),
			(i.x1-i.x0)*self.globalzoom,
			(i.y1-i.y0)*self.globalzoom, 15)
	end -- EOF for 
end

function DJVUReader:startHighLightMode()
	local t = self.doc:getPageText(self.pageno)

	--self:_drawTextHighLight(self:_genTextIter(t, 1, 1, #t, #(t[#t].words)))
	-- highlight the first line
	self:_drawTextHighLight(self:_genTextIter(t, 1, 1, 1, #(t[1].words)))
	fb:refresh(0)
end

