require "keys"
require "settings"
require "selectmenu"
require "commands"
require "helppage"

UniReader = {
	-- "constants":
	ZOOM_BY_VALUE = 0,
	ZOOM_FIT_TO_PAGE = -1,
	ZOOM_FIT_TO_PAGE_WIDTH = -2,
	ZOOM_FIT_TO_PAGE_HEIGHT = -3,
	ZOOM_FIT_TO_CONTENT = -4,
	ZOOM_FIT_TO_CONTENT_WIDTH = -5,
	ZOOM_FIT_TO_CONTENT_HEIGHT = -6,
	ZOOM_FIT_TO_CONTENT_WIDTH_PAN = -7,
	--ZOOM_FIT_TO_CONTENT_HEIGHT_PAN = -8,
	ZOOM_FIT_TO_CONTENT_HALF_WIDTH_MARGIN = -9,
	ZOOM_FIT_TO_CONTENT_HALF_WIDTH = -10,

	GAMMA_NO_GAMMA = 1.0,

	-- framebuffer update policy state:
	rcount = 5,
	rcountmax = 5,

	-- zoom state:
	globalzoom = 1.0,
	globalzoom_orig = 1.0,
	globalzoommode = -1, -- ZOOM_FIT_TO_PAGE

	globalrotate = 0,

	-- gamma setting:
	globalgamma = 1.0,   -- GAMMA_NO_GAMMA

	-- cached tile size
	fullwidth = 0,
	fullheight = 0,
	-- size of current page for current zoom level in pixels
	cur_full_width = 0,
	cur_full_height = 0,
	offset_x = 0,
	offset_y = 0,
	dest_x = 0, -- real offset_x when it's smaller than screen, so it's centered
	dest_y = 0,
	min_offset_x = 0,
	min_offset_y = 0,
	content_top = 0, -- for ZOOM_FIT_TO_CONTENT_WIDTH_PAN (prevView)

	-- set panning distance
	shift_x = 100,
	shift_y = 50,
	pan_by_page = false, -- using shift_[xy] or width/height
	pan_x = 0, -- top-left offset of page when pan activated
	pan_y = 0,
	pan_margin = 20, -- horizontal margin for two-column zoom
	pan_overlap_vertical = 30,
	show_overlap = 0,

	-- the document:
	doc = nil,
	-- the document's setting store:
	settings = nil,
	-- list of available commands:
	commands = nil,

	-- we will use this one often, so keep it "static":
	nulldc = DrawContext.new(),

	-- tile cache configuration:
	cache_max_memsize = 1024*1024*5, -- 5MB tile cache
	cache_max_ttl = 20, -- time to live
	-- tile cache state:
	cache_current_memsize = 0,
	cache = {},
	-- renderer cache size
	cache_document_size = 1024*1024*8, -- FIXME random, needs testing

	pagehash = nil,

	jump_stack = {},
	highlight = {},
	toc = nil,

	bbox = {}, -- override getUsedBBox
}

function UniReader:new(o)
	o = o or {}
	setmetatable(o, self)
	self.__index = self
	return o
end

----------------------------------------------------
-- !!!!!!!!!!!!!!!!!!!!!!!!!
--
-- For a new specific reader,
-- you must always overwrite following method:
--
-- * self:open()
--
-- overwrite other methods if needed.
----------------------------------------------------

-- open a file
function UniReader:open(filename, cache_size)
	return false
end

function UniReader:init()
	-- initialize commands
	self:addAllCommands()
end

----------------------------------------------------
-- highlight support 
----------------------------------------------------

function UniReader:screenOffset()
	local x = self.dest_x
	local y = self.dest_y
	if self.offset_x < 0 then
		x = x + self.offset_x
	end
	if self.offset_y < 0 then
		y = y + self.offset_y
	end
	print("# screenOffset "..x..","..y)
	return x,y
end

----------------------------------------------------
-- Given coordinates of four corners in original page
-- size and return coordinate of upper left conner in 
-- zoomed page size with width and height.
----------------------------------------------------
function UniReader:zoomedRectCoordTransform(x0, y0, x1, y1)
	local x,y = self:screenOffset()
	return
		x0 * self.globalzoom + x,
		y0 * self.globalzoom + y,
		(x1 - x0) * self.globalzoom,
		(y1 - y0) * self.globalzoom
end

----------------------------------------------------
-- Given coordinates of four corners in original page
-- size and return rectangular area in screen. You
-- might want to call this when you want to draw stuff
-- on screen.
--
-- NOTE: this method does not check whether given area
-- is can be shown in current screen. Make sure to check
-- with _isEntireWordInScreenRange() or _isWordInScreenRange()
-- before you want to draw on the returned area.
----------------------------------------------------
function UniReader:getRectInScreen(x0, y0, x1, y1)
	x, y, w, h = self:zoomedRectCoordTransform(x0, y0, x1, y1)
	if x < 0 then
		w = w + x
		x = 0 
	end
	if y < 0 then
		h = h + y
		y = 0 
	end
	if x + w > G_width then w = G_width - x end
	if y + h > G_height then h = G_height - y end
	return x, y, w, h
end

-- make sure the whole word/line can be seen in screen
-- @TODO when not in FIT_TO_CONTENT_WIDTH mode,
-- self.offset_{x,y} might be negative. 12.04 2012 (houqp)
function UniReader:_isEntireLineInScreenHeightRange(l)
	return	(l ~= nil) and
			(l.y0 * self.globalzoom) >= -self.offset_y
			and (l.y1 * self.globalzoom) <= -self.offset_y + G_height
end

function UniReader:_isEntireWordInScreenRange(w)
	return self:_isEntireWordInScreenHeightRange(w) and
			self:_isEntireWordInScreenWidthRange(w)
end

function UniReader:_isEntireWordInScreenHeightRange(w)
	return	(w ~= nil) and
			(w.y0 * self.globalzoom) >= -self.offset_y
			and (w.y1 * self.globalzoom) <= -self.offset_y + G_height
end

function UniReader:_isEntireWordInScreenWidthRange(w)
	return	(w ~= nil) and
			(w.x0 * self.globalzoom >= -self.offset_x) and
			(w.x1 * self.globalzoom <= -self.offset_x + G_width)
end

-- make sure at least part of the word can be seen in screen
function UniReader:_isWordInScreenRange(w)
	if not w then
		return false
	end

	is_entire_word_out_of_screen_height = 
		(w.y1 * self.globalzoom <= -self.offset_y)
		or (w.y0 * self.globalzoom >= -self.offset_y + G_height)

	is_entire_word_out_of_screen_width = 
			(w.x0 * self.globalzoom >= -self.offset_x + G_width
			or w.x1 * self.globalzoom <= -self.offset_x)

	return	(not is_entire_word_out_of_screen_height) and
			(not is_entire_word_out_of_screen_width)
end

