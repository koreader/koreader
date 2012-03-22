require "unireader"

DJVUReader = UniReader:new{}

-- open a DJVU file and its settings store
-- DJVU does not support password yet
function DJVUReader:open(filename)
	local ok
	ok, self.doc = pcall(djvu.openDocument, filename)
	if not ok then
		return ok, self.doc -- this will be the error message instead
	end
	return ok
end

function DJVUReader:_isWordInScreenRange(w)
	-- y axel in djvulibre starts from bottom
	return	(w ~= nil) and (
			( self.cur_full_height-(w.y0*self.globalzoom) <= 
				-self.offset_y + height ) and
			( self.cur_full_height-(w.y1*self.globalzoom) >=
				-self.offset_y ))
end

function DJVUReader:toggleTextHighLight(word_list)
	self:_toggleTextHighLight(word_list, 1, 1, 
							#word_list, #(word_list[#word_list]))
end

function DJVUReader:_toggleTextHighLight(t, l0, w0, l1, w1)
	print("haha", l0, w0, l1, w1)
	-- make sure (l0, w0) is smaller than (l1, w1)
	if l0 > l1 then
		l0, l1 = l1, l0
		w0, w1 = w1, w0
	elseif l0 == l1 and w0 > w1 then
		w0, w1 = w1, w0
	end

	if l0 == l1 then
		-- in the same line
		for i=w0, w1, 1 do
			if self:_isWordInScreenRange(t[l0][i]) then
				self:_toggleWordHighLight(t, l0, i)
			end
		end
	else
		-- highlight word in first line as special case
		for i=w0, #(t[l0]), 1 do
			if self:_isWordInScreenRange(t[l0][i]) then
				self:_toggleWordHighLight(t, l0, i)
			end
		end

		for i=l0+1, l1-1, 1 do
			for j=1, #t[i], 1 do
				if self:_isWordInScreenRange(t[i][j]) then
					self:_toggleWordHighLight(t, i, j)
				end
			end
		end

		-- highlight word in last line as special case
		for i=1, w1, 1 do
			if self:_isWordInScreenRange(t[l1][i]) then
				self:_toggleWordHighLight(t, l1, i)
			end
		end
	end -- EOF if l0==l1
end

function DJVUReader:_toggleWordHighLight(t, l, w)
	local width = (t[l][w].x1 - t[l][w].x0) * self.globalzoom
	local height = (t[l].y1 - t[l].y0) * self.globalzoom
	fb.bb:invertRect(
		t[l][w].x0*self.globalzoom-width*0.05,
		self.offset_y+self.cur_full_height-(t[l].y1*self.globalzoom)-height*0.05,
		width*1.1, height*1.1)
end

--function DJVUReader:_toggleWordHighLight(w)
	--local width = (w.x1-w.x0)*self.globalzoom
	--local height = (w.y1-w.y0)*self.globalzoom
	--fb.bb:invertRect(
		--w.x0*self.globalzoom-width*0.05,
		--self.offset_y+self.cur_full_height-(w.y1*self.globalzoom)-height*0.05,
		--width*1.1,
		--height*1.1)
--end

-- remember to clear cursor before calling this
function DJVUReader:drawCursorAfterWord(t, l, w)
	self.cursor:setHeight((t[l].y1 - t[l].y0) * self.globalzoom)
	self.cursor:moveTo(t[l][w].x1 * self.globalzoom, 
				self.offset_y + self.cur_full_height
				- (t[l].y1 * self.globalzoom))
	self.cursor:draw()
end

function DJVUReader:drawCursorBeforeWord(t, l, w)
	self.cursor:setHeight((t[l].y1 - t[l].y0)
							* self.globalzoom)
	self.cursor:moveTo(
		t[l][w].x0*self.globalzoom - self.cursor.w, 
		self.offset_y + self.cur_full_height
			- t[l].y1 * self.globalzoom)
	self.cursor:draw()
end

function DJVUReader:startHighLightMode()
	local t = self.doc:getPageText(self.pageno)

	local function _findFirstWordInView(t)
		-- @TODO maybe we can just check line by line here  22.03 2012 (houqp)
		for i=1, #t, 1 do
			for j=1, #t[i], 1 do
				if self:_isWordInScreenRange(t[i][j]) then
					return i, j
				end
			end
		end

		return nil
	end

	local function _prevWord(t, cur_l, cur_w)
		if cur_l == 1 then
			if cur_w == 1 then
				-- already the first word
				return 1, 1
			else
				-- in first line, but not first word
				return cur_l, cur_w -1 
			end
		end

		if cur_w <= 1 then
			-- first word in current line, goto previous line
			return cur_l - 1, #t[cur_l-1]
		else
			return cur_l, cur_w - 1
		end
	end

	local function _nextWord(t, cur_l, cur_w)
		if cur_l == #t then
			if cur_w == #(t[cur_l]) then
				-- already the last word
				return cur_l, cur_w
			else
				-- in last line, but not last word
				return cur_l, cur_w + 1
			end
		end

		if cur_w < #t[cur_l] then
			return cur_l, cur_w + 1
		else
			-- last word in current line, move to next line
			return cur_l + 1, 1
		end
	end

	local function _wordInNextLine(t, cur_l, cur_w)
		if cur_l == #t then
			-- already in last line, return the last word
			return cur_l, #(t[cur_l])
		else
			return cur_l + 1, math.min(cur_w, #t[cur_l+1])
		end
	end

	local function _wordInPrevLine(t, cur_l, cur_w)
		if cur_l == 1 then
			-- already in first line, return the first word
			return 1, 1
		else
			return cur_l - 1, math.min(cur_w, #t[cur_l-1])
		end
	end

	local function _isMovingForward(l, w)
		return l.cur > l.start or (l.cur == l.start and w.cur >= w.start)
	end

	local function _isMovingBackward(l, w)
		return not _isMovingForward(l, w)
	end

	local l = {}
	local w = {}

	l.start, w.start = _findFirstWordInView(t)
	--local l.start, w.start = _findFirstWordInView(t)
	if not l.start then
		print("# no text in current view!")
		return
	end

	l.cur, w.cur = l.start, w.start
	l.new, w.new = l.cur, w.cur
	local is_hightlight_mode = false
	local is_meet_start = false
	local is_meet_end = false
	local running = true
	
	self.cursor = Cursor:new {
		x_pos = t[l.cur][w.cur].x1*self.globalzoom,
		y_pos = self.offset_y + (self.cur_full_height
				- (t[l.cur][w.cur].y1 * self.globalzoom)),
		h = (t[l.cur][w.cur].y1 - t[l.cur][w.cur].y0) * self.globalzoom,
		line_width_factor = 4,
	}
	self.cursor:draw()
	fb:refresh(0)

	while running do
		local ev = input.waitForEvent()
		ev.code = adjustKeyEvents(ev)
		if ev.type == EV_KEY and ev.value == EVENT_VALUE_KEY_PRESS then
			if ev.code == KEY_FW_LEFT then
				local is_next_view = false
				if w.cur == 1 then
					w.cur = 0
					w.new = 0
				else
					if w.cur == 0 then 
						-- already at the left end of current line, 
						-- goto previous line (_prevWord does not understand
						-- zero w.cur)
						w.cur = 1 
					end
					l.new, w.new = _prevWord(t, l.cur, w.cur)
				end

				if w.new ~= 0 and 
				not self:_isWordInScreenRange(t[l.new][w.new]) then
					-- word is in previous view
					local pageno = self:prevView()
					self:goto(pageno)
					is_next_view = true
				else
					-- no need to goto next view, clear previous cursor manually
					self.cursor:clear()
				end

				-- update cursor
				if w.cur == 0 then
					-- meet line left end, must be handled as special case
					self:drawCursorBeforeWord(t, l.cur, 1)
				else
					self:drawCursorAfterWord(t, l.new, w.new)
				end
			elseif ev.code == KEY_FW_RIGHT then
				local is_next_view = false
				if w.cur == 0 then
					w.cur = 1
					w.new = 1
				else
					l.new, w.new = _nextWord(t, l.cur, w.cur)
					if w.new == 1 then
						-- Must be come from the right end of previous line, so
						-- goto the left end of current line.
						w.cur = 0
						w.new = 0
					end
				end

				if w.new ~= 0 and
				not self:_isWordInScreenRange(t[l.new][w.new]) then
					local pageno = self:nextView()
					self:goto(pageno)
					is_next_view = true
				else
					self.cursor:clear()
				end

				if w.cur == 0 then
					-- meet line left end, must be handled as special case
					self:drawCursorBeforeWord(t, l.new, 1)
				else
					self:drawCursorAfterWord(t, l.new, w.new)
				end
			elseif ev.code == KEY_FW_UP then
				local is_next_view = false
				if w.cur == 0 then
					-- goto left end of last line
					l.new = math.max(l.cur - 1, 1)
				elseif l.cur == 1 and w.cur == 1 then 
					-- already first word, to the left end of first line
					w.new = 0
				else
					l.new, w.new = _wordInPrevLine(t, l.cur, w.cur)
				end

				if w.new ~= 0 and
				not self:_isWordInScreenRange(t[l.new][w.new])
				or w.new == 0 and not self:_isWordInScreenRange(t[l.new][1]) then
					-- goto next view of current page
					local pageno = self:prevView()
					self:goto(pageno)
					is_next_view = true
				else
					self.cursor:clear()
				end

				if w.new == 0 then
					self:drawCursorBeforeWord(t, l.new, 1)
				else
					self:drawCursorAfterWord(t, l.new, w.new)
				end
			elseif ev.code == KEY_FW_DOWN then
				local is_next_view = false
				if w.cur == 0 then
					-- on the left end of current line, 
					-- goto left end of next line
					l.new = math.min(l.cur + 1, #t)
				else
					l.new, w.new = _wordInNextLine(t, l.cur, w.cur)
				end

				if w.cur ~= 0 and
				not self:_isWordInScreenRange(t[l.new][w.new]) 
				or w.cur == 0 and not self:_isWordInScreenRange(t[l.new][1]) then
					-- goto next view of current page
					local pageno = self:nextView()
					self:goto(pageno)
					is_next_view = true
				else
					self.cursor:clear()
				end

				if w.cur == 0 then
					self:drawCursorBeforeWord(t, l.new, 1)
				else
					self:drawCursorAfterWord(t, l.new, w.new)
				end
			elseif ev.code == KEY_FW_PRESS then
				if w.cur == 0 then
					w.cur = 1
				end
				l.start, w.start = l.cur, w.cur
				running = false
			elseif ev.code == KEY_BACK then
				running = false
				return
			end -- EOF if key event
			l.cur, w.cur = l.new, w.new
			fb:refresh(0)
		end
	end -- EOF while


	print("!!!!cccccccc", l.start, w.start)
	running = true

	-- in highlight mode
	while running do
		local ev = input.waitForEvent()
		ev.code = adjustKeyEvents(ev)
		if ev.type == EV_KEY and ev.value == EVENT_VALUE_KEY_PRESS then
			if ev.code == KEY_FW_LEFT then
				is_meet_end = false
				if not is_meet_start then
					local is_next_view = false
					l.new, w.new = _prevWord(t, l.cur, w.cur)

					if l.new == l.cur and w.new == w.cur then
						is_meet_start = true
					end

					if l.new ~= 0 and w.new ~= 0 and 
					not self:_isWordInScreenRange(t[l.new][w.new]) then
						-- word is in previous view
						local pageno = self:prevView()
						self:goto(pageno)
						is_next_view = true
					end

					if is_hightlight_mode then
						-- update highlight
						if w.new ~= 0 and is_next_view then
							self:_toggleTextHighLight(t, l.start, w.start, 
														l.new, w.new)
						else
							self:_toggleWordHighLight(t, l.cur, w.cur)
						end
					end
				end
			elseif ev.code == KEY_FW_RIGHT then
				is_meet_start = false
				if not is_meet_end then
					local is_next_view = false
					l.new, w.new = _nextWord(t, l.cur, w.cur)
					if l.new == l.cur and w.new == w.cur then
						is_meet_end = true
					end

					if not self:_isWordInScreenRange(t[l.new][w.new]) then
							local pageno = self:nextView()
							self:goto(pageno)
							is_next_view = true
					end

					-- update highlight
					if is_next_view then
						self:_toggleTextHighLight(t, l.start, w.start, 
													l.new, w.new)
					else
						self:_toggleWordHighLight(t, l.new, w.new)
					end
				end -- EOF if is not is_meet_end
			elseif ev.code == KEY_FW_UP then
				is_meet_end = false
				if not is_meet_start then
					local is_next_view = false
					l.new, w.new = _wordInPrevLine(t, l.cur, w.cur)

					if l.new ~= 0 and w.new ~= 0 and
					not self:_isWordInScreenRange(t[l.new][w.new]) then
						-- goto next view of current page
						local pageno = self:prevView()
						self:goto(pageno)
						is_next_view = true
					end

					-- update highlight
					if l.new ~=0 and w.new ~= 0 and is_next_view then
						-- word is in previous view
						self:_toggleTextHighLight(t, l.start, w.start, 
													l.new, w.new)
					else
						local tmp_l, tmp_w
						if _isMovingForward(l, w) then
							tmp_l, tmp_w = _nextWord(t, l.new, w.new)
							self:_toggleTextHighLight(t, tmp_l, tmp_w,
														l.cur, w.cur)
						else
							l.new, w.new = _nextWord(t, l.new, w.new)
							self:_toggleTextHighLight(t, l.new, w.new,
														l.cur, w.cur)
							l.new, w.new = _prevWord(t, l.new, w.new)
						end -- EOF if is moving forward
					end -- EOF if is previous view
				end -- EOF if is not is_meet_start
			elseif ev.code == KEY_FW_DOWN then
				local is_next_view = false
				l.new, w.new = _wordInNextLine(t, l.cur, w.cur)

				if not self:_isWordInScreenRange(t[l.new][w.new]) then
					-- goto next view of current page
					local pageno = self:nextView()
					self:goto(pageno)
					is_next_view = true
				end

				-- update highlight
				if is_next_view then
					-- redraw from start because of page refresh
					self:_toggleTextHighLight(t, l.start, w.start,
												l.new, w.new)
				else
					-- word in next is in current view, just highlight it
					if _isMovingForward(l, w) then
						l.cur, w.cur = _nextWord(t, l.cur, w.cur)
						self:_toggleTextHighLight(t, l.cur, w.cur,
													l.new, w.new)
					else
						l.cur, w.cur = _nextWord(t, l.cur, w.cur)
						self:_toggleTextHighLight(t, l.cur, w.cur,
													l.new, w.new)
					end -- EOF if moving forward
				end -- EOF if next view
			elseif ev.code == KEY_FW_PRESS then
				local first, last = 0
				if w.start < w.cur then
					first = w.start + 1
					last = w.cur
				else
					first = w.cur + 1
					last = w.start
				end
				--self:_toggleTextHighLightByEnds(t, first, last)

				local hl_item = {}
				for i=first,last,1 do
					table.insert(hl_item, t[i])
				end
				if not self.highlight[self.pageno] then
					self.highlight[self.pageno] = {}
				end
				table.insert(self.highlight[self.pageno], hl_item)

				is_hightlight_mode = false
				running = false
				self.cursor:clear()
			elseif ev.code == KEY_BACK then
				running = false
			end -- EOF if key event
			l.cur, w.cur = l.new, w.new
			fb:refresh(0)
		end
	end -- EOF while

end

