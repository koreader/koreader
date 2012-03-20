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

function DJVUReader:_toggleWordHighLightByEnds(t, end1, end2)
	if end1 > end2 then
		end1, end2 = end2, end1
	end

	for i=end1, end2, 1 do
		if self:_isWordInScreenRange(t[i]) then
			self:_toggleWordHighLight(t[i])
		end
	end
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

function DJVUReader:getScreenPosByPagePos()
end

function DJVUReader:_toggleWordHighLight(w)
	fb.bb:invertRect(
		w.x0*self.globalzoom,
		self.offset_y+self.cur_full_height-(w.y1*self.globalzoom),
		(w.x1-w.x0)*self.globalzoom,
		(w.y1-w.y0)*self.globalzoom, 15)
end

function DJVUReader:startHighLightMode()
	local t = self.doc:getPageText(self.pageno)

	--print(dump(t))

	local function _getLineByWord(t, cur_w)
		for k,l in ipairs(t.lines) do
			if l.last >= cur_w then
				return k
			end
		end
	end

	local function _findFirstWordInView(t)
		for k,v in ipairs(t) do
			if self:_isWordInScreenRange(v) then
				return k
			end
		end
		return nil
	end

	local function _wordInNextLine(t, cur_w)
		local cur_l = _getLineByWord(t, cur_w)
		if cur_l == #t.lines then
			-- already in last line, return the last word
			return t.lines[cur_l].last
		else
			local next_l_start = t.lines[cur_l].last + 1
			local cur_l_start = 1
			if cur_l ~= 1 then
				cur_l_start = t.lines[cur_l-1].last + 1
			end

			cur_w = next_l_start + (cur_w - cur_l_start)
			if cur_w > t.lines[cur_l+1].last then
				cur_w = t.lines[cur_l+1].last
			end
			return cur_w
		end
	end

	local function _wordInPrevLine(t, cur_w)
		local cur_l = _getLineByWord(t, cur_w)
		if cur_l == 1 then
			-- already in first line, return 0
			return 0
		else
			local prev_l_start = 1
			if cur_l > 2 then
				-- previous line is not the first line
				prev_l_start = t.lines[cur_l-2].last + 1
			end
			local cur_l_start = t.lines[cur_l-1].last + 1

			cur_w = prev_l_start + (cur_w - cur_l_start)
			if cur_w > t.lines[cur_l-1].last then
				cur_w = t.lines[cur_l-1].last
			end
			return cur_w
		end
	end


	local start_w = _findFirstWordInView(t)
	if not start_w then
		print("# no text in current view!")
		return
	end

	local cur_w = start_w
	local new_w = 1
	local is_hightlight_mode = false

	self.cursor = Cursor:new {
		x_pos = t[cur_w].x1*self.globalzoom,
		y_pos = self.offset_y + (self.cur_full_height
				- (t[cur_w].y1 * self.globalzoom)),
		h = (t[cur_w].y1-t[cur_w].y0)*self.globalzoom,
	}

	self.cursor:draw()
	fb:refresh(0)

	while true do
		local ev = input.waitForEvent()
		ev.code = adjustKeyEvents(ev)
		if ev.type == EV_KEY and ev.value == EVENT_VALUE_KEY_PRESS then
			if ev.code == KEY_FW_LEFT then
				if cur_w >= 1 then
					new_w = cur_w - 1

					if new_w ~= 0 and 
					not self:_isWordInScreenRange(t[new_w]) then
						-- word is in previous view
						local pageno = self:prevView()
						self:goto(pageno)
					else
						self.cursor:clear()
					end

					-- update cursor
					if new_w == 0 then
						-- meet top end, must be handled as special case
						self.cursor:setHeight((t[1].y1 - t[1].y0)
												* self.globalzoom)
						self.cursor:moveTo(
							t[1].x0*self.globalzoom - self.cursor.w, 
							self.offset_y + self.cur_full_height
								- t[1].y1 * self.globalzoom)
					else
						self.cursor:setHeight((t[new_w].y1 - t[new_w].y0)
												* self.globalzoom)
						self.cursor:moveTo(t[new_w].x1*self.globalzoom, 
										self.offset_y + self.cur_full_height
										- (t[new_w].y1*self.globalzoom))
					end
					self.cursor:draw()

					if is_hightlight_mode then
						-- update highlight
						if new_w ~= 0 and 
						not self:_isWordInScreenRange(t[new_w]) then
							self:_toggleWordHighLightByEnds(t, start_w, new_w)
						else
							self:_toggleWordHighLight(t[new_w+1])
						end
					end

					cur_w = new_w
				end
			elseif ev.code == KEY_FW_RIGHT then
				-- only highlight word in current page
				if cur_w < #t then
					new_w = cur_w + 1

					if not self:_isWordInScreenRange(t[new_w]) then
							local pageno = self:nextView()
							self:goto(pageno)
					else
						self.cursor:clear()
					end

					-- update cursor
					self.cursor:setHeight((t[new_w].y1 - t[new_w].y0)
											* self.globalzoom)
					self.cursor:moveTo(t[new_w].x1*self.globalzoom, 
									self.offset_y + self.cur_full_height
									- (t[new_w].y1 * self.globalzoom))
					self.cursor:draw()

					if is_hightlight_mode then
						-- update highlight
						if not self:_isWordInScreenRange(t[new_w]) then
							-- word to highlight is in next view
							self:_toggleWordHighLightByEnds(t, start_w, new_w)
						else
							self:_toggleWordHighLight(t[new_w])
						end
					end

					cur_w = new_w
				end
			elseif ev.code == KEY_FW_UP then
					new_w = _wordInPrevLine(t, cur_w)

					if new_w ~= 0 and 
					not self:_isWordInScreenRange(t[new_w]) then
						-- goto next view of current page
						local pageno = self:prevView()
						self:goto(pageno)
					else
						-- no need to jump to next view, clear previous cursor
						self.cursor:clear()
					end

					if new_w == 0 then
						-- meet top end, must be handled as special case
						self.cursor:setHeight((t[1].y1 - t[1].y0)
												* self.globalzoom)
						self.cursor:moveTo(
							t[1].x0*self.globalzoom - self.cursor.w, 
							self.offset_y + self.cur_full_height
								- t[1].y1 * self.globalzoom)
					else
						self.cursor:setHeight((t[new_w].y1 - t[new_w].y0)
												* self.globalzoom)
						self.cursor:moveTo(t[new_w].x1*self.globalzoom, 
										self.offset_y + self.cur_full_height
										- (t[new_w].y1*self.globalzoom))
					end
					self.cursor:draw()

					if is_hightlight_mode then
						-- update highlight
						if new_w ~= 0 and 
						not self:_isWordInScreenRange(t[new_w]) then
							-- word is in previous view
							self:_toggleWordHighLightByEnds(t, start_w, new_w)
						else
							for i=new_w+1, cur_w, 1 do
								self:_toggleWordHighLight(t[i])
							end
						end
					end

					cur_w = new_w
			elseif ev.code == KEY_FW_DOWN then
				new_w = _wordInNextLine(t, cur_w)

				if not self:_isWordInScreenRange(t[new_w]) then
					-- goto next view of current page
					local pageno = self:nextView()
					self:goto(pageno)
				else
					-- no need to jump to next view, clear previous cursor
					self.cursor:clear()
				end

				-- update cursor
				self.cursor:setHeight((t[new_w].y1 - t[new_w].y0)
										* self.globalzoom)
				self.cursor:moveTo(t[new_w].x1*self.globalzoom, 
								self.offset_y + self.cur_full_height
								- (t[new_w].y1*self.globalzoom))
				self.cursor:draw()

				if is_hightlight_mode then
					-- update highlight
					if not self:_isWordInScreenRange(t[new_w]) then
						-- redraw from start because of page refresh
						self:_toggleWordHighLightByEnds(t, start_w, new_w)
					else
						-- word in next is in current view, just highlight it
						for i=cur_w+1, new_w, 1 do
							self:_toggleWordHighLight(t[i])
						end
					end
				end

				cur_w = new_w
			elseif ev.code == KEY_FW_PRESS then
				if not is_hightlight_mode then
					is_hightlight_mode = true
					start_w = cur_w
				else -- pressed in highlight mode, record selected text
					if start_w < cur_w then
						self:_toggleWordHighLightByEnds(t, start_w+1, cur_w)
					else
						self:_toggleWordHighLightByEnds(t, cur_w+1, start_w)
					end
					is_hightlight_mode = false
				end
			end -- EOF if keyevent
			fb:refresh(0)
		end -- EOF while
	end
end

