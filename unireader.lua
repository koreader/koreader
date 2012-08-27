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
	rcountmax = 0,

	-- zoom state:
	globalzoom = 1.0,
	globalzoom_orig = 1.0,
	globalzoom_mode = -1, -- ZOOM_FIT_TO_PAGE

	globalrotate = 0,

	-- gamma setting:
	globalgamma = 1.0,   -- GAMMA_NO_GAMMA

	-- cached tile size
	fullwidth = 0,
	fullheight = 0,
	-- size of current page for current zoom level in pixels
	cur_full_width = 0,
	cur_full_height = 0,
	cur_bbox = {}, -- current page bbox
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
	pan_margin = 5, -- horizontal margin for two-column zoom (in pixels)
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

	-- we use array to simluate two stacks,
	-- one for backwards, one for forwards
	jump_history = {cur = 1},
	bookmarks = {},
	highlight = {},
	toc = nil,

	bbox = {}, -- override getUsedBBox

	last_search = {}
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
	InfoMessage:show("Registering fonts...", 1)
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
	Debug("screenOffset", x, y)
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
-- Given coordinates on the screen return positioni
-- in original page
----------------------------------------------------
function UniReader:screenToPageTransform(x, y)
	local x_o,y_o = self:screenOffset()
	local x_p,y_p =
		( x - x_o ) / self.globalzoom,
		( y - y_o ) / self.globalzoom
	Debug("screenToPage", x,y, "offset", x_o,y_o, "page", x_p,y_p)
	return x_p, y_p
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

-- make sure at least part of the box can be seen in next/previous view
-- @FIXME only works in FIT_TO_CONTENT_WIDTH mode  21.04 2012 (houqp)
function UniReader:_isBoxInNextView(box)
	return box.y1 * self.globalzoom > -self.offset_y + G_height
end

function UniReader:_isBoxInPrevView(box)
	return box.y0 * self.globalzoom < -self.offset_y
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

function UniReader:_isWordInNextView(w)
	return self:_isBoxInNextView(w)
end

function UniReader:_isLineInNextView(l)
	return self:_isBoxInNextView(l)
end

function UniReader:_isLineInPrevView(l)
	return self:_isBoxInPrevView(l)
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
	Debug("_toggleTextHighLight range", l0, w0, l1, w1)
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
	self.cursor:draw(true)
end

function UniReader:drawCursorBeforeWord(t, l, w)
	-- get height of line t[l][w] is in
	local _, _, _, h = self:zoomedRectCoordTransform(0, t[l].y0, 0, t[l].y1)
	-- get rect of t[l][w]
	local x, y, _, _ = self:getRectInScreen(t[l][w].x0, t[l][w].y0, t[l][w].x1, t[l][w].y1)
	self.cursor:setHeight(h)
	self.cursor:moveTo(x, y)
	self.cursor:draw(true)
end

function UniReader:getText(pageno)
	-- define a sensible implementation when your reader supports it
	return nil
end

function UniReader:startHighLightMode()
	local t = self:getText(self.pageno)
	if not t or #t == 0 then
		showInfoMsgWithDelay("No text available for highlight", 2000, 1);
		return nil
	end

	local function _findFirstWordInView(t)
		for i=1, #t, 1 do
			if self:_isEntireWordInScreenRange(t[i][1]) then
				return i, 1
			end
		end

		showInfoMsgWithDelay("No visible text for highlight", 2000, 1);
		Debug("_findFirstWordInView none found in", t)

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
		Debug("no text in current view!")
		-- InfoMessage about reason already shown
		return
	end

	w.start = 0
	l.cur, w.cur = l.start, w.start
	l.new, w.new = l.cur, w.cur
	local is_meet_start = false
	local is_meet_end = false
	local running = true

	local cx, cy, cw, ch = self:getRectInScreen(
		t[l.cur][1].x0,
		t[l.cur][1].y0,
		t[l.cur][1].x1,
		t[l.cur][1].y1)
	
	self.cursor = Cursor:new {
		x_pos = cx,
		y_pos = cy,
		h = ch,
		line_width_factor = 4,
	}
	self.cursor:draw(true)

	-- first use cursor to place start pos for highlight
	while running do
		local ev = input.saveWaitForEvent()
		ev.code = adjustKeyEvents(ev)
		if ev.type == EV_KEY and ev.value ~= EVENT_VALUE_KEY_RELEASE then
			if ev.code == KEY_FW_LEFT and not is_meet_start then
				is_meet_end = false
				l.new, w.new, is_meet_start = _prevGap(t, l.cur, w.cur)

				self.cursor:clear(true)
				if w.new ~= 0
				and self:_isLineInPrevView(t[l.new])
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

				self.cursor:clear(true)
				-- we want to check whether the word is in screen range,
				-- so trun gap into word
				local tmp_w = w.new
				if tmp_w == 0 then
					tmp_w = 1
				end
				if self:_isLineInNextView(t[l.new]) 
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

				self.cursor:clear(true)

				local tmp_w = w.new
				if tmp_w == 0 then
					tmp_w = 1
				end
				if self:_isLineInPrevView(t[l.new]) 
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

				self.cursor:clear(true)

				local tmp_w = w.new
				if w.cur == 0 then
					tmp_w = 1
				end
				if self:_isLineInNextView(t[l.new]) 
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
				-- handle left end of line as special case
				if w.cur == 0 then
					w.cur = 1
				end
				if self.highlight[self.pageno] then
					for k, text_item in ipairs(self.highlight[self.pageno]) do
						for _, line_item in ipairs(text_item) do
							if t[l.cur][w.cur].y0 >= line_item.y0
							and t[l.cur][w.cur].y1 <= line_item.y1
							and t[l.cur][w.cur].x0 >= line_item.x0
							and t[l.cur][w.cur].x1 <= line_item.x1 then
								self.highlight[self.pageno][k] = nil
								-- remove page entry if empty
								if #self.highlight[self.pageno] == 0 then
									self.highlight[self.pageno] = nil
								end
								return
							end
						end -- for line_item
					end -- for text_item
				end -- if not highlight table
			elseif ev.code == KEY_FW_PRESS then
				l.new, w.new = l.cur, w.cur
				l.start, w.start = l.cur, w.cur
				running = false
				self.cursor:clear(true)
			elseif ev.code == KEY_BACK then
				running = false
				return
			end -- if check key event
			l.cur, w.cur = l.new, w.new
		end
	end -- while running
	Debug("start", l.cur, w.cur, l.start, w.start)

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
		self:_isLineInPrevView(t[l.new]) then
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

		if self:_isLineInNextView(t[l.new]) then
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
		if ev.type == EV_KEY and ev.value ~= EVENT_VALUE_KEY_RELEASE then
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

