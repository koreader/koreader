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



-----------[ highlight support ]----------

----------------------------------------------------
-- Given coordinates of four conners and return
-- coordinate of upper left conner with with and height
--
-- In djvulibre library, some coordinates starts from
-- down left conner, i.e. y is upside down. This method
-- only transform these coordinates.
----------------------------------------------------
function DJVUReader:_rectCoordTransform(x0, y0, x1, y1)
	return 
		self.offset_x + x0 * self.globalzoom,
		self.offset_y + self.cur_full_height - (y1 * self.globalzoom),
		(x1 - x0) * self.globalzoom,
		(y1 - y0) * self.globalzoom
end

-- make sure the whole word can be seen in screen
function DJVUReader:_isEntireWordInScreenRange(w)
	return self:_isEntireWordInScreenHeightRange(w) and
			self:_isEntireWordInScreenWidthRange(w)
end

-- y axel in djvulibre starts from bottom
function DJVUReader:_isEntireWordInScreenHeightRange(w)
	return	(w ~= nil) and
			(self.cur_full_height - (w.y1 * self.globalzoom) >=
				-self.offset_y) and
			(self.cur_full_height - (w.y0 * self.globalzoom) <= 
				-self.offset_y + height)
end

function DJVUReader:_isEntireWordInScreenWidthRange(w)
	return	(w ~= nil) and
			(w.x0 * self.globalzoom >= -self.offset_x) and
			(w.x1 * self.globalzoom <= -self.offset_x + width)
end

-- make sure at least part of the word can be seen in screen
function DJVUReader:_isWordInScreenRange(w)
	return	(w ~= nil) and
			(self.cur_full_height - (w.y0 * self.globalzoom) >=
				-self.offset_y) and
			(self.cur_full_height - (w.y1 * self.globalzoom) <= 
				-self.offset_y + height) and
			(w.x1 * self.globalzoom >= -self.offset_x) and
			(w.x0 * self.globalzoom <= -self.offset_x + width)
end

function DJVUReader:toggleTextHighLight(word_list)
	for _,text_item in ipairs(word_list) do
		for _,line_item in ipairs(text_item) do
			-- make sure that line is in screen range
			if self:_isEntireWordInScreenHeightRange(line_item) then
				local x, y, w, h = self:_rectCoordTransform(
										line_item.x0, line_item.y0,
										line_item.x1, line_item.y1)
				-- slightly enlarge the highlight height 
				-- for better viewing experience
				x = x
				y = y - h * 0.1
				w = w
				h = h * 1.2

				self.highlight.drawer = self.highlight.drawer or "underscore"
				if self.highlight.drawer == "underscore" then
					self.highlight.line_width = self.highlight.line_width or 2
					self.highlight.line_color = self.highlight.line_color or 5
					fb.bb:paintRect(x, y+h-1, w,
						self.highlight.line_width,
						self.highlight.line_color)
				elseif self.highlight.drawer == "marker" then
					fb.bb:invertRect(x, y, w, h)
				end
			end -- EOF if isEntireWordInScreenHeightRange
		end -- EOF for line_item
	end -- EOF for text_item
end

function DJVUReader:_wordIterFromRange(t, l0, w0, l1, w1)
	local i = l0
	local j = w0 - 1
	return function()
		if i <= l1 then
			-- if in line range, loop through lines
			if i == l1 then
				-- in last line
				if j < w1 then
					j = j + 1
				else
					-- out of range return nil
					return nil, nil
				end
			else
				if j < #t[i] then
					j = j + 1
				else
					-- goto next line
					i = i + 1
					j = 1
				end
			end
			return i, j
		end
	end -- EOF closure
end

function DJVUReader:_toggleWordHighLight(t, l, w)
	x, y, w, h = self:_rectCoordTransform(t[l][w].x0, t[l].y0, 
										t[l][w].x1, t[l].y1)
	-- slightly enlarge the highlight range for better viewing experience
	x = x - w * 0.05
	y = y - h * 0.05
	w = w * 1.1
	h = h * 1.1
	
	fb.bb:invertRect(x, y, w, h)
end

