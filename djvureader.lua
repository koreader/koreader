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
	self:_toggleTextHighLightByEnds(word_list, 1, #word_list)
end

function DJVUReader:_toggleTextHighLightByEnds(t, end1, end2)
	if end1 > end2 then
		end1, end2 = end2, end1
	end

	for i=end1, end2, 1 do
		if self:_isWordInScreenRange(t[i]) then
			self:_toggleWordHighLight(t[i])
		end
	end
end

function DJVUReader:_toggleWordHighLight(w)
	local width = (w.x1-w.x0)*self.globalzoom
	local height = (w.y1-w.y0)*self.globalzoom
	fb.bb:invertRect(
		w.x0*self.globalzoom-width*0.05,
		self.offset_y+self.cur_full_height-(w.y1*self.globalzoom)-height*0.05,
		width*1.1,
		height*1.1)
end

-- remember to clear cursor before calling this
function DJVUReader:drawCursorAfterWord(w)
	self.cursor:setHeight((w.y1 - w.y0) * self.globalzoom)
	self.cursor:moveTo(w.x1 * self.globalzoom, 
				self.offset_y + self.cur_full_height - (w.y1 * self.globalzoom))
	self.cursor:draw()
end

function DJVUReader:startHighLightMode()
	local t = self.doc:getPageText(self.pageno)

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
	local running = true

	self.cursor = Cursor:new {
		x_pos = t[cur_w].x1*self.globalzoom,
		y_pos = self.offset_y + (self.cur_full_height
				- (t[cur_w].y1 * self.globalzoom)),
		h = (t[cur_w].y1 - t[cur_w].y0) * self.globalzoom,
		line_width_factor = 4,
	}
	self.cursor:draw()
	fb:refresh(0)

	while running do
		local ev = input.waitForEvent()
		ev.code = adjustKeyEvents(ev)
		if ev.type == EV_KEY and ev.value == EVENT_VALUE_KEY_PRESS then
			if ev.code == KEY_FW_LEFT then
				if cur_w >= 1 then
					local is_next_view = false
					new_w = cur_w - 1

					if new_w ~= 0 and 
					not self:_isWordInScreenRange(t[new_w]) then
						-- word is in previous view
						local pageno = self:prevView()
						self:goto(pageno)
						is_next_view = true
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
						self.cursor:draw()
					else
						self:drawCursorAfterWord(t[new_w])
					end

					if is_hightlight_mode then
						-- update highlight
						if new_w ~= 0 and is_next_view then
							self:_toggleTextHighLightByEnds(t, start_w, new_w)
						else
							self:_toggleWordHighLight(t[new_w+1])
						end
					end
				end
			elseif ev.code == KEY_FW_RIGHT then
				-- only highlight word in current page
				if cur_w < #t then
					local is_next_view = false
					new_w = cur_w + 1

					if not self:_isWordInScreenRange(t[new_w]) then
							local pageno = self:nextView()
							self:goto(pageno)
							is_next_view = true
					else
						self.cursor:clear()
					end

					-- update cursor
					self:drawCursorAfterWord(t[new_w])

					if is_hightlight_mode then
						-- update highlight
						if is_next_view then
							self:_toggleTextHighLightByEnds(t, start_w, new_w)
						else
							self:_toggleWordHighLight(t[new_w])
						end
					end
				end
			elseif ev.code == KEY_FW_UP then
					local is_next_view = false
					new_w = _wordInPrevLine(t, cur_w)

					if new_w ~= 0 and 
					not self:_isWordInScreenRange(t[new_w]) then
						-- goto next view of current page
						local pageno = self:prevView()
						self:goto(pageno)
						is_next_view = true
					else
						-- no need to jump to next view, clear previous cursor
						self.cursor:clear()
					end

					if new_w == 0 then
						-- meet top left end, must be handled as special case
						self.cursor:setHeight((t[1].y1 - t[1].y0)
												* self.globalzoom)
						self.cursor:moveTo(
							t[1].x0*self.globalzoom - self.cursor.w, 
							self.offset_y + self.cur_full_height
								- t[1].y1 * self.globalzoom)
						self.cursor:draw()
					else
						self:drawCursorAfterWord(t[new_w])
					end

					if is_hightlight_mode then
						-- update highlight
						if new_w ~= 0 and is_next_view then
							-- word is in previous view
							self:_toggleTextHighLightByEnds(t, start_w, new_w)
						else
							for i=new_w+1, cur_w, 1 do
								self:_toggleWordHighLight(t[i])
							end
						end
					end
			elseif ev.code == KEY_FW_DOWN then
				local is_next_view = false
				new_w = _wordInNextLine(t, cur_w)

				if not self:_isWordInScreenRange(t[new_w]) then
					-- goto next view of current page
					local pageno = self:nextView()
					self:goto(pageno)
					is_next_view = true
				else
					-- no need to jump to next view, clear previous cursor
					self.cursor:clear()
				end

				-- update cursor
				self:drawCursorAfterWord(t[new_w])

				if is_hightlight_mode then
					-- update highlight
					if is_next_view then
						-- redraw from start because of page refresh
						self:_toggleTextHighLightByEnds(t, start_w, new_w)
					else
						-- word in next is in current view, just highlight it
						for i=cur_w+1, new_w, 1 do
							self:_toggleWordHighLight(t[i])
						end
					end
				end
			elseif ev.code == KEY_FW_PRESS then
				if not is_hightlight_mode then
					is_hightlight_mode = true
					start_w = cur_w
				else -- pressed in highlight mode, record selected text
					local first, last = 0
					if start_w < cur_w then
						first = start_w + 1
						last = cur_w
					else
						first = cur_w + 1
						last = start_w
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
				end
			end -- EOF if keyevent
			cur_w = new_w
			fb:refresh(0)
		end -- EOF while
	end
end