-- Method to load settings before document open
function UniReader:preLoadSettings(filename)
	self.settings = DocSettings:open(filename)

	local cache_d_size = self.settings:readSetting("cache_document_size")
	if cache_d_size then
		self.cache_document_size = cache_d_size
	end
end

-- This is a low-level method that can be shared with all readers.
function UniReader:loadSettings(filename)
	if self.doc ~= nil then
		local gamma = self.settings:readSetting("gamma")
		if gamma then
			self.globalgamma = gamma
		end

		local jump_history = self.settings:readSetting("jump_history")
		if jump_history then
			self.jump_history = jump_history
		else
			self.jump_history = {cur = 1}
		end

		local bookmarks = self.settings:readSetting("bookmarks")
		self.bookmarks = bookmarks or {}

		-- clear obselate jumpstack settings
		-- move jump_stack to bookmarks incase users used
		-- it as bookmark feature before.
		local jump_stack = self.settings:readSetting("jumpstack")
		if jump_stack then
			if #self.bookmarks == 0 then
				self.bookmarks = jump_stack
			end
			self.settings:delSetting("jumpstack")
		end

		local highlight = self.settings:readSetting("highlight")
		self.highlight = highlight or {}
		if self.highlight.to_fix ~= nil then
			for _,fix_item in ipairs(self.highlight.to_fix) do
				if fix_item == "djvu invert y axle" then
					InfoMessage:show("Updating HighLight data...", 1)
					for pageno,text_table in pairs(self.highlight) do
						if type(pageno) == "number" then
							text_table = self:invertTextYAxel(pageno, text_table)
						end
					end
				end
			end
			Debug(self.highlight)
			self.highlight.to_fix = nil
		end

		local bbox = self.settings:readSetting("bbox")
		Debug("bbox loaded ", bbox)
		self.bbox = bbox

		self.globalzoom = self.settings:readSetting("globalzoom") or 1.0
		self.globalzoom_mode = self.settings:readSetting("globalzoom_mode") or -1

		self:loadSpecialSettings()
		return true
	end
	return false
end

function UniReader:getLastPageOrPos()
	return self.settings:readSetting("last_page") or 1
end