function UniReader:toggleTextHighLight(word_list)
	for _,text_item in ipairs(word_list) do
		for _,line_item in ipairs(text_item) do
			-- make sure that line is in screen range
			if self:_isWordInScreenRange(line_item) then
				local x, y, w, h = self:getRectInScreen(
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
			end -- if isEntireWordInScreenHeightRange
		end -- for line_item
	end -- for text_item
end

function UniReader:_wordIterFromRange(t, l0, w0, l1, w1)
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
	end -- closure
end

function UniReader:_toggleWordHighLight(t, l, w)
	x, y, w, h = self:getRectInScreen(t[l][w].x0, t[l].y0, 
										t[l][w].x1, t[l].y1)
	-- slightly enlarge the highlight range for better viewing experience
	x = x - w * 0.05
	y = y - h * 0.05
	w = w * 1.1
	h = h * 1.1
	
	fb.bb:invertRect(x, y, w, h)
end

function UniReader:_toggleTextHighLight(t, l0, w0, l1, w1)
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
function UniReader:drawCursorAfterWord(t, l, w)
	-- get height of line t[l][w] is in
	local _, _, _, h = self:zoomedRectCoordTransform(0, t[l].y0, 0, t[l].y1)
	-- get rect of t[l][w]
	local x, y, wd, _ = self:getRectInScreen(t[l][w].x0, t[l][w].y0, t[l][w].x1, t[l][w].y1)
	self.cursor:setHeight(h)
	self.cursor:moveTo(x+wd, y)
	self.cursor:draw()
end

function UniReader:drawCursorBeforeWord(t, l, w)
	-- get height of line t[l][w] is in
	local _, _, _, h = self:zoomedRectCoordTransform(0, t[l].y0, 0, t[l].y1)
	-- get rect of t[l][w]
	local x, y, _, _ = self:getRectInScreen(t[l][w].x0, t[l][w].y0, t[l][w].x1, t[l][w].y1)
	self.cursor:setHeight(h)
	self.cursor:moveTo(x, y)
	self.cursor:draw()
end

function UniReader:getText(pageno)
	-- define a sensible implementation when your reader supports it
	return nil
end

function UniReader:startHighLightMode()
	local t = self:getText(self.pageno)
	if not t or #t == 0 then
		return nil
	end

	local function _findFirstWordInView(t)
		for i=1, #t, 1 do
			if self:_isEntireWordInScreenRange(t[i][1]) then
				return i, 1
			end
		end

		print("## _findFirstWordInView none found in "..dump(t))

		return nil
	end

	local function _isMovingForward(l, w)
		return l.cur > l.start or (l.cur == l.start and w.cur > w.start)
	end

	---------------------------------------
	-- some word handling help functions
	---------------------------------------
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

	---------------------------------------
	-- some gap handling help functions
	---------------------------------------
	local function _nextGap(t, cur_l, cur_w)
		local is_meet_end = false

		-- handle left end of line as special case.
		if cur_w == 0 then
			if cur_l == #t and #t[cur_l] == 1 then
				is_meet_end = true
			end
			return cur_l, 1, is_meet_end
		end

		cur_l, cur_w = _nextWord(t, cur_l, cur_w)
		if cur_w == 1 then
			cur_w = 0
		end
		if cur_w ~= 0 and cur_l == #t and cur_w == #t[cur_l] then
			is_meet_end = true
		end
		return cur_l, cur_w, is_meet_end
	end

	local function _prevGap(t, cur_l, cur_w)
		local is_meet_start = false

		-- handle left end of line as special case.
		if cur_l == 1 and (cur_w == 1 or cur_w == 0) then -- in the first line
			is_meet_start = true
			return cur_l, 0, is_meet_start
		end
		if cur_w == 1 then -- not in the first line
			return cur_l, 0, is_meet_start
		elseif cur_w == 0 then
			-- set to 1 so _prevWord() can find previous word in previous line
			cur_w = 1
		end

		cur_l, cur_w = _prevWord(t, cur_l, cur_w)
		return cur_l, cur_w, is_meet_end
	end

	local function _gapInNextLine(t, cur_l, cur_w)
		local is_meet_end = false

		if cur_l == #t then
			-- already in last line
			cur_w = #t[cur_l]
			is_meet_end = true
		else
			-- handle left end of line as special case.
			if cur_w == 0 then
				cur_l = math.min(cur_l + 1, #t)
			else
				cur_l, cur_w = _wordInNextLine(t, cur_l, cur_w)
			end
		end

		return cur_l, cur_w, is_meet_end
	end

	local function _gapInPrevLine(t, cur_l, cur_w)
		local is_meet_start = false

		if cur_l == 1 then
			-- already in first line
			is_meet_start = true
			cur_w = 0
		else
			if cur_w == 0 then
				-- goto left end of previous line
				cur_l = math.max(cur_l - 1, 1)
			else
				cur_l, cur_w = _wordInPrevLine(t, cur_l, cur_w)
			end
		end

		return cur_l, cur_w, is_meet_start
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

	local cx, cy, cw, ch = self:getRectInScreen(
		t[l.cur][w.cur].x0,
		t[l.cur][w.cur].y0,
		t[l.cur][w.cur].x1,
		t[l.cur][w.cur].y1)
	
	self.cursor = Cursor:new {
		x_pos = cx+cw,
		y_pos = cy,
		h = ch,
		line_width_factor = 4,
	}
	self.cursor:draw()
	fb:refresh(1)

	-- first use cursor to place start pos for highlight
	while running do
		local ev = input.saveWaitForEvent()
		ev.code = adjustKeyEvents(ev)
		if ev.type == EV_KEY and ev.value == EVENT_VALUE_KEY_PRESS then
			if ev.code == KEY_FW_LEFT and not is_meet_start then
				is_meet_end = false
				l.new, w.new, is_meet_start = _prevGap(t, l.cur, w.cur)

				self.cursor:clear()
				if w.new ~= 0
				and not self:_isEntireLineInScreenHeightRange(t[l.new])
				and self:_isEntireWordInScreenWidthRange(t[l.new][w.new]) then
					-- word is in previous view
					local pageno = self:prevView()
					self:goto(pageno)
				end

				-- update cursor
				if w.new == 0 then
					-- meet line left end, must be handled as special case
					if self:_isEntireWordInScreenRange(t[l.new][1]) then
						self:drawCursorBeforeWord(t, l.new, 1)
					end
				else
					if self:_isEntireWordInScreenRange(t[l.new][w.new]) then
						self:drawCursorAfterWord(t, l.new, w.new)
					end
				end
			elseif ev.code == KEY_FW_RIGHT and not is_meet_end then
				is_meet_start = false
				l.new, w.new, is_meet_end = _nextGap(t, l.cur, w.cur)

				self.cursor:clear()
				-- we want to check whether the word is in screen range,
				-- so trun gap into word
				local tmp_w = w.new
				if tmp_w == 0 then
					tmp_w = 1
				end
				if not self:_isEntireLineInScreenHeightRange(t[l.new]) 
				and self:_isEntireWordInScreenWidthRange(t[l.new][tmp_w]) then
					local pageno = self:nextView()
					self:goto(pageno)
				end

				if w.new == 0 then
					-- meet line left end, must be handled as special case
					if self:_isEntireWordInScreenRange(t[l.new][1]) then
						self:drawCursorBeforeWord(t, l.new, 1)
					end
				else
					if self:_isEntireWordInScreenRange(t[l.new][w.new]) then
						self:drawCursorAfterWord(t, l.new, w.new)
					end
				end
			elseif ev.code == KEY_FW_UP and not is_meet_start then
				is_meet_end = false
				l.new, w.new, is_meet_start = _gapInPrevLine(t, l.cur, w.cur)

				self.cursor:clear()

				local tmp_w = w.new
				if tmp_w == 0 then
					tmp_w = 1
				end
				if not self:_isEntireLineInScreenHeightRange(t[l.new]) 
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
			elseif ev.code == KEY_FW_DOWN and not is_meet_end then
				is_meet_start = false
				l.new, w.new, is_meet_end = _gapInNextLine(t, l.cur, w.cur)

				self.cursor:clear()

				local tmp_w = w.new
				if w.cur == 0 then
					tmp_w = 1
				end
				if not self:_isEntireLineInScreenHeightRange(t[l.new]) 
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
						end -- for line_item
					end -- for text_item
				end -- if not highlight table
				if #self.highlight[self.pageno] == 0 then
					self.highlight[self.pageno] = nil
				end
				return
			elseif ev.code == KEY_FW_PRESS then
				l.new, w.new = l.cur, w.cur
				l.start, w.start = l.cur, w.cur
				running = false
				self.cursor:clear()
			elseif ev.code == KEY_BACK then
				running = false
				return
			end -- if check key event
			l.cur, w.cur = l.new, w.new
			fb:refresh(1)
		end
	end -- while running
	--print("start", l.cur, w.cur, l.start, w.start)

	-- two helper functions for highlight
	local function _togglePrevWordHighLight(t, l, w)
		if w.cur == 0 then
			if l.cur == 1 then
				-- already at the begin of first line, nothing to toggle
				return l, w, true
			else
				w.cur = 1
			end
		end
		l.new, w.new = _prevWord(t, l.cur, w.cur)

		if l.cur == 1 and w.cur == 1 then
			is_meet_start = true
			-- left end of first line must be handled as special case
			w.new = 0
		end

		if w.new ~= 0 and 
		not self:_isEntireLineInScreenHeightRange(t[l.new]) then
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

		if not self:_isEntireLineInScreenHeightRange(t[l.new]) then
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
		local ev = input.saveWaitForEvent()
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
				end -- if not is_meet_end
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
				end -- not is_meet_start
			elseif ev.code == KEY_FW_DOWN then
				is_meet_start = false
				if not is_meet_end then
					-- handle left end of first line as special case
					if w.cur == 0 then
						tmp_w = 1
					else
						tmp_w = w.cur
					end
					tmp_l, tmp_w = _wordInNextLine(t, l.cur, tmp_w)
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
			end -- if key event
			fb:refresh(1)
		end
	end -- EOF while
end


----------------------------------------------------
-- Renderer memory
----------------------------------------------------

function UniReader:getCacheSize()
	return -1
end

function UniReader:cleanCache()
	return
end

----------------------------------------------------
-- Setting related methods
----------------------------------------------------

-- load special settings for specific reader
function UniReader:loadSpecialSettings()
	return
end

-- save special settings for specific reader
function UniReader:saveSpecialSettings()
end



--[ following are default methods ]--

function UniReader:initGlobalSettings(settings)
	local pan_margin = settings:readSetting("pan_margin")
	if pan_margin then
		self.pan_margin = pan_margin
	end

	local pan_overlap_vertical = settings:readSetting("pan_overlap_vertical")
	if pan_overlap_vertical then
		self.pan_overlap_vertical = pan_overlap_vertical
	end

	local cache_max_memsize = settings:readSetting("cache_max_memsize")
	if cache_max_memsize then
		self.cache_max_memsize = cache_max_memsize
	end

	local cache_max_ttl = settings:readSetting("cache_max_ttl")
	if cache_max_ttl then
		self.cache_max_ttl = cache_max_ttl
	end

	local rcountmax = settings:readSetting("partial_refresh_count")
	if rcountmax then
		self.rcountmax = rcountmax
	end
end

-- This is a low-level method that can be shared with all readers.
function UniReader:loadSettings(filename)
	if self.doc ~= nil then
		self.settings = DocSettings:open(filename,self.cache_document_size)

		local gamma = self.settings:readSetting("gamma")
		if gamma then
			self.globalgamma = gamma
		end

		local jumpstack = self.settings:readSetting("jumpstack")
		self.jump_stack = jumpstack or {}

		local highlight = self.settings:readSetting("highlight")
		self.highlight = highlight or {}

		local bbox = self.settings:readSetting("bbox")
		print("# bbox loaded "..dump(bbox))
		self.bbox = bbox

		self.globalzoom = self.settings:readSetting("globalzoom") or 1.0
		self.globalzoommode = self.settings:readSetting("globalzoommode") or -1

		self:loadSpecialSettings()
		return true
	end
	return false
end

function UniReader:getLastPageOrPos()
	return self.settings:readSetting("last_page") or 1
end

function UniReader:saveLastPageOrPos()
	self.settings:savesetting("last_page", self.pageno)
end

-- guarantee that we have enough memory in cache
function UniReader:cacheClaim(size)
	if(size > self.cache_max_memsize) then
		-- we're not allowed to claim this much at all
		error("too much memory claimed")
		return false
	end
	while self.cache_current_memsize + size > self.cache_max_memsize do
		-- repeat this until we have enough free memory
		for k, _ in pairs(self.cache) do
			if self.cache[k].ttl > 0 then
				-- reduce ttl
				self.cache[k].ttl = self.cache[k].ttl - 1
			else
				-- cache slot is at end of life, so kick it out
				self.cache_current_memsize = self.cache_current_memsize - self.cache[k].size
				self.cache[k].bb:free()
				self.cache[k] = nil
			end
		end
	end
	self.cache_current_memsize = self.cache_current_memsize + size
	return true
end

function UniReader:drawOrCache(no, preCache)
	-- our general caching strategy is as follows:
	-- #1 goal: we must render the needed area.
	-- #2 goal: we render as much of the requested page as we can
	-- #3 goal: we render the full page
	-- #4 goal: we render next page, too. (TODO)

	-- ideally, this should be factored out and only be called when needed (TODO)
	local ok, page = pcall(self.doc.openPage, self.doc, no)
	local width, height = G_width, G_height
	if not ok then
		-- TODO: error handling
		return nil
	end
	local dc = self:setzoom(page, preCache)

	-- offset_x_in_page & offset_y_in_page is the offset within zoomed page
	-- they are always positive.
	-- you can see self.offset_x_& self.offset_y as the offset within
	-- draw space, which includes the page. So it can be negative and positive.
	local offset_x_in_page = -self.offset_x
	local offset_y_in_page = -self.offset_y
	if offset_x_in_page < 0 then offset_x_in_page = 0 end
	if offset_y_in_page < 0 then offset_y_in_page = 0 end

	-- check if we have relevant cache contents
	local pagehash = no..'_'..self.globalzoom..'_'..self.globalrotate..'_'..self.globalgamma
	if self.cache[pagehash] ~= nil then
		-- we have something in cache, check if it contains the requested part
		if self.cache[pagehash].x <= offset_x_in_page
			and self.cache[pagehash].y <= offset_y_in_page
			and ( self.cache[pagehash].x + self.cache[pagehash].w >= offset_x_in_page + width
				or self.cache[pagehash].w >= self.fullwidth - 1)
			and ( self.cache[pagehash].y + self.cache[pagehash].h >= offset_y_in_page + height
				or self.cache[pagehash].h >= self.fullheight - 1)
		then
			-- requested part is within cached tile
			-- ...so properly clean page
			page:close()
			-- ...and give it more time to live (ttl), except if we're precaching
			if not preCache then
				self.cache[pagehash].ttl = self.cache_max_ttl
			end
			-- ...and return blitbuffer plus offset into it
			return pagehash,
				offset_x_in_page - self.cache[pagehash].x,
				offset_y_in_page - self.cache[pagehash].y
		end
	end
	-- okay, we do not have it in cache yet.
	-- so render now.
	-- start off with the requested area
	local tile = { x = offset_x_in_page, y = offset_y_in_page,
					w = width, h = height }
	-- can we cache the full page?
	local max_cache = self.cache_max_memsize
	if preCache then
		max_cache = max_cache - self.cache[self.pagehash].size
	end
	if (self.fullwidth * self.fullheight / 2) <= max_cache then
		-- yes we can, so do this with offset 0, 0
		tile.x = 0
		tile.y = 0
		tile.w = self.fullwidth
		tile.h = self.fullheight
	elseif (tile.w*tile.h / 2) < max_cache then
		-- no, we can't. so generate a tile as big as we can go
		-- grow area in steps of 10px
		while ((tile.w+10) * (tile.h+10) / 2) < max_cache do
			if tile.x > 0 then
				tile.x = tile.x - 5
				tile.w = tile.w + 5
			end
			if tile.x + tile.w < self.fullwidth then
				tile.w = tile.w + 5
			end
			if tile.y > 0 then
				tile.y = tile.y - 5
				tile.h = tile.h + 5
			end
			if tile.y + tile.h < self.fullheight then
				tile.h = tile.h + 5
			end
		end
	else
		if not preCache then
			print("E: not enough memory in cache left, probably a bug.")
		end
		return nil
	end
	self:cacheClaim(tile.w * tile.h / 2);
	self.cache[pagehash] = {
		x = tile.x,
		y = tile.y,
		w = tile.w,
		h = tile.h,
		ttl = self.cache_max_ttl,
		size = tile.w * tile.h / 2,
		bb = Blitbuffer.new(tile.w, tile.h)
	}
	--print ("# new biltbuffer:"..dump(self.cache[pagehash]))
	dc:setOffset(-tile.x, -tile.y)
	print("# rendering: page="..no)
	page:draw(dc, self.cache[pagehash].bb, 0, 0)
	page:close()

	-- return hash and offset within blitbuffer
	return pagehash,
		offset_x_in_page - tile.x,
		offset_y_in_page - tile.y
end

-- blank the cache
function UniReader:clearCache()
	for k, _ in pairs(self.cache) do
		self.cache[k].bb:free()
	end
	self.cache = {}
	self.cache_current_memsize = 0
end

-- set viewer state according to zoom state
function UniReader:setzoom(page, preCache)
	local dc = DrawContext.new()
	local pwidth, pheight = page:getSize(self.nulldc)
	local width, height = G_width, G_height
	print("# page::getSize "..pwidth.."*"..pheight);
	local x0, y0, x1, y1 = page:getUsedBBox()
	if x0 == 0.01 and y0 == 0.01 and x1 == -0.01 and y1 == -0.01 then
		x0 = 0
		y0 = 0
		x1 = pwidth
		y1 = pheight
	end
	if x1 == 0 then x1 = pwidth end
	if y1 == 0 then y1 = pheight end
	-- clamp to page BBox
	if x0 < 0 then x0 = 0 end
	if x1 > pwidth then x1 = pwidth end
	if y0 < 0 then y0 = 0 end
	if y1 > pheight then y1 = pheight end

	if self.bbox.enabled then
		print("# ORIGINAL page::getUsedBBox "..x0.."*"..y0.." "..x1.."*"..y1);
		local bbox = self.bbox[self.pageno] -- exact

		local oddEven = self:oddEven(self.pageno)
		if bbox ~= nil then
			print("## bbox from "..self.pageno)
		else
			bbox = self.bbox[oddEven] -- odd/even
		end
		if bbox ~= nil then -- last used up to this page
			print("## bbox from "..oddEven)
		else
			for i = 0,self.pageno do
				bbox = self.bbox[ self.pageno - i ]
				if bbox ~= nil then
					print("## bbox from "..self.pageno - i)
					break
				end
			end
		end
		if bbox ~= nil then
			x0 = bbox["x0"]
			y0 = bbox["y0"]
			x1 = bbox["x1"]
			y1 = bbox["y1"]
		end
	end

	print("# page::getUsedBBox "..x0.."*"..y0.." "..x1.."*"..y1);

	if self.globalzoommode == self.ZOOM_FIT_TO_PAGE
	or self.globalzoommode == self.ZOOM_FIT_TO_CONTENT then
		self.globalzoom = width / pwidth
		self.offset_x = 0
		self.offset_y = (height - (self.globalzoom * pheight)) / 2
		if height / pheight < self.globalzoom then
			self.globalzoom = height / pheight
			self.offset_x = (width - (self.globalzoom * pwidth)) / 2
			self.offset_y = 0
		end
		self.pan_by_page = false
	elseif self.globalzoommode == self.ZOOM_FIT_TO_PAGE_WIDTH
	or self.globalzoommode == self.ZOOM_FIT_TO_CONTENT_WIDTH then
		self.globalzoom = width / pwidth
		self.offset_x = 0
		self.offset_y = (height - (self.globalzoom * pheight)) / 2
		self.pan_by_page = false
	elseif self.globalzoommode == self.ZOOM_FIT_TO_PAGE_HEIGHT
	or self.globalzoommode == self.ZOOM_FIT_TO_CONTENT_HEIGHT then
		self.globalzoom = height / pheight
		self.offset_x = (width - (self.globalzoom * pwidth)) / 2
		self.offset_y = 0
		self.pan_by_page = false
	end

	if self.globalzoommode == self.ZOOM_FIT_TO_CONTENT then
		if (x1 - x0) < pwidth then
			self.globalzoom = width / (x1 - x0)
			if height / (y1 - y0) < self.globalzoom then
				self.globalzoom = height / (y1 - y0)
			end
		end
		self.offset_x = -1 * x0 * self.globalzoom
		self.offset_y = -1 * y0 * self.globalzoom
	elseif self.globalzoommode == self.ZOOM_FIT_TO_CONTENT_WIDTH then
		if (x1 - x0) < pwidth then
			self.globalzoom = width / (x1 - x0)
		end
		self.offset_x = -1 * x0 * self.globalzoom
		self.offset_y = -1 * y0 * self.globalzoom
		self.content_top = self.offset_y
		-- enable pan mode in ZOOM_FIT_TO_CONTENT_WIDTH
		self.globalzoommode = self.ZOOM_FIT_TO_CONTENT_WIDTH_PAN
	elseif self.globalzoommode == self.ZOOM_FIT_TO_CONTENT_WIDTH_PAN then
		if self.content_top == -2012 then
			-- We must handle previous page turn as a special cases,
			-- because we want to arrive at the bottom of previous page.
			-- Since this a real page turn, we need to recalculate stuff.
			if (x1 - x0) < pwidth then
				self.globalzoom = width / (x1 - x0)
			end
			self.offset_x = -1 * x0 * self.globalzoom
			self.content_top = -1 * y0 * self.globalzoom
			self.offset_y = fb.bb:getHeight() - self.fullheight
		end
	elseif self.globalzoommode == self.ZOOM_FIT_TO_CONTENT_HEIGHT then
		if (y1 - y0) < pheight then
			self.globalzoom = height / (y1 - y0)
		end
		self.offset_x = -1 * x0 * self.globalzoom
		self.offset_y = -1 * y0 * self.globalzoom
	elseif self.globalzoommode == self.ZOOM_FIT_TO_CONTENT_HALF_WIDTH
		or self.globalzoommode == self.ZOOM_FIT_TO_CONTENT_HALF_WIDTH_MARGIN then
		local margin = self.pan_margin
		if self.globalzoommode == self.ZOOM_FIT_TO_CONTENT_HALF_WIDTH then margin = 0 end
		local pg_margin = 0 -- margin scaled to page size
		if margin > 0 then pg_margin = margin * 2 / self.globalzoom end
		self.globalzoom = width / (x1 - x0 + pg_margin)
		self.offset_x = -1 * x0 * self.globalzoom * 2 + margin
		self.globalzoom = height / (y1 - y0 + pg_margin)
		self.offset_y = -1 * y0 * self.globalzoom * 2 + margin
		self.globalzoom = width / (x1 - x0 + pg_margin) * 2
		print("column mode offset:"..self.offset_x.."*"..self.offset_y.." zoom:"..self.globalzoom);
		self.globalzoommode = self.ZOOM_BY_VALUE -- enable pan mode
		self.pan_x = self.offset_x
		self.pan_y = self.offset_y
		self.pan_by_page = true
	end

	dc:setZoom(self.globalzoom)
	self.globalzoom_orig = self.globalzoom

	dc:setRotate(self.globalrotate);
	self.fullwidth, self.fullheight = page:getSize(dc)
	if not preCache then -- save current page fullsize
		self.cur_full_width = self.fullwidth
		self.cur_full_height = self.fullheight
	end
	self.min_offset_x = fb.bb:getWidth() - self.fullwidth
	self.min_offset_y = fb.bb:getHeight() - self.fullheight
	if(self.min_offset_x > 0) then
		self.min_offset_x = 0
	end
	if(self.min_offset_y > 0) then
		self.min_offset_y = 0
	end

	print("# Reader:setZoom globalzoom:"..self.globalzoom.." globalrotate:"..self.globalrotate.." offset:"..self.offset_x.."*"..self.offset_y.." pagesize:"..self.fullwidth.."*"..self.fullheight.." min_offset:"..self.min_offset_x.."*"..self.min_offset_y)

	-- set gamma here, we don't have any other good place for this right now:
	if self.globalgamma ~= self.GAMMA_NO_GAMMA then
		print("gamma correction: "..self.globalgamma)
		dc:setGamma(self.globalgamma)
	end
	return dc
end

-- render and blit a page
function UniReader:show(no)
	local pagehash, offset_x, offset_y = self:drawOrCache(no)
	local width, height = G_width, G_height

	if not pagehash then
		return
	end
	self.pagehash = pagehash
	local bb = self.cache[pagehash].bb
	self.dest_x = 0
	self.dest_y = 0
	if bb:getWidth() - offset_x < width then
		-- we can't fill the whole output width, center the content
		self.dest_x = (width - (bb:getWidth() - offset_x)) / 2
	end
	if bb:getHeight() - offset_y < height and
	self.globalzoommode ~= self.ZOOM_FIT_TO_CONTENT_WIDTH_PAN then
		-- we can't fill the whole output height and not in
		-- ZOOM_FIT_TO_CONTENT_WIDTH_PAN mode, center the content
		self.dest_y = (height - (bb:getHeight() - offset_y)) / 2
	elseif self.globalzoommode == self.ZOOM_FIT_TO_CONTENT_WIDTH_PAN and
	self.offset_y > 0 then
		-- if we are in ZOOM_FIT_TO_CONTENT_WIDTH_PAN mode and turning to
		-- the top of the page, we might leave an empty space between the
		-- page top and screen top.
		self.dest_y = self.offset_y
	end
	if self.dest_x or self.dest_y then
		fb.bb:paintRect(0, 0, width, height, 8)
	end
	print("# blitFrom dest_off:("..self.dest_x..", "..self.dest_y..
		"), src_off:("..offset_x..", "..offset_y.."), "..
		"width:"..width..", height:"..height)
	fb.bb:blitFrom(bb, self.dest_x, self.dest_y, offset_x, offset_y, width, height)

	print("## self.show_overlap "..self.show_overlap)
	if self.show_overlap < 0 then
		fb.bb:dimRect(0,0, width, self.dest_y - self.show_overlap)
	elseif self.show_overlap > 0 then
		fb.bb:dimRect(0,self.dest_y + height - self.show_overlap, width, self.show_overlap)
	end
	self.show_overlap = 0

	-- render highlights to page
	if self.highlight[no] then
		self:toggleTextHighLight(self.highlight[no])
	end

	if self.rcount >= self.rcountmax then
		print("full refresh")
		self.rcount = 1
		fb:refresh(0)
	else
		print("partial refresh")
		self.rcount = self.rcount + 1
		fb:refresh(1)
	end
	self.slot_visible = slot;
end

function UniReader:isSamePage(p1, p2)
	return p1 == p2
end

--[[
	@ pageno is the page you want to add to jump_stack
	  NOTE: for CREReader, pageno refers to xpointer
--]]
function UniReader:addJump(pageno, notes)
	local jump_item = nil
	local notes_to_add = notes
	if not notes_to_add then
		-- no notes given, auto generate from Toc entry
		notes_to_add = self:getTocTitleOfCurrentPage()
		if notes_to_add ~= "" then
			notes_to_add = "in "..notes_to_add
		end
	end
	-- move pageno page to jump_stack top if already in
	for _t,_v in ipairs(self.jump_stack) do
		if self:isSamePage(_v.page, pageno) then
			jump_item = _v
			table.remove(self.jump_stack, _t)
			-- if original notes is not empty, probably defined by users,
			-- we use the original notes to overwrite auto generated notes
			-- from Toc entry
			if jump_item.notes ~= "" then
				notes_to_add = jump_item.notes
			end
			jump_item.notes = notes or notes_to_add
			break
		end
	end
	-- create a new one if page not found in stack
	if not jump_item then
		jump_item = {
			page = pageno,
			datetime = os.date("%Y-%m-%d %H:%M:%S"),
			notes = notes_to_add,
		}
	end

	-- insert item at the start
	table.insert(self.jump_stack, 1, jump_item)

	if #self.jump_stack > 10 then
		-- remove the last element to keep the size less than 10
		table.remove(self.jump_stack)
	end
end

function UniReader:delJump(pageno)
	for _t,_v in ipairs(self.jump_stack) do
		if _v.page == pageno then
			table.remove(self.jump_stack, _t)
		end
	end
end

-- change current page and cache next page after rendering
function UniReader:goto(no)
	if no < 1 or no > self.doc:getPages() then
		return
	end

	-- for jump_stack, distinguish jump from normal page turn
	if self.pageno and math.abs(self.pageno - no) > 1 then
		self:addJump(self.pageno)
	end

	self.pageno = no
	self:show(no)

	-- TODO: move the following to a more appropriate place
	-- into the caching section
	if no < self.doc:getPages() then
		if #self.bbox == 0 or not self.bbox.enabled then
			-- pre-cache next page, but if we will modify bbox don't!
			self:drawOrCache(no+1, true)
		end
	end
end

function UniReader:redrawCurrentPage()
	self:goto(self.pageno)
end

function UniReader:nextView()
	local pageno = self.pageno

	if self.globalzoommode == self.ZOOM_FIT_TO_CONTENT_WIDTH_PAN then
		if self.offset_y <= self.min_offset_y then
			-- hit content bottom, turn to next page
			self.globalzoommode = self.ZOOM_FIT_TO_CONTENT_WIDTH
			pageno = pageno + 1
		else
			-- goto next view of current page
			self.offset_y = self.offset_y - G_height
							+ self.pan_overlap_vertical
			self.show_overlap = -self.pan_overlap_vertical -- top < 0
		end
	else
		-- not in fit to content width pan mode, just do a page turn
		pageno = pageno + 1
		if self.pan_by_page then
			-- we are in two column mode
			self.offset_x = self.pan_x
			self.offset_y = self.pan_y
		end
	end

	return pageno
end

function UniReader:prevView()
	local pageno = self.pageno

	if self.globalzoommode == self.ZOOM_FIT_TO_CONTENT_WIDTH_PAN then
		if self.offset_y >= self.content_top then
			-- hit content top, turn to previous page
			-- set self.content_top with magic num to signal self:setZoom
			self.content_top = -2012
			pageno = pageno - 1
		else
			-- goto previous view of current page
			self.offset_y = self.offset_y + G_height
							- self.pan_overlap_vertical
			self.show_overlap = self.pan_overlap_vertical -- bottom > 0
		end
	else
		-- not in fit to content width pan mode, just do a page turn
		pageno = pageno - 1
		if self.pan_by_page then
			-- we are in two column mode
			self.offset_x = self.pan_x
			self.offset_y = self.pan_y
		end
	end

	return pageno
end

-- adjust global gamma setting
function UniReader:modifyGamma(factor)
	print("modifyGamma, gamma="..self.globalgamma.." factor="..factor)
	self.globalgamma = self.globalgamma * factor;
	self:redrawCurrentPage()
end

-- adjust zoom state and trigger re-rendering
function UniReader:setGlobalZoomMode(newzoommode)
	if self.globalzoommode ~= newzoommode then
		self.globalzoommode = newzoommode
		self:redrawCurrentPage()
	end
end

-- adjust zoom state and trigger re-rendering
function UniReader:setGlobalZoom(zoom)
	if self.globalzoom ~= zoom then
		self.globalzoommode = self.ZOOM_BY_VALUE
		self.globalzoom = zoom
		self:redrawCurrentPage()
	end
end

function UniReader:setRotate(rotate)
	self.globalrotate = rotate
	self:redrawCurrentPage()
end

-- @ orien: 1 for clockwise rotate, -1 for anti-clockwise
function UniReader:screenRotate(orien)
	Screen:screenRotate(orien)
	-- update global width and height variable
	G_width, G_height = fb:getSize()
	self:clearCache()
end

function UniReader:cleanUpTocTitle(title)
	return title:gsub("\13", "")
end

function UniReader:fillToc()
	self.toc = self.doc:getToc()
end

function UniReader:getTocTitleByPage(pageno)
	if not self.toc then
		-- build toc when needed.
		self:fillToc()
	end

	-- no table of content
	if #self.toc == 0 then
		return ""
	end

	local pre_entry = self.toc[1]
	for _k,_v in ipairs(self.toc) do
		if _v.page > pageno then
			break
		end
		pre_entry = _v
	end
	return self:cleanUpTocTitle(pre_entry.title)
end

function UniReader:getTocTitleOfCurrentPage()
	return self:getTocTitleByPage(self.pageno)
end

function UniReader:gotoTocEntry(entry)
	self:goto(entry.page)
end

function UniReader:showToc()
	if not self.toc then
		-- build toc if needed.
		self:fillToc()
	end

	-- build menu items
	local menu_items = {}
	for k,v in ipairs(self.toc) do
		table.insert(menu_items,
		("        "):rep(v.depth-1)..self:cleanUpTocTitle(v.title))
	end

	if #menu_items == 0 then
		showInfoMsgWithDelay(
			"This document does not have a TOC.", 2000, 1)
	else
		toc_menu = SelectMenu:new{
			menu_title = "Table of Contents",
			item_array = menu_items,
		}
		item_no = toc_menu:choose(0, fb.bb:getHeight())

		if item_no then
			self:gotoTocEntry(self.toc[item_no])
		else
			self:redrawCurrentPage()
		end
	end
end

function UniReader:showJumpStack()
	local menu_items = {}
	for k,v in ipairs(self.jump_stack) do
		table.insert(menu_items,
			v.datetime.." -> Page "..v.page.." "..v.notes)
	end

	if #menu_items == 0 then
		showInfoMsgWithDelay(
			"No jump history found.", 2000, 1)
	else
		jump_menu = SelectMenu:new{
			menu_title = "Jump Keeper      (current page: "..self.pageno..")",
			item_array = menu_items,
		}
		item_no = jump_menu:choose(0, fb.bb:getHeight())
		if item_no then
			local jump_item = self.jump_stack[item_no]
			self:goto(jump_item.page)
		else
			self:redrawCurrentPage()
		end
	end
end

function UniReader:showHighLight()
	local menu_items = {}
	local highlight_dict = {}
	-- build menu items
	for k,v in pairs(self.highlight) do
		if type(k) == "number" then
			for k1,v1 in ipairs(v) do
				table.insert(menu_items, v1.text)
				table.insert(highlight_dict, {page=k, start=v1[1]})
			end
		end
	end
	if #menu_items == 0 then
		showInfoMsgWithDelay(
			"No HighLights found.", 2000, 1)
	else
		toc_menu = SelectMenu:new{
			menu_title = "HighLights",
			item_array = menu_items,
		}
		item_no = toc_menu:choose(0, fb.bb:getHeight())
		if item_no then
			self:goto(highlight_dict[item_no].page)
		else
			self:redrawCurrentPage()
		end
	end
end

-- used in UniReader:showMenu()
function UniReader:_drawReadingInfo()
	local width, height = G_width, G_height
	local load_percent = (self.pageno / self.doc:getPages())
	local face = Font:getFace("cfont", 22)

	-- display memory on top of page
	fb.bb:paintRect(0, 0, width, 15+6*2, 0)
	renderUtf8Text(fb.bb, 10, 15+6, face,
		"Memory: "..
		math.ceil( self.cache_current_memsize / 1024 ).."/"..math.ceil( self.cache_max_memsize / 1024 )..
		" "..math.ceil( self.doc:getCacheSize() / 1024 ).."/"..math.ceil( self.cache_document_size / 1024 ).." k",
	true)

	-- display reading progress on bottom of page
	local ypos = height - 50
	fb.bb:paintRect(0, ypos, width, 50, 0)
	ypos = ypos + 15
	local cur_section = self:getTocTitleOfCurrentPage()
	if cur_section ~= "" then
		cur_section = "Section: "..cur_section
	end
	renderUtf8Text(fb.bb, 10, ypos+6, face,
		"Page: "..self.pageno.."/"..self.doc:getPages()..
		"    "..cur_section, true)

	ypos = ypos + 15
	blitbuffer.progressBar(fb.bb, 10, ypos, width-20, 15,
							5, 4, load_percent, 8)
end

function UniReader:showMenu()
	self:_drawReadingInfo()

	fb:refresh(1)
	while 1 do
		local ev = input.saveWaitForEvent()
		ev.code = adjustKeyEvents(ev)
		if ev.type == EV_KEY and ev.value == EVENT_VALUE_KEY_PRESS then
			if ev.code == KEY_BACK or ev.code == KEY_MENU then
				return
			elseif ev.code == KEY_C then
				self.doc:cleanCache()
			end
		end
	end
end

function UniReader:oddEven(number)
	print("## oddEven "..number)
	if number % 2 == 1 then
		return "odd"
	else
		return "even"
	end
end

-- wait for input and handle it
function UniReader:inputLoop()
	local keep_running = true
	while 1 do
		local ev = input.saveWaitForEvent()
		ev.code = adjustKeyEvents(ev)
		if ev.type == EV_KEY and ev.value == EVENT_VALUE_KEY_PRESS then
			local secs, usecs = util.gettime()
			keydef = Keydef:new(ev.code, getKeyModifier())
			print("key pressed: "..tostring(keydef))
			command = self.commands:getByKeydef(keydef)
			if command ~= nil then
				print("command to execute: "..tostring(command))
				ret_code = command.func(self,keydef)
				if ret_code == "break" then
					break;
				end
			else
				print("command not found: "..tostring(command))
			end

			local nsecs, nusecs = util.gettime()
			local dur = (nsecs - secs) * 1000000 + nusecs - usecs
			print("E: T="..ev.type.." V="..ev.value.." C="..ev.code.." DUR="..dur)
		end
	end

	-- do clean up stuff
	self:clearCache()
	self.toc = nil
	if self.doc ~= nil then
		self.doc:close()
	end
	if self.settings ~= nil then
		self:saveLastPageOrPos()
		self.settings:savesetting("gamma", self.globalgamma)
		self.settings:savesetting("jumpstack", self.jump_stack)
		self.settings:savesetting("bbox", self.bbox)
		self.settings:savesetting("globalzoom", self.globalzoom)
		self.settings:savesetting("globalzoommode", self.globalzoommode)
		self.settings:savesetting("highlight", self.highlight)
		self:saveSpecialSettings()
		self.settings:close()
	end

	return keep_running
end

-- command definitions
function UniReader:addAllCommands()
	self.commands = Commands:new()
	self.commands:addGroup("< >",{Keydef:new(KEY_PGBCK,nil),Keydef:new(KEY_PGFWD,nil)},
		"previous/next page",
		function(unireader,keydef)
			unireader:goto(keydef.keycode==KEY_PGBCK and unireader:prevView() or unireader:nextView())
		end)
	self.commands:addGroup(MOD_ALT.."< >",{Keydef:new(KEY_PGBCK,MOD_ALT),Keydef:new(KEY_PGFWD,MOD_ALT)},
		"zoom out/in 10%",
		function(unireader,keydef)
			unireader:setGlobalZoom(unireader.globalzoom + (keydef.keycode==KEY_PGBCK and -1 or 1)*unireader.globalzoom_orig*0.1)
		end)
	self.commands:addGroup(MOD_SHIFT.."< >",{Keydef:new(KEY_PGBCK,MOD_SHIFT),Keydef:new(KEY_PGFWD,MOD_ALTSHIFT)},
		"zoom out/in 20%",
		function(unireader,keydef)
			unireader:setGlobalZoom(unireader.globalzoom + (keydef.keycode==KEY_PGBCK and -1 or 1)*unireader.globalzoom_orig*0.2)
		end)
	self.commands:add(KEY_BACK,nil,"Back",
		"back to last jump",
		function(unireader)
			if #unireader.jump_stack ~= 0 then
				unireader:goto(unireader.jump_stack[1].page)
			end
		end)
	self.commands:add(KEY_BACK,MOD_ALT,"Back",
		"close document",
		function(unireader)
			return "break"
		end)
	self.commands:add(KEY_HOME,MOD_ALT,"Home",
		"exit application",
		function(unireader)
			keep_running = false
			return "break"
		end)
	self.commands:addGroup("vol-/+",{Keydef:new(KEY_VPLUS,nil),Keydef:new(KEY_VMINUS,nil)},
		"decrease/increase gamma 25%",
		function(unireader,keydef)
			unireader:modifyGamma(keydef.keycode==KEY_VPLUS and 1.25 or 0.8)
		end)
	--numeric key group
	local numeric_keydefs = {}
	for i=1,10 do numeric_keydefs[i]=Keydef:new(KEY_1+i-1,nil,tostring(i%10)) end
	self.commands:addGroup("[1, 2 .. 9, 0]",numeric_keydefs,
		"jump to 10%, 20% .. 90%, 100% of document",
		function(unireader,keydef)
			print('jump to page: '..math.max(math.floor(unireader.doc:getPages()*(keydef.keycode-KEY_1)/9),1)..'/'..unireader.doc:getPages())
			unireader:goto(math.max(math.floor(unireader.doc:getPages()*(keydef.keycode-KEY_1)/9),1))
		end)
	-- end numeric keys
	self.commands:add(KEY_A,nil,"A",
		"zoom to fit page",
		function(unireader)
			unireader:setGlobalZoomMode(unireader.ZOOM_FIT_TO_PAGE)
		end)
	self.commands:add(KEY_A,MOD_SHIFT,"A",
		"zoom to fit content",
		function(unireader)
			unireader:setGlobalZoomMode(unireader.ZOOM_FIT_TO_CONTENT)
		end)
	self.commands:add(KEY_S,nil,"S",
		"zoom to fit page width",
		function(unireader)
			unireader:setGlobalZoomMode(unireader.ZOOM_FIT_TO_PAGE_WIDTH)
		end)
	self.commands:add(KEY_S,MOD_SHIFT,"S",
		"zoom to fit content width",
		function(unireader)
			unireader:setGlobalZoomMode(unireader.ZOOM_FIT_TO_CONTENT_WIDTH)
		end)
	self.commands:add(KEY_D,nil,"D",
		"zoom to fit page height",
		function(unireader)
			unireader:setGlobalZoomMode(unireader.ZOOM_FIT_TO_PAGE_HEIGHT)
		end)
	self.commands:add(KEY_D,MOD_SHIFT,"D",
		"zoom to fit content height",
		function(unireader)
			unireader:setGlobalZoomMode(unireader.ZOOM_FIT_TO_CONTENT_HEIGHT)
		end)
	self.commands:add(KEY_F,nil,"F",
		"zoom to fit margin 2-column mode",
		function(unireader)
			unireader:setGlobalZoomMode(unireader.ZOOM_FIT_TO_CONTENT_HALF_WIDTH_MARGIN)
		end)
	self.commands:add(KEY_F,MOD_SHIFT,"F",
		"zoom to fit content 2-column mode",
		function(unireader)
			unireader:setGlobalZoomMode(unireader.ZOOM_FIT_TO_CONTENT_HALF_WIDTH)
		end)
	self.commands:add(KEY_G,nil,"G",
		"open 'go to page' input box",
		function(unireader)
			local page = NumInputBox:input(G_height-100, 100, "Page:")
			-- convert string to number
			if not pcall(function () page = page + 0 end) then
				page = unireader.pageno
			else
				if page < 1 or page > unireader.doc:getPages() then
					page = unireader.pageno
				end
			end
			unireader:goto(page)
		end)
	self.commands:add(KEY_H,nil,"H",
		"show help page",
		function(unireader)
			HelpPage:show(0, G_height, unireader.commands)
			unireader:redrawCurrentPage()
		end)
	self.commands:add(KEY_T,nil,"T",
		"show table of content",
		function(unireader)
			unireader:showToc()
		end)
	self.commands:add(KEY_B,nil,"B",
		"show jump stack",
		function(unireader)
			unireader:showJumpStack()
		end)
	self.commands:add(KEY_B,MOD_SHIFT,"B",
		"add jump",
		function(unireader)
			unireader:addJump(unireader.pageno)
		end)
	self.commands:add(KEY_J,MOD_SHIFT,"J",
		"rotate 10° clockwise",
		function(unireader)
			unireader:setRotate( unireader.globalrotate + 10 )
		end)
	self.commands:add(KEY_J,nil,"J",
		"rotate screen 90° clockwise",
		function(unireader)
			unireader:screenRotate("clockwise")
			if self.globalzoommode == self.ZOOM_FIT_TO_CONTENT_WIDTH_PAN then
				self:setGlobalZoomMode(self.ZOOM_FIT_TO_CONTENT_WIDTH)
			else
				self:redrawCurrentPage()
			end
		end)
	self.commands:add(KEY_K,MOD_SHIFT,"K",
		"rotate 10° counterclockwise",
		function(unireader)
			unireader:setRotate( unireader.globalrotate - 10 )
		end)
	self.commands:add(KEY_K,nil,"K",
		"rotate screen 90° counterclockwise",
		function(unireader)
			unireader:screenRotate("anticlockwise")
			if self.globalzoommode == self.ZOOM_FIT_TO_CONTENT_WIDTH_PAN then
				self:setGlobalZoomMode(self.ZOOM_FIT_TO_CONTENT_WIDTH)
			else
				self:redrawCurrentPage()
			end
		end)
	self.commands:add(KEY_R, MOD_SHIFT, "R",
		"manual full screen refresh",
		function(unireader)
			-- eink will not refresh if nothing is changeed on the screen
			-- so we fake a change here.
			fb.bb:invertRect(0, 0, 1, 1)
			fb:refresh(1)
			fb.bb:invertRect(0, 0, 1, 1)
			fb:refresh(0)
			unireader.rcount = 1
		end)
	self.commands:add(KEY_Z,nil,"Z",
		"set crop mode",
		function(unireader)
			local bbox = {}
			bbox["x0"] = - unireader.offset_x / unireader.globalzoom
			bbox["y0"] = - unireader.offset_y / unireader.globalzoom
			bbox["x1"] = bbox["x0"] + G_width / unireader.globalzoom
			bbox["y1"] = bbox["y0"] + G_height / unireader.globalzoom
			bbox.pan_x = unireader.pan_x
			bbox.pan_y = unireader.pan_y
			unireader.bbox[unireader.pageno] = bbox
			unireader.bbox[unireader:oddEven(unireader.pageno)] = bbox
			unireader.bbox.enabled = true
			print("# bbox " .. unireader.pageno .. dump(unireader.bbox))
			unireader.globalzoommode = unireader.ZOOM_FIT_TO_CONTENT -- use bbox
		end)
	self.commands:add(KEY_Z,MOD_SHIFT,"Z",
		"reset crop",
		function(unireader)
			unireader.bbox[unireader.pageno] = nil;
			print("# bbox remove "..unireader.pageno .. dump(unireader.bbox));
		end)
	self.commands:add(KEY_Z,MOD_ALT,"Z",
		"toggle crop mode",
		function(unireader)
			unireader.bbox.enabled = not unireader.bbox.enabled;
			print("# bbox override: ", unireader.bbox.enabled);
		end)
	self.commands:add(KEY_MENU,nil,"Menu",
		"toggle info box",
		function(unireader)
			unireader:showMenu()
			unireader:redrawCurrentPage()
		end)
	-- panning
	local panning_keys = {Keydef:new(KEY_FW_LEFT,MOD_ANY),Keydef:new(KEY_FW_RIGHT,MOD_ANY),Keydef:new(KEY_FW_UP,MOD_ANY),Keydef:new(KEY_FW_DOWN,MOD_ANY),Keydef:new(KEY_FW_PRESS,MOD_ANY)}
	self.commands:addGroup("[joypad]",panning_keys,
		"pan the active view; use Shift or Alt for smaller steps",
		function(unireader,keydef)
			if keydef.keycode ~= KEY_FW_PRESS then
				unireader.globalzoommode = unireader.ZOOM_BY_VALUE
			end
			if unireader.globalzoommode == unireader.ZOOM_BY_VALUE then
				local x
				local y
				if keydef.modifier==MOD_SHIFT then -- shift always moves in small steps
					x = unireader.shift_x / 2
					y = unireader.shift_y / 2
				elseif keydef.modifier==MOD_ALT then
					x = unireader.shift_x / 5
					y = unireader.shift_y / 5
				elseif unireader.pan_by_page then
					x = G_width
					y = G_height - unireader.pan_overlap_vertical -- overlap for lines which didn't fit
				else
					x = unireader.shift_x
					y = unireader.shift_y
				end

				print("offset "..unireader.offset_x.."*"..unireader.offset_x.." shift "..x.."*"..y.." globalzoom="..unireader.globalzoom)
				local old_offset_x = unireader.offset_x
				local old_offset_y = unireader.offset_y

				if keydef.keycode == KEY_FW_LEFT then
					print("# KEY_FW_LEFT "..unireader.offset_x.." + "..x.." > 0");
					unireader.offset_x = unireader.offset_x + x
					if unireader.pan_by_page then
						if unireader.offset_x > 0 and unireader.pageno > 1 then
							unireader.offset_x = unireader.pan_x
							unireader.offset_y = unireader.min_offset_y -- bottom
							unireader:goto(unireader.pageno - 1)
						else
							unireader.show_overlap = 0
							unireader.offset_y = unireader.min_offset_y
						end
					elseif unireader.offset_x > 0 then
						unireader.offset_x = 0
					end
				elseif keydef.keycode == KEY_FW_RIGHT then
					print("# KEY_FW_RIGHT "..unireader.offset_x.." - "..x.." < "..unireader.min_offset_x.." - "..unireader.pan_margin);
					unireader.offset_x = unireader.offset_x - x
					if unireader.pan_by_page then
						if unireader.offset_x < unireader.min_offset_x - unireader.pan_margin and unireader.pageno < unireader.doc:getPages() then
							unireader.offset_x = unireader.pan_x
							unireader.offset_y = unireader.pan_y
							unireader:goto(unireader.pageno + 1)
						else
							unireader.show_overlap = 0
							unireader.offset_y = unireader.pan_y
						end
					elseif unireader.offset_x < unireader.min_offset_x then
						unireader.offset_x = unireader.min_offset_x
					end
				elseif keydef.keycode == KEY_FW_UP then
					unireader.offset_y = unireader.offset_y + y
					if unireader.offset_y > 0 then
						if unireader.pan_by_page then
							unireader.show_overlap = unireader.offset_y + unireader.pan_overlap_vertical
						end
						unireader.offset_y = 0
					elseif unireader.pan_by_page then
						unireader.show_overlap = unireader.pan_overlap_vertical -- bottom
					end
				elseif keydef.keycode == KEY_FW_DOWN then
					unireader.offset_y = unireader.offset_y - y
					if unireader.offset_y < unireader.min_offset_y then
						if unireader.pan_by_page then
							unireader.show_overlap = unireader.offset_y + y - unireader.min_offset_y - G_height
						end
						unireader.offset_y = unireader.min_offset_y
					elseif unireader.pan_by_page then
						unireader.show_overlap = -unireader.pan_overlap_vertical -- top
					end
				elseif keydef.keycode == KEY_FW_PRESS then
					if keydef.modifier==MOD_SHIFT then
						if unireader.pan_by_page then
							unireader.offset_x = unireader.pan_x
							unireader.offset_y = unireader.pan_y
						else
							unireader.offset_x = 0
							unireader.offset_y = 0
						end
					else
						unireader.pan_by_page = not unireader.pan_by_page
						if unireader.pan_by_page then
							unireader.pan_x = unireader.offset_x
							unireader.pan_y = unireader.offset_y
						end
					end
				end
				if old_offset_x ~= unireader.offset_x
				or old_offset_y ~= unireader.offset_y then
					unireader:redrawCurrentPage()
				end
			end
		end)
	-- end panning
	-- highlight mode
	self.commands:add(KEY_N, nil, "N",
		"start highlight mode",
		function(unireader)
			unireader:startHighLightMode()
			unireader:goto(unireader.pageno)
		end
	)
	self.commands:add(KEY_N, MOD_SHIFT, "N",
		"display all highlights",
		function(unireader)
			unireader:showHighLight()
			unireader:goto(unireader.pageno)
		end
	)
	-- commands.map is very large, impacts startup performance on device
	--print("## defined commands "..dump(self.commands.map))
end