function DJVUReader:_toggleTextHighLight(t, l0, w0, l1, w1)
	--print("# toggle range", l0, w0, l1, w1)
	-- make sure (l0, w0) is smaller than (l1, w1)
	if l0 > l1 then
		l0, l1 = l1, l0
		w0, w1 = w1, w0
	elseif l0 == l1 and w0 > w1 then
		w0, w1 = w1, w0
	end

	for _l, _w in self:_wordIterFromRange(t, l0, w0, l1, w1) do
		if self:_isWordInScreenRange(t[_l][_w]) then
			-- blitbuffer module will take care of the out of screen range part.
			self:_toggleWordHighLight(t, _l, _w)
		end
	end
end

-- remember to clear cursor before calling this
function DJVUReader:drawCursorAfterWord(t, l, w)
	self.cursor:setHeight((t[l].y1 - t[l].y0) * self.globalzoom)
	self.cursor:moveTo(
		self.offset_x + t[l][w].x1 * self.globalzoom, 
		self.offset_y + self.cur_full_height - (t[l].y1 * self.globalzoom))
	self.cursor:draw()
end

function DJVUReader:drawCursorBeforeWord(t, l, w)
	self.cursor:setHeight((t[l].y1 - t[l].y0)
							* self.globalzoom)
	self.cursor:moveTo(
		self.offset_x + t[l][w].x0 * self.globalzoom - self.cursor.w, 
		self.offset_y + self.cur_full_height - t[l].y1 * self.globalzoom)
	self.cursor:draw()
end