function UniReader:saveLastPageOrPos()
	self.settings:saveSetting("last_page", self.pageno)
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
			Debug("ERROR not enough memory in cache left, probably a bug.")
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
	--debug ("# new biltbuffer:"..dump(self.cache[pagehash]))
	dc:setOffset(-tile.x, -tile.y)
	Debug("rendering page", no)
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
	Debug("page::getSize",pwidth,pheight)
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
		Debug("ORIGINAL page::getUsedBBox", x0,y0, x1,y1 )
		local bbox = self.bbox[self.pageno] -- exact

		local oddEven = self:oddEven(self.pageno)
		if bbox ~= nil then
			Debug("bbox from", self.pageno)
		else
			bbox = self.bbox[oddEven] -- odd/even
		end
		if bbox ~= nil then -- last used up to this page
			Debug("bbox from", oddEven)
		else
			for i = 0,self.pageno do
				bbox = self.bbox[ self.pageno - i ]
				if bbox ~= nil then
					Debug("bbox from", self.pageno - i)
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

	Debug("page::getUsedBBox", x0, y0, x1, y1 )

	if self.globalzoom_mode == self.ZOOM_FIT_TO_PAGE
	or self.globalzoom_mode == self.ZOOM_FIT_TO_CONTENT then
		self.globalzoom = width / pwidth
		self.offset_x = 0
		self.offset_y = (height - (self.globalzoom * pheight)) / 2
		if height / pheight < self.globalzoom then
			self.globalzoom = height / pheight
			self.offset_x = (width - (self.globalzoom * pwidth)) / 2
			self.offset_y = 0
		end
		self.pan_by_page = false
	elseif self.globalzoom_mode == self.ZOOM_FIT_TO_PAGE_WIDTH
	or self.globalzoom_mode == self.ZOOM_FIT_TO_CONTENT_WIDTH then
		self.globalzoom = width / pwidth
		self.offset_x = 0
		self.offset_y = (height - (self.globalzoom * pheight)) / 2
		self.pan_by_page = false
	elseif self.globalzoom_mode == self.ZOOM_FIT_TO_PAGE_HEIGHT
	or self.globalzoom_mode == self.ZOOM_FIT_TO_CONTENT_HEIGHT then
		self.globalzoom = height / pheight
		self.offset_x = (width - (self.globalzoom * pwidth)) / 2
		self.offset_y = 0
		self.pan_by_page = false
	end

	if self.globalzoom_mode == self.ZOOM_FIT_TO_CONTENT then
		if (x1 - x0) < pwidth then
			self.globalzoom = width / (x1 - x0)
			if height / (y1 - y0) < self.globalzoom then
				self.globalzoom = height / (y1 - y0)
			end
		end
		self.offset_x = -1 * x0 * self.globalzoom
		self.offset_y = -1 * y0 * self.globalzoom
	elseif self.globalzoom_mode == self.ZOOM_FIT_TO_CONTENT_WIDTH then
		if (x1 - x0) < pwidth then
			self.globalzoom = width / (x1 - x0)
		end
		self.offset_x = -1 * x0 * self.globalzoom
		self.offset_y = -1 * y0 * self.globalzoom
		self.content_top = self.offset_y
		-- enable pan mode in ZOOM_FIT_TO_CONTENT_WIDTH
		self.globalzoom_mode = self.ZOOM_FIT_TO_CONTENT_WIDTH_PAN
	elseif self.globalzoom_mode == self.ZOOM_FIT_TO_CONTENT_WIDTH_PAN then
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
	elseif self.globalzoom_mode == self.ZOOM_FIT_TO_CONTENT_HEIGHT then
		if (y1 - y0) < pheight then
			self.globalzoom = height / (y1 - y0)
		end
		self.offset_x = -1 * x0 * self.globalzoom
		self.offset_y = -1 * y0 * self.globalzoom
	elseif self.globalzoom_mode == self.ZOOM_FIT_TO_CONTENT_HALF_WIDTH
		or self.globalzoom_mode == self.ZOOM_FIT_TO_CONTENT_HALF_WIDTH_MARGIN then
		local margin = self.pan_margin
		if self.globalzoom_mode == self.ZOOM_FIT_TO_CONTENT_HALF_WIDTH then margin = 0 end
		self.globalzoom = width / (x1 - x0 + margin)
		self.offset_x = -1 * x0 * self.globalzoom * 2 + margin
		self.globalzoom = height / (y1 - y0 + margin)
		self.offset_y = -1 * y0 * self.globalzoom * 2 + margin
		self.globalzoom = width / (x1 - x0 + margin) * 2
		Debug("column mode offset:", self.offset_x, self.offset_y, " zoom:", self.globalzoom);
		self.globalzoom_mode = self.ZOOM_BY_VALUE -- enable pan mode
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

		self.cur_bbox = {
			["x0"] = x0,
			["y0"] = y0,
			["x1"] = x1,
			["y1"] = y1,
		}
		Debug("cur_bbox", self.cur_bbox)

	end
	self.min_offset_x = fb.bb:getWidth() - self.fullwidth
	self.min_offset_y = fb.bb:getHeight() - self.fullheight
	if(self.min_offset_x > 0) then
		self.min_offset_x = 0
	end
	if(self.min_offset_y > 0) then
		self.min_offset_y = 0
	end

	Debug("Reader:setZoom globalzoom:", self.globalzoom, " globalrotate:", self.globalrotate, " offset:", self.offset_x, self.offset_y, " pagesize:", self.fullwidth, self.fullheight, " min_offset:", self.min_offset_x, self.min_offset_y)

	-- set gamma here, we don't have any other good place for this right now:
	if self.globalgamma ~= self.GAMMA_NO_GAMMA then
		Debug("gamma correction: ", self.globalgamma)
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
	self.globalzoom_mode ~= self.ZOOM_FIT_TO_CONTENT_WIDTH_PAN then
		-- we can't fill the whole output height and not in
		-- ZOOM_FIT_TO_CONTENT_WIDTH_PAN mode, center the content
		self.dest_y = (height - (bb:getHeight() - offset_y)) / 2
	elseif self.globalzoom_mode == self.ZOOM_FIT_TO_CONTENT_WIDTH_PAN and
	self.offset_y > 0 then
		-- if we are in ZOOM_FIT_TO_CONTENT_WIDTH_PAN mode and turning to
		-- the top of the page, we might leave an empty space between the
		-- page top and screen top.
		self.dest_y = self.offset_y
	end
	if self.dest_x or self.dest_y then
		fb.bb:paintRect(0, 0, width, height, 8)
	end
	Debug("blitFrom dest_off:", self.dest_x, self.dest_y, 
		"src_off:", offset_x, offset_y,
		"width:", width, "height:", height)
	fb.bb:blitFrom(bb, self.dest_x, self.dest_y, offset_x, offset_y, width, height)

	Debug("self.show_overlap", self.show_overlap)
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
		Debug("full refresh")
		self.rcount = 0
		fb:refresh(0)
	else
		Debug("partial refresh")
		self.rcount = self.rcount + 1
		fb:refresh(1)
	end
	self.slot_visible = slot;
