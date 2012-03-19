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
	-- y axel in djvulibre starts from bottom
	return	(w ~= nil) and (
			( self.cur_full_height-(w.y0*self.globalzoom) <= 
				-self.offset_y + height ) and
			( self.cur_full_height-(w.y1*self.globalzoom) >=
				-self.offset_y ))
end

function DJVUReader:_isLastWordInPage(t, l, w)
	return (l == #t) and (w == #(t[l].words))
end

function DJVUReader:_isFirstWordInPage(t, l, w)
	return (l == 1) and (w == 1)
end
------------------------------------------------
-- @text text object returned from doc:getPageText()
-- @l0 start line
-- @w0 start word
-- @l1 end line
-- @w1 end word
--
-- get words from the w0th word in l0th line
-- to w1th word in l1th line (not included).
------------------------------------------------
function DJVUReader:_genTextIter(text, l0, w0, l1, w1)
	local word_items = {}
	local count = 0
	local l = l0
	local w = w0
	local tmp_w1 = 0

	print(l0, w0, l1, w1)

	if l0 < 1 or w0 < 1 or l0 > l1 then
		return function() return nil end
	end

	-- build item table
	while l <= l1 do
		local words = text[l].words

		if l == l1 then 
			tmp_w1 = w1 - 1
			if tmp_w1 == 0 then
				break
			end
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
		fb.bb:invertRect(
			i.x0*self.globalzoom,
			self.offset_y+self.cur_full_height-(i.y1*self.globalzoom),
			(i.x1-i.x0)*self.globalzoom,
			(i.y1-i.y0)*self.globalzoom, 15)
	end -- EOF for 
end

function DJVUReader:startHighLightMode()
	local t = self.doc:getPageText(self.pageno)

	local function _posToNextWord(t, cur_l, cur_w) 
		local new_l = cur_l
		local new_w = cur_w

		if new_w >= #(t[new_l].words) then
			if new_l == #t then
				-- word to mark is the last word in last line
				return new_l, #(t[new_l].words)+1
			else
				-- word to mark is not the last word in last line, 
				-- goto next line
				new_l = new_l + 1
				new_w = 1
			end
		else
			-- simply move to next word in the same line
			new_w = new_w + 1
		end

		return new_l, new_w
	end

	local function _posToPrevWord(t, cur_l, cur_w)
		local new_l = cur_l
		local new_w = cur_w

		if new_w == 1 then
			-- already the first word, goto previous line
			new_l = new_l - 1
			if new_l == 0 or #(t[new_l].words) == 0 then
				return cur_l, cur_w
			end
			new_w = #(t[new_l].words)
		else
			-- simply move to previous word in the same line
			new_w = new_w - 1
		end

		return new_l, new_w
	end

	local function _posToNextLine(t, cur_l, cur_w)
		local new_l = cur_l
		local new_w = cur_w

		if new_l >= #t then
			-- already last line, jump to line end instead
			return new_l, #(t[new_l].words)+1
		end

		new_l = new_l + 1
		new_w = math.min(new_w, #t[new_l].words)

		return new_l, new_w
	end

	local function _posToPrevLine(t, cur_l, cur_w)
		local new_l = cur_l
		local new_w = cur_w

		if new_l == 1 then
			return cur_l, cur_w
		end

		new_l = new_l - 1
		new_w = math.min(new_w, #t[new_l].words)

		return new_l, new_w
	end


	local start_l = 1
	local start_w = 1
	-- next to be marked word position
	local cur_l = 1
	--local cur_w = #(t[1].words)
	local cur_w = 1
	local new_l = 1
	local new_w = 1
	local iter
	local meet_page_end = false
	local meet_page_start = false

	while true do
		local ev = input.waitForEvent()
		ev.code = adjustKeyEvents(ev)
		if ev.type == EV_KEY and ev.value == EVENT_VALUE_KEY_PRESS then
			if ev.code == KEY_FW_LEFT then
				if self:_isFirstWordInPage(t, cur_l, cur_w) then
					iter = function() return nil end
				else
					new_l, new_w = _posToPrevWord(t, cur_l, cur_w)
					if not self:_isWordInScreenRange(t[new_l].words[new_w]) then
						-- goto next view of current page
						local pageno = self:prevView()
						self:goto(pageno)
						cur_l = start_l
						cur_w = start_w
					end
					iter = self:_genTextIter(t, new_l, new_w, cur_l, cur_w)
					meet_page_end = false
				end
			elseif ev.code == KEY_FW_RIGHT then
				if meet_page_end then
					iter = function() return nil end
				else
					new_l, new_w = _posToNextWord(t, cur_l, cur_w)
					if not self:_isWordInScreenRange(t[new_l].words[new_w]) then
						if self:_isLastWordInPage(t, new_l, new_w-1) then
							-- meet the end of page, mark it
							meet_page_end = true
						else
							-- goto next view of current page
							local pageno = self:nextView()
							self:goto(pageno)
							cur_l = start_l
							cur_w = start_w
						end
					end
					iter = self:_genTextIter(t, cur_l, cur_w, new_l, new_w)
					meet_page_start = false
				end
			elseif ev.code == KEY_FW_UP then
				if self:_isFirstWordInPage(t, cur_l, cur_w) then
					iter = function() return nil end
				else
					new_l, new_w = _posToPrevLine(t, cur_l, cur_w)
					if not self:_isWordInScreenRange(t[new_l].words[new_w]) then
						-- goto next view of current page
						local pageno = self:prevView()
						self:goto(pageno)
						cur_l = start_l
						cur_w = start_w
					end
					iter = self:_genTextIter(t, new_l, new_w, cur_l, cur_w)
					meet_page_end = false
				end
			elseif ev.code == KEY_FW_DOWN then
				if meet_page_end then
					-- already at the end of page, we don't do a pageturn
					-- so do noting here
					iter = function() return nil end
				else
					new_l, new_w = _posToNextLine(t, cur_l, cur_w)
					if not self:_isWordInScreenRange(t[new_l].words[new_w]) then
						if self:_isLastWordInPage(t, new_l, new_w-1) then
							-- meet the end of page, mark it
							meet_page_end = true
						else
							-- goto next view of current page
							local pageno = self:nextView()
							self:goto(pageno)
							cur_l = start_l
							cur_w = start_w
						end
					end
					iter = self:_genTextIter(t, cur_l, cur_w, new_l, new_w)
					meet_page_start = false
				end
			end -- EOF if keyevent

			self:_drawTextHighLight(iter)
			fb:refresh(0)
			cur_l, cur_w = new_l, new_w
		end
	end
end