function DJVUReader:startHighLightMode()
	local t = self.doc:getPageText(self.pageno)

	local function _findFirstWordInView(t)
		for i=1, #t, 1 do
			if self:_isEntireWordInScreenRange(t[i][1]) then
				return i, 1
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
		return l.cur > l.start or (l.cur == l.start and w.cur > w.start)
	end

	local l = {}
	local w = {}

	l.start, w.start = _findFirstWordInView(t)
	if not l.start then
		print("# no text in current view!")
		return
	end

	l.cur, w.cur = l.start, w.start
	l.new, w.new = l.cur, w.cur
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
	fb:refresh(1)

	-- first use cursor to place start pos for highlight
	while running do
		local ev = input.waitForEvent()
		ev.code = adjustKeyEvents(ev)
		if ev.type == EV_KEY and ev.value == EVENT_VALUE_KEY_PRESS then
			if ev.code == KEY_FW_LEFT then
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

				self.cursor:clear()
				if w.new ~= 0
				and not self:_isEntireWordInScreenHeightRange(t[l.new][w.new])
				and self:_isEntireWordInScreenWidthRange(t[l.new][w.new]) then
					-- word is in previous view
					local pageno = self:prevView()
					self:goto(pageno)
				end

				-- update cursor
				if w.cur == 0 then
					-- meet line left end, must be handled as special case
					if self:_isEntireWordInScreenRange(t[l.cur][1]) then
						self:drawCursorBeforeWord(t, l.cur, 1)
					end
				else
					if self:_isEntireWordInScreenRange(t[l.new][w.new]) then
						self:drawCursorAfterWord(t, l.new, w.new)
					end
				end
			elseif ev.code == KEY_FW_RIGHT then
				if w.cur == 0 then
					w.cur = 1
					w.new = 1
				else
					l.new, w.new = _nextWord(t, l.cur, w.cur)
					if w.new == 1 then
						-- Must be come from the right end of previous line,
						-- so goto the left end of current line.
						w.cur = 0
						w.new = 0
					end
				end

				self.cursor:clear()

				local tmp_w = w.new
				if w.cur == 0 then
					tmp_w = 1
				end
				if not self:_isEntireWordInScreenHeightRange(t[l.new][tmp_w]) 
				and self:_isEntireWordInScreenWidthRange(t[l.new][tmp_w]) then
					local pageno = self:nextView()
					self:goto(pageno)
				end

				if w.cur == 0 then
					-- meet line left end, must be handled as special case
					if self:_isEntireWordInScreenRange(t[l.new][1]) then
						self:drawCursorBeforeWord(t, l.new, 1)
					end
				else
					if self:_isEntireWordInScreenRange(t[l.new][w.new]) then
						self:drawCursorAfterWord(t, l.new, w.new)
					end
				end
			elseif ev.code == KEY_FW_UP then
				if w.cur == 0 then
					-- goto left end of last line
					l.new = math.max(l.cur - 1, 1)
				elseif l.cur == 1 and w.cur == 1 then 
					-- already first word, to the left end of first line
					w.new = 0
				else
					l.new, w.new = _wordInPrevLine(t, l.cur, w.cur)
				end

				self.cursor:clear()

				local tmp_w = w.new
				if w.cur == 0 then
					tmp_w = 1
				end
				if not self:_isEntireWordInScreenHeightRange(t[l.new][tmp_w]) 
				and self:_isEntireWordInScreenWidthRange(t[l.new][tmp_w]) then
					-- goto next view of current page
					local pageno = self:prevView()
					self:goto(pageno)
				end

				if w.new == 0 then
					if self:_isEntireWordInScreenRange(t[l.new][1]) then
						self:drawCursorBeforeWord(t, l.new, 1)
					end
				else
					if self:_isEntireWordInScreenRange(t[l.new][w.new]) then
						self:drawCursorAfterWord(t, l.new, w.new)
					end
				end
			elseif ev.code == KEY_FW_DOWN then
				if w.cur == 0 then
					-- on the left end of current line, 
					-- goto left end of next line
					l.new = math.min(l.cur + 1, #t)
				else
					l.new, w.new = _wordInNextLine(t, l.cur, w.cur)
				end

				self.cursor:clear()

				local tmp_w = w.new
				if w.cur == 0 then
					tmp_w = 1
				end
				if not self:_isEntireWordInScreenHeightRange(t[l.new][tmp_w]) 
				and self:_isEntireWordInScreenWidthRange(t[l.new][tmp_w]) then
					-- goto next view of current page
					local pageno = self:nextView()
					self:goto(pageno)
				end

				if w.cur == 0 then
					if self:_isEntireWordInScreenRange(t[l.new][1]) then
						self:drawCursorBeforeWord(t, l.new, 1)
					end
				else
					if self:_isEntireWordInScreenRange(t[l.new][w.new]) then
						self:drawCursorAfterWord(t, l.new, w.new)
					end
				end
			elseif ev.code == KEY_DEL then
				if self.highlight[self.pageno] then
					for k, text_item in ipairs(self.highlight[self.pageno]) do
						for _, line_item in ipairs(text_item) do
							if t[l.cur][w.cur].y0 >= line_item.y0
							and t[l.cur][w.cur].y1 <= line_item.y1
							and t[l.cur][w.cur].x0 >= line_item.x0
							and t[l.cur][w.cur].x1 <= line_item.x1 then
								self.highlight[self.pageno][k] = nil
							end
						end -- EOF for line_item
					end -- EOF for text_item
				end -- EOF if not highlight table
				if #self.highlight[self.pageno] == 0 then
					self.highlight[self.pageno] = nil
				end
				return
			elseif ev.code == KEY_FW_PRESS then
				if w.cur == 0 then
					w.cur = 1
					l.cur, w.cur = _prevWord(t, l.cur, w.cur)
				end
				l.new, w.new = l.cur, w.cur
				l.start, w.start = l.cur, w.cur
				running = false
				self.cursor:clear()
			elseif ev.code == KEY_BACK then
				running = false
				return
			end -- EOF if key event
			l.cur, w.cur = l.new, w.new
			fb:refresh(1)
		end
	end -- EOF while
	--print("start", l.cur, w.cur, l.start, w.start)

	-- two helper functions for highlight
	local function _togglePrevWordHighLight(t, l, w)
		l.new, w.new = _prevWord(t, l.cur, w.cur)

		if l.cur == 1 and w.cur == 1 then
			is_meet_start = true
			-- left end of first line must be handled as special case
			w.new = 0
		end

		if w.new ~= 0 and 
		not self:_isEntireWordInScreenHeightRange(t[l.new][w.new]) then
			-- word out of left and right sides of current view should
			-- not trigger pan by page
			if self:_isEntireWordInScreenWidthRange(t[l.new][w.new]) then
				-- word is in previous view
				local pageno = self:prevView()
				self:goto(pageno)
			end

			local l0 = l.start
			local w0 = w.start
			local l1 = l.cur
			local w1 = w.cur
			if _isMovingForward(l, w) then
				l0, w0 = _nextWord(t, l0, w0)
				l1, w1 = l.new, w.new
			end
			self:_toggleTextHighLight(t, l0, w0, 
										l1, w1)
		else
			self:_toggleWordHighLight(t, l.cur, w.cur)
		end

		l.cur, w.cur = l.new, w.new
		return l, w, (is_meet_start or false)
	end

	local function _toggleNextWordHighLight(t, l, w)
		if w.cur == 0 then
			w.new = 1
		else
			l.new, w.new = _nextWord(t, l.cur, w.cur)
		end
		if l.new == #t and w.new == #t[#t] then
			is_meet_end = true
		end

		if not self:_isEntireWordInScreenHeightRange(t[l.new][w.new]) then
			if self:_isEntireWordInScreenWidthRange(t[l.new][w.new]) then
				local pageno = self:nextView()
				self:goto(pageno)
			end

			local tmp_l = l.start
			local tmp_w = w.start
			if _isMovingForward(l, w) then
				tmp_l, tmp_w = _nextWord(t, tmp_l, tmp_w)
			end
			self:_toggleTextHighLight(t, tmp_l, tmp_w, 
										l.new, w.new)
		else
			self:_toggleWordHighLight(t, l.new, w.new)
		end

		l.cur, w.cur = l.new, w.new
		return l, w, (is_meet_end or false)
	end


	-- go into highlight mode
	running = true
	while running do
		local ev = input.waitForEvent()
		ev.code = adjustKeyEvents(ev)
		if ev.type == EV_KEY and ev.value == EVENT_VALUE_KEY_PRESS then
			if ev.code == KEY_FW_LEFT then
				is_meet_end = false
				if not is_meet_start then
					l, w, is_meet_start = _togglePrevWordHighLight(t, l, w)
				end
			elseif ev.code == KEY_FW_RIGHT then
				is_meet_start = false
				if not is_meet_end then
					l, w, is_meet_end = _toggleNextWordHighLight(t, l, w)
				end -- EOF if is not is_meet_end
			elseif ev.code == KEY_FW_UP then
				is_meet_end = false
				if not is_meet_start then
					if l.cur == 1 then
						-- handle left end of first line as special case
						tmp_l = 1
						tmp_w = 0
					else
						tmp_l, tmp_w = _wordInPrevLine(t, l.cur, w.cur)
					end
					while not (tmp_l == l.cur and tmp_w == w.cur) do
						l, w, is_meet_start = _togglePrevWordHighLight(t, l, w)
					end
				end
			elseif ev.code == KEY_FW_DOWN then
				is_meet_start = false
				if not is_meet_end then
					if w.cur == 0 then
						-- handle left end of first line as special case
						tmp_l = math.min(tmp_l + 1, #t)
						tmp_w = 1
					else
						tmp_l, tmp_w = _wordInNextLine(t, l.new, w.new)
					end
					while not (tmp_l == l.cur and tmp_w == w.cur) do
						l, w, is_meet_end = _toggleNextWordHighLight(t, l, w)
					end
				end
			elseif ev.code == KEY_FW_PRESS then
				local l0, w0, l1, w1

				-- find start and end of highlight text
				if _isMovingForward(l, w) then
					l0, w0 = _nextWord(t, l.start, w.start)
					l1, w1 = l.cur, w.cur
				else
					l0, w0 = _nextWord(t, l.cur, w.cur)
					l1, w1 = l.start, w.start
				end
				-- remove selection area
				self:_toggleTextHighLight(t, l0, w0, l1, w1)

				-- put text into highlight table of current page
				local hl_item = {}
				local s = ""
				local prev_l = l0
				local prev_w = w0
				local l_item = {
					x0 = t[l0][w0].x0,
					y0 = t[l0].y0,
					y1 = t[l0].y1,
				}
				for _l,_w in self:_wordIterFromRange(t, l0, w0, l1, w1) do
					local word_item = t[_l][_w]
					if _l > prev_l then
						-- in next line, add previous line to highlight item
						l_item.x1 = t[prev_l][prev_w].x1
						table.insert(hl_item, l_item)
						-- re initialize l_item for new line
						l_item = {
							x0 = word_item.x0, 
							y0 = t[_l].y0,
							y1 = t[_l].y1,
						}
					end
					s = s .. word_item.word .. " "
					prev_l, prev_w = _l, _w
				end
				-- insert last line of text in line item
				l_item.x1 = t[prev_l][prev_w].x1
				table.insert(hl_item, l_item)
				hl_item.text = s

				if not self.highlight[self.pageno] then
					self.highlight[self.pageno] = {}
				end
				table.insert(self.highlight[self.pageno], hl_item)

				running = false
			elseif ev.code == KEY_BACK then
				running = false
			end -- EOF if key event
			fb:refresh(1)
		end
	end -- EOF while
end