end

function UniReader:isSamePage(p1, p2)
	return p1 == p2
end

--[[
	@ pageno is the page you want to add to jump_history, this will
	  clear the forward stack since pageno is the new head.
	  NOTE: for CREReader, pageno refers to xpointer
--]]
function UniReader:addJump(pageno)
	-- build notes from TOC
	local notes = self:getTocTitleByPage(pageno)
	if notes ~= "" then
		notes = "in "..notes
	end
	-- create a head
	jump_item = {
		page = pageno,
		datetime = os.date("%Y-%m-%d %H:%M:%S"),
		notes = notes,
	}
	-- clear forward stack if it is not empty
	if self.jump_history.cur < #self.jump_history then
		for i=self.jump_history.cur+1, #self.jump_history do
			self.jump_history[i] = nil
		end
	end
	-- keep the size less than 10
	if #self.jump_history > 10 then
		table.remove(self.jump_history)
	end
	-- set up new head
	-- if backward stack top is the same as page to record, remove it
	if #self.jump_history ~= 0 and
	self:isSamePage(self.jump_history[#self.jump_history].page, pageno) then
		self.jump_history[#self.jump_history] = nil
	end
	table.insert(self.jump_history, jump_item)
	self.jump_history.cur = #self.jump_history + 1
	return true
end

function UniReader:delJump(pageno)
	for _t,_v in ipairs(self.jump_history) do
		if _v.page == pageno then
			table.remove(self.jump_history, _t)
		end
	end
end

function UniReader:isBookmarkInSequence(a, b)
	return a.page < b.page
end

-- return nil if page already marked
-- otherwise, return true
function UniReader:addBookmark(pageno)
	for k,v in ipairs(self.bookmarks) do
		if v.page == pageno then
			return nil
		end
	end
	-- build notes from TOC
	local notes = self:getTocTitleByPage(pageno)
	if notes ~= "" then
		notes = "in "..notes
	end
	mark_item = {
		page = pageno,
		datetime = os.date("%Y-%m-%d %H:%M:%S"),
		notes = notes,
	}
	table.insert(self.bookmarks, mark_item)
	table.sort(self.bookmarks, function(a,b)
		return self:isBookmarkInSequence(a, b)
	end)
	return true
end

-- change current page and cache next page after rendering
function UniReader:goto(no, is_ignore_jump)
	if no < 1 or no > self.doc:getPages() then
		return
	end

	-- for jump_history
	if not is_ignore_jump then
		-- distinguish jump from normal page turn
		if self.pageno and math.abs(self.pageno - no) > 1 then
			self:addJump(self.pageno)
		end
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

	if self.globalzoom_mode == self.ZOOM_FIT_TO_CONTENT_WIDTH_PAN then
		if self.offset_y <= self.min_offset_y then
			-- hit content bottom, turn to next page
			self.globalzoom_mode = self.ZOOM_FIT_TO_CONTENT_WIDTH
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

	if self.globalzoom_mode == self.ZOOM_FIT_TO_CONTENT_WIDTH_PAN then
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
	Debug("modifyGamma, gamma=", self.globalgamma, " factor=", factor)
	self.globalgamma = self.globalgamma * factor;
	self:redrawCurrentPage()
end

-- adjust zoom state and trigger re-rendering
function UniReader:setglobalzoom_mode(newzoommode)
	if self.globalzoom_mode ~= newzoommode then
		self.globalzoom_mode = newzoommode
		self:redrawCurrentPage()
	end
end

-- adjust zoom state and trigger re-rendering
function UniReader:setGlobalZoom(zoom)
	if self.globalzoom ~= zoom then
		self.globalzoom_mode = self.ZOOM_BY_VALUE
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

-- getTocTitleByPage wrapper, so specific reader
-- can tranform pageno according its need
function UniReader:getTocTitleByPage(pageno)
	return self:_getTocTitleByPage(pageno)
end

function UniReader:_getTocTitleByPage(pageno)
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

function UniReader:showJumpHist()
	local menu_items = {}
	for k,v in ipairs(self.jump_history) do
		if k == self.jump_history.cur then
			cur_sign = "*(Cur) "
		else
			cur_sign = ""
		end
		table.insert(menu_items,
			cur_sign..v.datetime.." -> Page "..v.page.." "..v.notes)
	end

	if #menu_items == 0 then
		showInfoMsgWithDelay("No jump history found.", 2000, 1)
	else
		-- if cur points to head, draw entry for current page
		if self.jump_history.cur > #self.jump_history then
			table.insert(menu_items,
				"Current Page "..self.pageno)
		end

		jump_menu = SelectMenu:new{
			menu_title = "Jump History",
			item_array = menu_items,
		}
		item_no = jump_menu:choose(0, fb.bb:getHeight())
		if item_no and item_no <= #self.jump_history then
			local jump_item = self.jump_history[item_no]
			self.jump_history.cur = item_no
			self:goto(jump_item.page, true)
			-- set new head if we reached the top of backward stack
			if self.jump_history.cur == #self.jump_history then
				self.jump_history.cur = self.jump_history.cur + 1
			end
		else
			self:redrawCurrentPage()
		end
	end
end

function UniReader:showBookMarks()
	local menu_items = {}
	-- build menu items
	for k,v in ipairs(self.bookmarks) do
		table.insert(menu_items,
			"Page "..v.page.." "..v.notes.." @ "..v.datetime)
	end
	if #menu_items == 0 then
		showInfoMsgWithDelay(
			"No bookmark found.", 2000, 1)
	else
		toc_menu = SelectMenu:new{
			menu_title = "Bookmarks",
			item_array = menu_items,
		}
		item_no = toc_menu:choose(0, fb.bb:getHeight())
		if item_no then
			self:goto(self.bookmarks[item_no].page)
		else
			self:redrawCurrentPage()
		end
	end
end

function UniReader:nextBookMarkedPage()
	for k,v in ipairs(self.bookmarks) do
		if self.pageno < v.page then
			return v
		end
	end
	return nil
end

function UniReader:prevBookMarkedPage()
	local pre_item = nil
	for k,v in ipairs(self.bookmarks) do
		if self.pageno <= v.page then
			if not pre_item then
				break
			elseif pre_item.page < self.pageno then
				return pre_item
			end
		end
		pre_item = v
	end
	return pre_item
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


function UniReader:searchHighLight(search)

	search = string.lower(search) -- case in-sensitive

	local old_highlight = self.highlight
	self.highlight = {} -- FIXME show only search results?

	local pageno = self.pageno -- start search at current page
	local max_pageno = self.doc:getPages()
	local found = 0

	if self.last_search then
		Debug("self.last_search",self.last_search)
		if self.last_search.pageno == self.pageno
		and self.last_search.search == search
		then
			pageno = pageno + 1
			Debug("continue search for ", search)
		end
	end

	while found == 0 do

		local t = self:getText(pageno)

		if t ~= nil and #t > 0 then

			Debug("self:getText", pageno, #t)

			for i = 1, #t, 1 do
				for j = 1, #t[i], 1 do
					local e = t[i][j]
					if e.word ~= nil then
						if string.match( string.lower(e.word), search ) then

							if not self.highlight[pageno] then
								self.highlight[pageno] = {}
							end

							local hl_item = {
								text = e.word,
								[1] = {
									x0 = e.x0,
									y0 = e.y0,
									x1 = e.x1,
									y1 = e.y1,
								}
							}

							table.insert(self.highlight[pageno], hl_item)
							found = found + 1
						end
					end
				end
			end

		else
			Debug("self:getText", pageno, 'empty')
		end

		if found > 0 then
			Debug("self.highlight", self.highlight);
			self.pageno = pageno
		else
			pageno = math.mod( pageno + 1, max_pageno + 1 )
			Debug("next page", pageno, max_pageno)
			if pageno == self.pageno then -- wrap around, stop
				found = -1
			end
		end

	end

	self:goto(self.pageno) -- show highlights, remove input
	if found > 0 then
		showInfoMsgWithDelay( found.." hits '"..search.."' page "..self.pageno, 2000, 1)
		self.last_search = {
			pageno = self.pageno,
			search = search,
			hits = found,
		}
	else
		showInfoMsgWithDelay( "'"..search.."' not found in document", 2000, 1)
	end

	self.highlight = old_highlight -- will not remove search highlights until page refresh

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
	Debug("oddEven", number)
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
		if ev.type == EV_KEY and ev.value ~= EVENT_VALUE_KEY_RELEASE then
			local secs, usecs = util.gettime()
			keydef = Keydef:new(ev.code, getKeyModifier())
			Debug("key pressed:", tostring(keydef))
			command = self.commands:getByKeydef(keydef)
			if command ~= nil then
				Debug("command to execute:", tostring(command))
				ret_code = command.func(self,keydef)
				if ret_code == "break" then
					break;
				end
			else
				Debug("command not found:", tostring(command))
			end

			local nsecs, nusecs = util.gettime()
			local dur = (nsecs - secs) * 1000000 + nusecs - usecs
			Debug("E: T="..ev.type, " V="..ev.value, " C="..ev.code, " DUR=", dur)

			if ev.value == EVENT_VALUE_KEY_REPEAT then
				self.rcount = 0
				Debug("prevent full screen refresh", self.rcount)
			end
		else
			Debug("ignored ev ",ev)
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
		self.settings:saveSetting("gamma", self.globalgamma)
		self.settings:saveSetting("jump_history", self.jump_history)
		self.settings:saveSetting("bookmarks", self.bookmarks)
		self.settings:saveSetting("bbox", self.bbox)
		self.settings:saveSetting("globalzoom", self.globalzoom)
		self.settings:saveSetting("globalzoom_mode", self.globalzoom_mode)
		self.settings:saveSetting("highlight", self.highlight)
		self:saveSpecialSettings()
		self.settings:close()
	end

	return keep_running
end

-- command definitions
function UniReader:addAllCommands()
	self.commands = Commands:new()
	self.commands:addGroup("< >",{
		Keydef:new(KEY_PGBCK,nil),Keydef:new(KEY_LPGBCK,nil),
		Keydef:new(KEY_PGFWD,nil),Keydef:new(KEY_LPGFWD,nil)},
		"previous/next page",
		function(unireader,keydef)
			unireader:goto(
			(keydef.keycode == KEY_PGBCK or keydef.keycode == KEY_LPGBCK)
			and unireader:prevView() or unireader:nextView())
		end)
	self.commands:addGroup(MOD_ALT.."< >",{
		Keydef:new(KEY_PGBCK,MOD_ALT),Keydef:new(KEY_PGFWD,MOD_ALT),
		Keydef:new(KEY_LPGBCK,MOD_ALT),Keydef:new(KEY_LPGFWD,MOD_ALT)},
		"zoom out/in 10%",
		function(unireader,keydef)
			is_zoom_out = (keydef.keycode == KEY_PGBCK or keydef.keycode == KEY_LPGBCK)
			unireader:setGlobalZoom(unireader.globalzoom_orig
				+ (is_zoom_out and -1 or 1)*unireader.globalzoom_orig*0.1)
		end)
	self.commands:addGroup(MOD_SHIFT.."< >",{
		Keydef:new(KEY_PGBCK,MOD_SHIFT),Keydef:new(KEY_PGFWD,MOD_SHIFT),
		Keydef:new(KEY_LPGBCK,MOD_SHIFT),Keydef:new(KEY_LPGFWD,MOD_SHIFT)},
		"zoom out/in 20%",
		function(unireader,keydef)
			is_zoom_out = (keydef.keycode == KEY_PGBCK or keydef.keycode == KEY_LPGBCK)
			unireader:setGlobalZoom(unireader.globalzoom_orig
			   + ( is_zoom_out and -1 or 1)*unireader.globalzoom_orig*0.2)
		end)
	self.commands:add(KEY_BACK,nil,"Back",
		"go backward in jump history",
		function(unireader)
			local prev_jump_no = 0
			if unireader.jump_history.cur > #unireader.jump_history then
				-- if cur points to head, put current page in history
				unireader:addJump(self.pageno)
				prev_jump_no = unireader.jump_history.cur - 2
			else
				prev_jump_no = unireader.jump_history.cur - 1
			end

			if prev_jump_no >= 1 then
				unireader.jump_history.cur = prev_jump_no
				unireader:goto(unireader.jump_history[prev_jump_no].page, true)
			else
				showInfoMsgWithDelay("Already first jump!", 2000, 1)
			end
		end)
	self.commands:add(KEY_BACK,MOD_SHIFT,"Back",
		"go forward in jump history",
		function(unireader)
			local next_jump_no = unireader.jump_history.cur + 1
			if next_jump_no <= #self.jump_history then
				unireader.jump_history.cur = next_jump_no
				unireader:goto(unireader.jump_history[next_jump_no].page, true)
				-- set new head if we reached the top of backward stack
				if unireader.jump_history.cur == #unireader.jump_history then
					unireader.jump_history.cur = unireader.jump_history.cur + 1
				end
			else
				showInfoMsgWithDelay("Already last jump!", 2000, 1)
			end
		end)
	self.commands:add(KEY_BACK,MOD_ALT,"Back",
		"close document",
		function(unireader)
			return "break"
		end)
	self.commands:add(KEY_HOME,nil,"Home",
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
			Debug('jump to page:', math.max(math.floor(unireader.doc:getPages()*(keydef.keycode-KEY_1)/9),1), '/', unireader.doc:getPages())
			unireader:goto(math.max(math.floor(unireader.doc:getPages()*(keydef.keycode-KEY_1)/9),1))
		end)
	-- end numeric keys
	self.commands:add(KEY_A,nil,"A",
		"zoom to fit page",
		function(unireader)
			unireader:setglobalzoom_mode(unireader.ZOOM_FIT_TO_PAGE)
		end)
	self.commands:add(KEY_A,MOD_SHIFT,"A",
		"zoom to fit content",
		function(unireader)
			unireader:setglobalzoom_mode(unireader.ZOOM_FIT_TO_CONTENT)
		end)
	self.commands:add(KEY_S,nil,"S",
		"zoom to fit page width",
		function(unireader)
			unireader:setglobalzoom_mode(unireader.ZOOM_FIT_TO_PAGE_WIDTH)
		end)
	self.commands:add(KEY_S,MOD_SHIFT,"S",
		"zoom to fit content width",
		function(unireader)
			unireader:setglobalzoom_mode(unireader.ZOOM_FIT_TO_CONTENT_WIDTH)
		end)
	self.commands:add(KEY_D,nil,"D",
		"zoom to fit page height",
		function(unireader)
			unireader:setglobalzoom_mode(unireader.ZOOM_FIT_TO_PAGE_HEIGHT)
		end)
	self.commands:add(KEY_D,MOD_SHIFT,"D",
		"zoom to fit content height",
		function(unireader)
			unireader:setglobalzoom_mode(unireader.ZOOM_FIT_TO_CONTENT_HEIGHT)
		end)
	self.commands:add(KEY_F,nil,"F",
		"zoom to fit margin 2-column mode",
		function(unireader)
			unireader:setglobalzoom_mode(unireader.ZOOM_FIT_TO_CONTENT_HALF_WIDTH_MARGIN)
		end)
	self.commands:add(KEY_F,MOD_SHIFT,"F",
		"zoom to fit content 2-column mode",
		function(unireader)
			unireader:setglobalzoom_mode(unireader.ZOOM_FIT_TO_CONTENT_HALF_WIDTH)
		end)
	self.commands:add(KEY_G,nil,"G",
		"open 'go to page' input box",
		function(unireader)
			local page = NumInputBox:input(G_height-100, 100,
				"Page:", "current page "..self.pageno, true)
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
		"show bookmarks",
		function(unireader)
			unireader:showBookMarks()
		end)
	self.commands:add(KEY_B,MOD_ALT,"B",
		"add bookmark to current page",
		function(unireader)
			ok = unireader:addBookmark(self.pageno)
			if not ok then
				showInfoMsgWithDelay("Page already marked!", 2000, 1)
			else
				showInfoMsgWithDelay("Page marked.", 2000, 1)
			end
		end)
	self.commands:add(KEY_B,MOD_SHIFT,"B",
		"show jump history",
		function(unireader)
			unireader:showJumpHist()
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
			if self.globalzoom_mode == self.ZOOM_FIT_TO_CONTENT_WIDTH_PAN then
				self:setglobalzoom_mode(self.ZOOM_FIT_TO_CONTENT_WIDTH)
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
			if self.globalzoom_mode == self.ZOOM_FIT_TO_CONTENT_WIDTH_PAN then
				self:setglobalzoom_mode(self.ZOOM_FIT_TO_CONTENT_WIDTH)
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
			unireader.rcount = 0
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
			Debug("bbox", unireader.pageno, unireader.bbox)
			unireader.globalzoom_mode = unireader.ZOOM_FIT_TO_CONTENT -- use bbox
			showInfoMsgWithDelay("Manual crop setting saved.", 2000, 1)
		end)
	self.commands:add(KEY_Z,MOD_SHIFT,"Z",
		"reset crop",
		function(unireader)
			unireader.bbox[unireader.pageno] = nil;
			showInfoMsgWithDelay("Manual crop setting removed.", 2000, 1)
			Debug("bbox remove", unireader.pageno, unireader.bbox);
		end)
	self.commands:add(KEY_Z,MOD_ALT,"Z",
		"toggle crop mode",
		function(unireader)
			unireader.bbox.enabled = not unireader.bbox.enabled;
			if unireader.bbox.enabled then
				showInfoMsgWithDelay("Manual crop enabled.", 2000, 1)
			else
				showInfoMsgWithDelay("Manual crop disabled.", 2000, 1)
			end
			Debug("bbox override", unireader.bbox.enabled);
		end)
	self.commands:add(KEY_X,nil,"X",
		"invert page bbox",
		function(unireader)
			local bbox = unireader.cur_bbox
			Debug("bbox", bbox)
			x,y,w,h = unireader:getRectInScreen( bbox["x0"], bbox["y0"], bbox["x1"], bbox["y1"] )
			Debug("inxertRect",x,y,w,h)
			fb.bb:invertRect( x,y, w,h )
			fb:refresh(1)
		end)
	self.commands:add(KEY_X,MOD_SHIFT,"X",
		"modify page bbox",
		function(unireader)
			local bbox = unireader.cur_bbox
			Debug("bbox", bbox)
			x,y,w,h = unireader:getRectInScreen( bbox["x0"], bbox["y0"], bbox["x1"], bbox["y1"] )
			Debug("getRectInScreen",x,y,w,h)

			local new_bbox = bbox
			local x_s, y_s = x,y
			local running_corner = "top-left"

			Screen:saveCurrentBB()

			fb.bb:invertRect( 0,y_s, G_width,1 )
			fb.bb:invertRect( x_s,0, 1,G_height )
			InfoMessage:show(running_corner.." bbox");
			fb:refresh(1)

			local last_direction = { x = 0, y = 0 }

			while running_corner do
				local ev = input.saveWaitForEvent()
				Debug("ev",ev)
				ev.code = adjustKeyEvents(ev)

				if ev.type == EV_KEY and ev.value ~= EVENT_VALUE_KEY_RELEASE then

					fb.bb:invertRect( 0,y_s, G_width,1 )
					fb.bb:invertRect( x_s,0, 1,G_height )

					local step   = 10
					local factor = 1

					local x_direction, y_direction = 0,0
					if ev.code == KEY_FW_LEFT then
						x_direction = -1
					elseif ev.code == KEY_FW_RIGHT then
						x_direction =  1
					elseif ev.code == KEY_FW_UP then
						y_direction = -1
					elseif ev.code == KEY_FW_DOWN then
						y_direction =  1
					elseif ev.code == KEY_FW_PRESS then
						local p_x,p_y = unireader:screenToPageTransform(x_s,y_s)
						if running_corner == "top-left" then
							new_bbox["x0"] = p_x
							new_bbox["y0"] = p_y
							Debug("change top-left", bbox, "to", new_bbox)
							running_corner = "bottom-right"
							Screen:restoreFromSavedBB()
							InfoMessage:show(running_corner.." bbox")
							fb:refresh(1)
							x_s = x+w
							y_s = y+h
						else
							new_bbox["x1"] = p_x
							new_bbox["y1"] = p_y
							running_corner = false
						end
					elseif ev.code >= KEY_Q and ev.code <= KEY_P then
						factor = ev.code - KEY_Q + 1
						x_direction = last_direction["x"]
						y_direction = last_direction["y"]
						Debug("factor",factor,"deltas",x_direction,y_direction)
					elseif ev.code >= KEY_A and ev.code <= KEY_L then
						factor = ev.code - KEY_A + 11
						x_direction = last_direction["x"]
						y_direction = last_direction["y"]
					elseif ev.code >= KEY_Z and ev.code <= KEY_M then
						factor = ev.code - KEY_Z + 20
						x_direction = last_direction["x"]
						y_direction = last_direction["y"]
					elseif ev.code == KEY_BACK or ev.code == KEY_HOME then
						running_corner = false
					end

					Debug("factor",factor,"deltas",x_direction,y_direction)

					if running_corner then
						local x_o = x_direction * step * factor
						local y_o = y_direction * step * factor
						Debug("move slider",x_o,y_o)
						if x_s+x_o >= 0 and x_s+x_o <= G_width  then x_s = x_s + x_o end
						if y_s+y_o >= 0 and y_s+y_o <= G_height then y_s = y_s + y_o end

						if x_direction ~= 0 or y_direction ~= 0 then
							Screen:restoreFromSavedBB()
						end

						fb.bb:invertRect( 0,y_s, G_width,1 )
						fb.bb:invertRect( x_s,0, 1,G_height )

						if x_direction or y_direction then
							last_direction = { x = x_direction, y = y_direction }
							Debug("last_direction",last_direction)

							-- FIXME partial duplicate of SelectMenu.item_shortcuts
							local keys = {
								"Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P",
								"A", "S", "D", "F", "G", "H", "J", "K", "L",
								"Z", "X", "C", "V", "B", "N", "M",
							}

							local max = 0
							if x_direction == 1 then
								max = G_width - x_s
							elseif x_direction == -1 then
								max = x_s
							elseif y_direction == 1 then
								max = G_height - y_s
							elseif y_direction == -1 then
								max = y_s
							else
								print("ERROR: unknown direction!")
							end

							max = max / step
							if max > #keys then max = #keys end

							local face = Font:getFace("hpkfont", 11)

							for i = 1, max, 1 do
								local key = keys[i]
								local tick = i * step * x_direction
								if x_direction ~= 0 then
									local tick = i * step * x_direction
									Debug("x tick",i,tick,key)
									if running_corner == "top-left" then -- ticks must be inside page
										fb.bb:invertRect(     x_s+tick, y_s, 1, math.abs(tick))
									else
										fb.bb:invertRect(     x_s+tick, y_s-math.abs(tick), 1, math.abs(tick))
									end
									if x_direction < 0 then tick = tick - step end
									tick = tick - step * x_direction / 2
									renderUtf8Text(fb.bb, x_s+tick+2, y_s+4, face, key)
								else
									local tick = i * step * y_direction
									Debug("y tick",i,tick,key)
									if running_corner == "top-left" then -- ticks must be inside page
										fb.bb:invertRect(     x_s, y_s+tick, math.abs(tick),1)
									else
										fb.bb:invertRect(     x_s-math.abs(tick), y_s+tick, math.abs(tick),1)
									end
									if y_direction > 0 then tick = tick + step end
									tick = tick - step * y_direction / 2
									renderUtf8Text(fb.bb, x_s-3, y_s+tick-1, face, key)
								end
							end
						end

						fb:refresh(1)
					end
				end

			end

			unireader.bbox[unireader.pageno] = new_bbox
			unireader.bbox[unireader:oddEven(unireader.pageno)] = new_bbox
			unireader.bbox.enabled = true
			Debug("crop bbox", bbox, "to", new_bbox)

			Screen:restoreFromSavedBB()
			x,y,w,h = unireader:getRectInScreen( new_bbox["x0"], new_bbox["y0"], new_bbox["x1"], new_bbox["y1"] )
			fb.bb:invertRect( x,y, w,h )
			--fb.bb:invertRect( x+1,y+1, w-2,h-2 ) -- just border?
			showInfoMsgWithDelay("new page bbox", 2000, 1);
			self:redrawCurrentPage()

			self.rcount = self.rcountmax -- force next full refresh

			--unireader:setglobalzoom_mode(unireader.ZOOM_FIT_TO_CONTENT)
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
				unireader.globalzoom_mode = unireader.ZOOM_BY_VALUE
			end
			if unireader.globalzoom_mode == unireader.ZOOM_BY_VALUE then
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

				Debug("offset", unireader.offset_x, unireader.offset_x, " shift", x, y, " globalzoom", unireader.globalzoom)
				local old_offset_x = unireader.offset_x
				local old_offset_y = unireader.offset_y

				if keydef.keycode == KEY_FW_LEFT then
					Debug("KEY_FW_LEFT", unireader.offset_x, "+", x, "> 0");
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
					Debug("KEY_FW_RIGHT", unireader.offset_x, "-", x, "<", unireader.min_offset_x, "-", unireader.pan_margin);
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
	self.commands:add(KEY_DOT, nil, ".",
		"search and highlight text",
		function(unireader)
			local search = InputBox:input(G_height - 100, 100,
				"Search:", self.last_search.search )

			if search ~= nil and string.len( search ) > 0 then
				unireader:searchHighLight(search)
			end
		end
	)
	self.commands:add(KEY_P, MOD_SHIFT, "P",
	"make screenshot",
	function(unireader)
		Screen:screenshot()
	end 
	)
	-- commands.map is very large, impacts startup performance on device
	--Debug("defined commands "..dump(self.commands.map))
end
