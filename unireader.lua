require "keys"
require "settings"
require "selectmenu"
require "commands"
require "helppage"
require "dialog"
require "defaults"

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
	rcount = DRCOUNT,
	-- default to full refresh on every page turn
	rcountmax = DRCOUNTMAX,

	-- zoom state:
	globalzoom = DGLOBALZOOM,
	globalzoom_orig = DGLOBALZOOM_ORIG,
	globalzoom_mode = DGLOBALZOOM_MODE, -- ZOOM_FIT_TO_PAGE

	globalrotate = DGLOBALROTATE,

	-- gamma setting:
	globalgamma = DGLOBALGAMMA,   -- GAMMA_NO_GAMMA

	-- DjVu page rendering mode (used in djvu.c:drawPage())
	-- See comments in djvureader.lua:DJVUReader:select_render_mode()
	render_mode = DRENDER_MODE, -- COLOUR

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
	shift_x = DSHIFT_X,
	shift_y = DSHIFT_Y,
	-- step to change zoom manually, default = 16%
	step_manual_zoom = DSTEP_MANUAL_ZOOM,
	pan_by_page = DPAN_BY_PAGE, -- using shift_[xy] or width/height
	pan_x = DPAN_X, -- top-left offset of page when pan activated
	pan_y = DPAN_Y,
	pan_x1 = 0, -- bottom-right offset of page when pan activated
	pan_y1 = 0,
	pan_margin = DPAN_MARGIN, -- horizontal margin for two-column zoom (in pixels)
	pan_overlap_vertical = DPAN_OVERLAP_VERTICAL,
	show_overlap = DSHOW_OVERLAP,
	show_overlap_enable,
	show_links_enable,
	comics_mode_enable,
	rtl_mode_enable, -- rtl = right-to-left
	page_mode_enable,

	-- the document:
	doc = nil,
	-- the document's setting store:
	settings = nil,
	-- list of available commands:
	commands = nil,

	-- we will use this one often, so keep it "static":
	nulldc = DrawContext.new(),

	-- tile cache configuration:
	cache_max_memsize = DCACHE_MAX_MEMSIZE, -- 5MB tile cache
	cache_max_ttl = DCACHE_MAX_TTL, -- time to live
	-- tile cache state:
	cache_current_memsize = 0,
	cache = {},
	-- renderer cache size
	cache_document_size = DCACHE_DOCUMENT_SIZE, -- FIXME random, needs testing

	pagehash = nil,

	-- we use array to simluate two stacks,
	-- one for backwards, one for forwards
	jump_history = {cur = 1},
	bookmarks = {},
	highlight = {},
	toc = nil,
	toc_expandable = false, -- if true then TOC contains expandable/collapsible items
	toc_children = nil, -- each element is the list of children for each TOC node (nil if none)
	toc_xview = nil, -- fully expanded (and marked with '+') view of TOC
	toc_cview = nil, -- current view of TOC
	toc_curidx_to_x = nil, -- current view to expanded view map

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
	InfoMessage:inform("Registering fonts...", nil, 1, MSG_AUX)
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
-- Given coordinates on the screen return position
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
		InfoMessage:inform("No text available ", 1000, 1, MSG_WARN);
		return nil
	end

	local function _findFirstWordInView(t)
		for i=1, #t, 1 do
			if self:_isEntireWordInScreenRange(t[i][1]) then
				return i, 1
			end
		end

		InfoMessage:inform("No visible text ", 1000, 1, MSG_WARN);
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
								table.remove(self.highlight[self.pageno],k)
								-- remove page entry if empty
								if #self.highlight[self.pageno] == 0 then
									table.remove(self.highlight, self.pageno)
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
	self.pan_margin = settings:readSetting("pan_margin") or self.pan_margin
	self.pan_overlap_vertical = settings:readSetting("pan_overlap_vertical") or self.pan_overlap_vertical
	self.cache_max_memsize = settings:readSetting("cache_max_memsize") or self.cache_max_memsize
	self.cache_max_ttl = settings:readSetting("cache_max_ttl") or self.cache_max_ttl
	self.rcountmax = settings:readSetting("rcountmax") or self.rcountmax
end

-- Method to load settings before document open
function UniReader:preLoadSettings(filename)
	self.settings = DocSettings:open(filename)
	self.cache_document_size = self.settings:readSetting("cache_document_size") or self.cache_document_size
end

-- all defaults which can be overriden by reader objects
-- (PDFReader, DJVUReader, etc) must be initialized here.
function UniReader:setDefaults()
	self.show_overlap_enable = DUNIREADER_SHOW_OVERLAP_ENABLE
	self.show_links_enable = DUNIREADER_SHOW_LINKS_ENABLE
	self.comics_mode_enable = DUNIREADER_COMICS_MODE_ENABLE
	self.rtl_mode_enable = DUNIREADER_RTL_MODE_ENABLE
	self.page_mode_enable = DUNIREADER_PAGE_MODE_ENABLE
end

-- This is a low-level method that can be shared with all readers.
function UniReader:loadSettings(filename)
	if self.doc ~= nil then
		-- moved "gamma" to not-crengine related parameters
		self.jump_history = self.settings:readSetting("jump_history") or {cur = 1}
		self.bookmarks = self.settings:readSetting("bookmarks") or {}

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

		self.highlight = self.settings:readSetting("highlight") or {}
		if self.highlight.to_fix ~= nil then
			for _,fix_item in ipairs(self.highlight.to_fix) do
				if fix_item == "djvu invert y axle" then
					Debug("Updating HighLight data...")
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

		self.rcountmax = self.settings:readSetting("rcountmax") or self.rcountmax

		self:setDefaults()
		local tmp = self.settings:readSetting("show_overlap_enable")
		if tmp ~= nil then
			self.show_overlap_enable = tmp
		end
		tmp = self.settings:readSetting("show_links_enable")
		if tmp ~= nil then
			self.show_links_enable = tmp
		end
		tmp = self.settings:readSetting("comics_mode_enable")
		if tmp ~= nil then
			self.comics_mode_enable = tmp
		end
		tmp = self.settings:readSetting("rtl_mode_enable")
		if tmp ~= nil then
			self.rtl_mode_enable = tmp
		end
		tmp = self.settings:readSetting("page_mode_enable")
		if tmp ~= nil then
			self.page_mode_enable = tmp
		end


		-- other parameters are reader-specific --> @TODO: move to proper place, like loadSpecialSettings()
		-- since DJVUReader still has no loadSpecialSettings(), just a quick solution is
		local ftype = string.lower(string.match(filename, ".+%.([^.]+)") or "")
		if ReaderChooser:getReaderByType(ftype) ~= CREReader then
			self.globalgamma = self.settings:readSetting("gamma") or self.globalgamma
			local bbox = self.settings:readSetting("bbox")
			Debug("bbox loaded ", bbox)
			self.bbox = bbox

			self.globalzoom = self.settings:readSetting("globalzoom") or 1.0
			self.globalzoom_mode = self.settings:readSetting("globalzoom_mode") or -1
			self.render_mode = self.settings:readSetting("render_mode") or 0
			self.shift_x = self.settings:readSetting("shift_x") or self.shift_x
			self.shift_y = self.settings:readSetting("shift_y") or self.shift_y
			self.step_manual_zoom = self.settings:readSetting("step_manual_zoom") or self.step_manual_zoom
		end

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

	local page_indicator = function()
		if Debug('page_indicator',no) then
			local pg_w = G_width / ( self.doc:getPages() )
			fb.bb:invertRect( pg_w*(no-1),0, pg_w,10)
			fb:refresh(1,     pg_w*(no-1),0, pg_w,10)
		end
	end
	page_indicator()

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

			page_indicator()

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
	page:draw(dc, self.cache[pagehash].bb, 0, 0, self.render_mode)
	page:close()

	page_indicator()

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
	-- rounds down pwidth and pheight to 2 decimals, because page:getUsedBBox() returns only 2 decimals.
	-- without it, later check whether to use margins will fail for some documents
	pwidth = math.floor(pwidth * 100) / 100
	pheight = math.floor(pheight * 100) / 100
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
		if self.comics_mode_enable then self.offset_y = 0 end
	elseif self.globalzoom_mode == self.ZOOM_FIT_TO_PAGE_HEIGHT
	or self.globalzoom_mode == self.ZOOM_FIT_TO_CONTENT_HEIGHT then
		self.globalzoom = height / pheight
		self.offset_x = (width - (self.globalzoom * pwidth)) / 2
		self.offset_y = 0
		self.pan_by_page = false
		if self.comics_mode_enable then 
			if self.rtl_mode_enable then
				self.offset_x = width - (self.globalzoom * pwidth)
			else
				self.offset_x = 0
			end
		end
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
		if x0 == 0 and y0 == 0 and x1 == pwidth and y1 == pheight then
			margin = 0
			Debug("page doesn't have bbox, disabling margin")
		end
		self.globalzoom = width / ( (x1 - x0) / ( 1 - ( margin / G_width ) ) ) -- decrease zoom for margin factor
		self.globalzoom = self.globalzoom * 2
		self.offset_x = -1 * x0 * self.globalzoom + margin
		self.offset_y = -1 * y0 * self.globalzoom + margin
		self.pan_x = self.offset_x
		self.pan_y = self.offset_y
		self.pan_x1 = -1 * x1 * self.globalzoom - margin + G_width  -- sets pan_x1 to left edge of the right column
		self.pan_y1 = -1 * y1 * self.globalzoom - margin + G_height
		self.pan_by_page = self.globalzoom_mode -- store for later and enable pan_by_page
		self.globalzoom_mode = self.ZOOM_BY_VALUE -- enable pan mode
		if self.rtl_mode_enable then self.offset_x = -1 * x1 * self.globalzoom - margin + width end
		Debug("column mode offset:", self.offset_x, self.offset_y, " zoom:", self.globalzoom, " margin:", margin);
	else
		Debug("globalzoom_mode didn't modify params", self.globalzoom_mode)
	end

	if self.adjust_offset then
		Debug("self.ajdust_offset BEFORE ", self.globalzoom, " globalrotate:", self.globalrotate, " offset:", self.offset_x, self.offset_y, " pagesize:", self.fullwidth, self.fullheight, " min_offset:", self.min_offset_x, self.min_offset_y)
		self.adjust_offset(self)
		self.adjust_offset = nil
		Debug("self.ajdust_offset  AFTER ", self.globalzoom, " globalrotate:", self.globalrotate, " offset:", self.offset_x, self.offset_y, " pagesize:", self.fullwidth, self.fullheight, " min_offset:", self.min_offset_x, self.min_offset_y)
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
	if self.pan_y1 == 0 then self.pan_y1 = self.min_offset_y end

	Debug("Reader:setZoom globalzoom_mode:", self.globalzoom_mode, " globalzoom:", self.globalzoom, " globalrotate:", self.globalrotate, " offset:", self.offset_x, self.offset_y, " pagesize:", self.fullwidth, self.fullheight, " min_offset:", self.min_offset_x, self.min_offset_y)

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

	if self.last_globalzoom_mode == self.ZOOM_FIT_TO_CONTENT_WIDTH_PAN then
		Debug("ZOOM_FIT_TO_CONTENT_WIDTH_PAN - fit page to top")
		self.dest_y = 0
	end

	if self.dest_x or self.dest_y then
		fb.bb:paintRect(0, 0, width, height, DBACKGROUND_COLOR)
	end
	Debug("blitFrom dest_off:", self.dest_x, self.dest_y,
		"src_off:", offset_x, offset_y,
		"width:", width, "height:", height)
	fb.bb:blitFrom(bb, self.dest_x, self.dest_y, offset_x, offset_y, width, height)

	Debug("self.show_overlap", self.show_overlap)
       if self.show_overlap_enable and not self.comics_mode_enable then
               if self.show_overlap < 0 then
                       fb.bb:dimRect(0,0, width, self.dest_y - self.show_overlap)
               elseif self.show_overlap > 0 then
                       fb.bb:dimRect(0,self.dest_y + height - self.show_overlap, width, self.show_overlap)
               end
	end
	self.show_overlap = 0

	-- render highlights to page
	if self.highlight[no] then
		self:toggleTextHighLight(self.highlight[no])
	end

	-- draw links on page
	local links = nil
	if self.show_links_enable then
		links = self:getPageLinks( no )
	end
	if links ~= nil then
		for i, link in ipairs(links) do
			if link.page then -- skip non-page links
				local x,y,w,h = self:zoomedRectCoordTransform( link.x0,link.y0, link.x1,link.y1 )
				fb.bb:invertRect(x,y+h-2, w,1)
			end
		end
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
	local numpages = self.doc:getPages()
	if no < 1 or no > numpages then
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
	if no < numpages then

		local old = {
			globalzoom = self.globalzoom,
			offset_x = self.offset_x,
			offset_y = self.offset_y,
			dest_x = self.dest_x,
			dest_y = self.dest_y,
			min_offset_x = self.min_offset_x,
			min_offset_y = self.min_offset_y,
			pan_x = self.pan_x,
			pan_y = self.pan_y
		}

		self:drawOrCache(no+1, true)

		-- restore currently visible values, not from preCache page
		self.globalzoom = old.globalzoom
		self.offset_x = old.offset_x
		self.offset_y = old.offset_y
		self.dest_x = old.dest_x
		self.dest_y = old.dest_y
		self.min_offset_x = old.min_offset_x
		self.min_offset_y = old.min_offset_y
		self.pan_x = old.pan_x
		self.pan_y = old.pan_y
		Debug("pre-cached page ", no+1, " and restored offsets")


		Debug("globalzoom_mode:", self.globalzoom_mode, " globalzoom:", self.globalzoom, " globalrotate:", self.globalrotate, " offset:", self.offset_x, self.offset_y, " pagesize:", self.fullwidth, self.fullheight, " min_offset:", self.min_offset_x, self.min_offset_y)

	end
end

function UniReader:redrawCurrentPage()
	self:goto(self.pageno)
end

function UniReader:nextView()
	local pageno = self.pageno

	Debug("nextView last_globalzoom_mode=", self.last_globalzoom_mode, " globalzoom_mode=", self.globalzoom_mode)

	if self.globalzoom_mode == self.ZOOM_FIT_TO_CONTENT_WIDTH_PAN
	or self.last_globalzoom_mode == self.ZOOM_FIT_TO_CONTENT_WIDTH_PAN then
		if self.offset_y <= self.min_offset_y or self.page_mode_enable then
			-- hit content bottom, turn to next page
			if pageno < self.doc:getPages() then
				self.globalzoom_mode = self.ZOOM_FIT_TO_CONTENT_WIDTH
			end
			pageno = pageno + 1
		else
			-- goto next view of current page
			self.offset_y = self.offset_y - G_height + self.pan_overlap_vertical

			if self.comics_mode_enable then
				if self.offset_y < self.min_offset_y then
					self.offset_y = self.min_offset_y - 0
				end
			end

			self.show_overlap = -self.pan_overlap_vertical -- top < 0
		end

	-- page-buttons in 2 column mode	
	elseif self.pan_by_page and not self.page_mode_enable then
			self:twoColNextView()
			pageno = self.pageno

	else
		-- not in fit to content width pan mode, just do a page turn
		pageno = pageno + 1
		if self.pan_by_page then
			Debug("two-column pan_by_page", self.pan_by_page)
			self.globalzoom_mode = self.pan_by_page
		end
	end

	return pageno
end

function UniReader:prevView()
	local pageno = self.pageno

	Debug("prevView last_globalzoom_mode=", self.last_globalzoom_mode, " globalzoom_mode=", self.globalzoom_mode)

	if self.globalzoom_mode == self.ZOOM_FIT_TO_CONTENT_WIDTH_PAN
	or self.last_globalzoom_mode == self.ZOOM_FIT_TO_CONTENT_WIDTH_PAN then
		if self.offset_y >= self.content_top or self.page_mode_enable then
			-- hit content top, turn to previous page
			-- set self.content_top with magic num to signal self:setZoom
			if pageno > 1 then
				self.content_top = -2012
			end
			if self.page_mode_enable then
				self.globalzoom_mode = self.ZOOM_FIT_TO_CONTENT_WIDTH
			end
			pageno = pageno - 1
		else
			-- goto previous view of current page
			self.offset_y = self.offset_y + G_height - self.pan_overlap_vertical

			if self.comics_mode_enable then
				if self.offset_y > self.content_top then
					self.offset_y = self.content_top + 0
				end
			end

			self.show_overlap = self.pan_overlap_vertical -- bottom > 0
		end

	-- page-buttons in 2 column mode
	elseif self.pan_by_page and not self.page_mode_enable then
			self:twoColPrevView()
			pageno = self.pageno
			
	else
		-- not in fit to content width pan mode, just do a page turn
		pageno = pageno - 1
		if self.pan_by_page then
			Debug("two-column pan_by_page", self.pan_by_page)
			self.globalzoom_mode = self.pan_by_page
		end
	end

	return pageno
end

function UniReader:twoColNextView()
	local pageno = self.pageno
	local x = G_width
	local y = G_height - self.pan_overlap_vertical -- overlap for lines which didn't fit
	if self.offset_y > self.pan_y1 then
		self.offset_y = self.offset_y - y
		self.show_overlap = self.offset_y + y - self.pan_y1 - G_height
		if self.offset_y < self.pan_y1 then
			self.offset_y = self.pan_y1
		else
			self.show_overlap = -self.pan_overlap_vertical -- top
		end

	-- can't go down anymore
	else
		if self.rtl_mode_enable then -- rtl_mode enabled
			-- can go left?
		  if self.offset_x + 0.01 < self.pan_x then
				self.offset_x = self.offset_x + x
				self.offset_y = self.pan_y
				self.show_overlap = 0

			-- can't go left -> end of page -> go to next one
			else
				if pageno < self.doc:getPages() then
					self.globalzoom_mode = self.pan_by_page
					self.pageno = self.pageno + 1
				end	
			end

		else -- rtl_mode disabled
			-- can go right?
			if self.offset_x - 0.01 > self.pan_x1 then
				self.offset_x = self.offset_x - x
				self.offset_y = self.pan_y
				self.show_overlap = 0

			-- can't go right -> end of page -> go to next one
			else
				if pageno < self.doc:getPages() then
					self.globalzoom_mode = self.pan_by_page
					self.pageno = self.pageno + 1
				end	
			end	-- end of page
		end	-- not rtl_mode	
	end -- move right
end

function UniReader:twoColPrevView()
	local pageno = self.pageno
	local x = G_width
	local y = G_height - self.pan_overlap_vertical -- overlap for lines which didn't fit
	
	-- can go up?
	if self.offset_y < self.pan_y then
		self.offset_y = self.offset_y + y
		self.show_overlap = self.offset_y + self.pan_overlap_vertical - self.pan_y
		if self.offset_y > self.pan_y then
			self.offset_y = self.pan_y
		else
			self.show_overlap = self.pan_overlap_vertical --bottom
		end

	-- no more up		
	else 	
		if self.rtl_mode_enable then -- rtl_mode enabled
			-- can go right?
		  if self.offset_x - 0.01 > self.pan_x1 then
				self.offset_x = self.offset_x - x
				self.offset_y = self.min_offset_y
				self.show_overlap = 0

			-- can't go right -> top of the page -> go to previous page
		  else
				if pageno > 1 then
					self.adjust_offset = function(unireader)
						self.offset_x = self.pan_x -- move to first column
						self.offset_y = self.min_offset_y
					end
					self.globalzoom_mode = self.pan_by_page
					self.pageno = self.pageno - 1
				end
		  end
		else -- rtl_mode disabled
			-- can go left?
		  if self.offset_x + 0.01 < self.pan_x then
				self.offset_x = self.offset_x + x
				self.offset_y = self.pan_y1
				self.show_overlap = 0

			-- can't go left -> top of the page -> go to previous page
			else
				if pageno > 1 then
					self.adjust_offset = function(unireader)
						self.offset_x = self.pan_x - G_width -- move to last column
						self.offset_y = self.pan_y1
					end
					self.globalzoom_mode = self.pan_by_page
					self.pageno = self.pageno - 1
				end
			end -- top of page
		end -- not rtl_mode
	end	-- move left
end

-- adjust global gamma setting
function UniReader:modifyGamma(factor)
	Debug("modifyGamma, gamma=", self.globalgamma, " factor=", factor)
	self.globalgamma = self.globalgamma * factor;
	InfoMessage:inform(string.format("New gamma is %.2f", self.globalgamma), nil, 1, MSG_AUX)
	self:redrawCurrentPage()
end

-- adjust zoom state and trigger re-rendering
function UniReader:setglobalzoom_mode(newzoommode)
	if self.globalzoom_mode ~= newzoommode then
		self.last_globalzoom_mode = nil
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
	return (title:gsub("\13", ""))
end

function UniReader:fillToc()
	self.toc = self.doc:getToc()
	self.toc_children = {}
	self.toc_xview = {}
	self.toc_cview = {}
	self.toc_curidx_to_x = {}

	-- To combine the forest represented by the array of depths
	-- (self.toc[].depth) into a single tree we introduce a virtual head
	-- of depth=0 at position index=0 (The Great Parent)
	local prev, prev_depth = 0, 0
	self.toc_xview[0] = "_HEAD"

	-- the parent[] array is only needed for the calculation of
	-- self.toc_children[] arrays.
	local parent = {}
	for k,v in ipairs(self.toc) do
		table.insert(self.toc_xview,
			("    "):rep(v.depth-1)..self:cleanUpTocTitle(v.title))
		if (v.depth > prev_depth) then --> k is a child of prev
			if not self.toc_children[prev] then
				self.toc_children[prev] = {}
			end
			table.insert(self.toc_children[prev], k)
			parent[k] = prev
			self.toc_xview[prev] = "+ "..self.toc_xview[prev]
			if prev > 0 then
				self.toc_expandable = true
			end
		elseif (v.depth == prev_depth) then --> k and prev are siblings
			parent[k] = parent[prev]
			if not self.toc_children[parent[k]] then
				table.insert(self.toc_children[0],k)
			else
				table.insert(self.toc_children[parent[k]], k)
			end
		else --> k and prev must have a common (possibly virtual) ancestor
			local par = parent[prev]
			while (self.toc[par].depth > v.depth) do
				par = parent[par]
			end
			parent[k] = parent[par]
			if not self.toc_children[parent[k]] then
				table.insert(self.toc_children[0],k)
			else
				table.insert(self.toc_children[parent[k]], k)
			end
		end
		prev = k
		prev_depth = self.toc[prev].depth
	end -- for k,v in ipairs(self.toc)
	if (self.toc_children[0]) then
		self.toc_curidx_to_x = self.toc_children[0]
		for i=1,#self.toc_children[0] do
			table.insert(self.toc_cview, self.toc_xview[self.toc_children[0][i]])
		end
	end
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
	local numpages = self.doc:getPages()
	for k,v in ipairs(self.toc) do
		if v.page >= 1 and v.page <= numpages and v.page > pageno then
			break
		end
		pre_entry = v
	end
	return self:cleanUpTocTitle(pre_entry.title)
end

function UniReader:getTocTitleOfCurrentPage()
	return self:getTocTitleByPage(self.pageno)
end

function UniReader:gotoTocEntry(entry)
	self:goto(entry.page)
end

-- expand TOC item to one level down
function UniReader:expandTOCItem(xidx, item_no)
	if string.find(self.toc_cview[item_no], "^+ ") then
		for i=#self.toc_children[xidx],1,-1 do
			table.insert(self.toc_cview, item_no+1,
				self.toc_xview[self.toc_children[xidx][i]])
			table.insert(self.toc_curidx_to_x, item_no+1,
				self.toc_children[xidx][i])
		end
		self.toc_cview[item_no] = string.gsub(self.toc_cview[item_no], "^+ ", "- ", 1)
	end
end

-- collapse TOC item AND all its descendants to all levels, recursively
function UniReader:collapseTOCItem(xidx, item_no)
	if string.find(self.toc_cview[item_no], "^- ") then
		for i=1,#self.toc_children[xidx] do
			self:collapseTOCItem(self.toc_curidx_to_x[item_no+1], item_no+1)
			table.remove(self.toc_cview, item_no+1)
			table.remove(self.toc_curidx_to_x, item_no+1)
		end
		self.toc_cview[item_no] = string.gsub(self.toc_cview[item_no], "^- ", "+ ", 1)
	end
end

-- expand all subitems of a given TOC item to all levels, recursively
function UniReader:expandAllTOCSubItems(xidx, item_no)
	if string.find(self.toc_cview[item_no], "^+ ") then
		for i=#self.toc_children[xidx],1,-1 do
			table.insert(self.toc_cview, item_no+1, self.toc_xview[self.toc_children[xidx][i]])
			table.insert(self.toc_curidx_to_x, item_no+1, self.toc_children[xidx][i])
			self:expandAllTOCSubItems(self.toc_curidx_to_x[item_no+1], item_no+1)
		end
		self.toc_cview[item_no] = string.gsub(self.toc_cview[item_no], "^+ ", "- ", 1)
	end
end

-- calculate the position as index into self.toc_cview[],
-- corresponding to the current page.
function UniReader:findTOCpos()
	local pos, found_pos = 0, false
	local numpages = self.doc:getPages()

	-- find the index into toc_xview first
	for k,v in ipairs(self.toc) do
		if v.page >= 1 and v.page <= numpages and v.page > self.pageno then
			pos = k - 1
			found_pos = true
			break
		end
	end

	if not found_pos then
		pos = #self.toc
	end

	found_pos = false

	-- now map it to toc_cview[]
	for k,v in ipairs(self.toc_curidx_to_x) do
		if v == pos then
			pos = k
			found_pos = true
			break
		elseif v > pos then
			pos = k - 1
			found_pos = true
			break
		end
	end

	if not found_pos then
		pos = #self.toc_cview
	end

	return pos
end

function UniReader:showToc()
	if not self.toc then
		self:fillToc() -- fill self.toc(title,page,depth) from physical TOC
	end

	if #self.toc == 0 then
		return InfoMessage:inform("No Table of Contents ", 1500, 1, MSG_WARN)
	end

	local toc_curitem = self:findTOCpos()

	while true do
		toc_menu = SelectMenu:new{
			menu_title = "Table of Contents (" .. tostring(#self.toc_cview) .. "/" .. tostring(#self.toc) .. " items)",
			item_array = self.toc_cview,
			current_entry = toc_curitem-1,
			expandable = self.toc_expandable
		}
		local ret_code, item_no, all = toc_menu:choose(0, fb.bb:getHeight())
		if ret_code then -- normal item selection
			-- check to make sure the destination is local
			local toc_entry = self.toc[self.toc_curidx_to_x[ret_code]]
			local pagenum = toc_entry.page
			if pagenum < 1 or pagenum > self.doc:getPages() then
				InfoMessage:inform("External links unsupported ", 1500, 1, MSG_WARN)
				toc_curitem = ret_code
			else
				return self:gotoTocEntry(toc_entry)
			end
		elseif item_no then -- expand or collapse item
			local abs_item_no = math.abs(item_no)
			local xidx = self.toc_curidx_to_x[abs_item_no]
			if self.toc_children[xidx] then
				if item_no > 0 then
					if not all then
						self:expandTOCItem(xidx, item_no)
					else
						self:expandAllTOCSubItems(xidx, item_no)
					end
				else
					self:collapseTOCItem(xidx, abs_item_no)
				end
			end
			toc_curitem = abs_item_no
		else -- return from menu via Back
			return self:redrawCurrentPage()
		end -- if ret_code
	end -- while true
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
		InfoMessage:inform("No jump history found ", 2000, 1, MSG_WARN)
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
	local ret_code, item_no = -1, -1

	-- build menu items
	for k,v in ipairs(self.bookmarks) do
		table.insert(menu_items,
			"p."..v.page.." "..v.notes.." @ "..v.datetime)
	end
	if #menu_items == 0 then
		return InfoMessage:inform("No bookmarks found ", 1500, 1, MSG_WARN)
	end
	while true do
		bm_menu = SelectMenu:new{
			menu_title = "Bookmarks ("..tostring(#menu_items).." items)",
			item_array = menu_items,
			deletable = true,
		}
		ret_code, item_no = bm_menu:choose(0, fb.bb:getHeight())
		if ret_code then -- normal item selection
			return self:goto(self.bookmarks[ret_code].page)
		elseif item_no then -- delete item
			table.remove(menu_items, item_no)
			table.remove(self.bookmarks, item_no)
			if #menu_items == 0 then
				return self:redrawCurrentPage()
			end
		else -- return via Back
			return self:redrawCurrentPage()
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
	local menu_items, highlight_page, highlight_num = {}, {}, {}
	local ret_code, item_no = -1, -1

	-- build menu items
	for k,v in pairs(self.highlight) do
		if type(k) == "number" then
			for k1,v1 in ipairs(v) do
				table.insert(menu_items, v1.text)
				table.insert(highlight_page, k)
				table.insert(highlight_num, k1)
			end
		end
	end

	if #menu_items == 0 then
		return InfoMessage:inform("No HighLights found ", 1000, 1, MSG_WARN)
	end

	while true do
		hl_menu = SelectMenu:new{
			menu_title = "HighLights ("..tostring(#menu_items).." items)",
			item_array = menu_items,
			deletable = true,
		}
		ret_code, item_no = hl_menu:choose(0, fb.bb:getHeight())
		if ret_code then
			return self:goto(highlight_page[ret_code])
		elseif item_no then -- delete item
			local hpage = highlight_page[item_no]
			local hnum = highlight_num[item_no]
			table.remove(self.highlight[hpage], hnum)
			if #self.highlight[hpage] == 0 then
				table.remove(self.highlight, hpage)
			end
			table.remove(menu_items, item_no)
			if #menu_items == 0 then
				return self:redrawCurrentPage()
			end
		else
			return self:redrawCurrentPage()
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

	self.highlight.drawer = "marker" -- show as inverted block instead of underline

	self:goto(self.pageno) -- show highlights, remove input
	if found > 0 then
		InfoMessage:inform( found.." hits '"..search.."' page "..self.pageno, 2000, 1, MSG_WARN)
		self.last_search = {
			pageno = self.pageno,
			search = search,
			hits = found,
		}
	else
		InfoMessage:inform( "'"..search.."' not found in document ", 2000, 1, MSG_WARN)
	end

	self.highlight = old_highlight -- will not remove search highlights until page refresh

end


function UniReader:getPageLinks(pageno)
	Debug("getPageLinks not supported in this format")
	return nil
end

function UniReader:clearSelection()
	-- used only in crengine
end

-- returns five numbers (in KB): rss, data, stack, lib, totalvm
function memUsage()
	local rss, data, stack, lib, totalvm = -1, -1, -1, -1, -1
	local file = io.open("/proc/self/status", "r")
	if file then
		for line in file:lines() do
			local s, n
			s, n = line:gsub("VmRSS:%s-(%d+) kB", "%1")	
			if n ~= 0 then rss = tonumber(s) end

			s, n = line:gsub("VmData:%s-(%d+) kB", "%1")	
			if n ~= 0 then data = tonumber(s) end

			s, n = line:gsub("VmStk:%s-(%d+) kB", "%1")	
			if n ~= 0 then stack = tonumber(s) end

			s, n = line:gsub("VmLib:%s-(%d+) kB", "%1")	
			if n ~= 0 then lib = tonumber(s) end

			s, n = line:gsub("VmSize:%s-(%d+) kB", "%1")	
			if n ~= 0 then totalvm = tonumber(s) end

			if rss ~= -1 and data ~= -1 and stack ~= -1 
			  and lib ~= -1 and totalvm ~= -1 then
				break
			end
		end -- for line in file:lines()
		file:close()
	end -- if file
	return rss, data, stack, lib, totalvm
end


-- used in UniReader:showMenu()
function UniReader:_drawReadingInfo()
	local width, height = G_width, G_height
	local numpages = self.doc:getPages()
	local load_percent = (self.pageno / numpages)
	local rss, data, stack, lib, totalvm = memUsage()
	local face = Font:getFace("rifont", 20)

	-- display memory on top of page
	fb.bb:paintRect(0, 0, width, 40+6*2, 0)
	renderUtf8Text(fb.bb, 10, 15+6, face,
		"M: "..
		math.ceil( self.cache_current_memsize / 1024 ).."/"..math.ceil( self.cache_max_memsize / 1024 ).."k "..
		math.ceil( self.doc:getCacheSize() / 1024 ).."/"..math.ceil( self.cache_document_size / 1024 ).."k", true)
	local txt = os.date("%a %d %b %Y %T").." ["..BatteryLevel().."]"
	local w = sizeUtf8Text(0, width, face, txt, true).x
	renderUtf8Text(fb.bb, width - w - 10, 15+6, face, txt, true)
	renderUtf8Text(fb.bb, 10, 15+6+22, face,
	"RSS:"..rss.." DAT:"..data.." STK:"..stack.." LIB:"..lib.." TOT:"..totalvm.."k", true)

	-- display reading progress on bottom of page
	local ypos = height - 50
	fb.bb:paintRect(0, ypos, width, 50, 0)
	ypos = ypos + 15
	local cur_section = self:getTocTitleOfCurrentPage()
	if cur_section ~= "" then
		cur_section = "Sec: "..cur_section
	end
	renderUtf8Text(fb.bb, 10, ypos+6, face,
		"p."..self.pageno.."/"..numpages.."   "..cur_section, true)

	ypos = ypos + 15
	blitbuffer.progressBar(fb.bb, 10, ypos, width-20, 15,
							5, 4, load_percent, 8)
end

function UniReader:showMenu()
	self:_drawReadingInfo()

	fb:refresh(1)
	while true do
		local ev = input.saveWaitForEvent()
		ev.code = adjustKeyEvents(ev)
		if ev.type == EV_KEY and ev.value == EVENT_VALUE_KEY_PRESS then
			if ev.code == KEY_BACK or ev.code == KEY_MENU then
				return
			elseif ev.code == KEY_C then
				self:clearCache()
			elseif ev.code == KEY_D then
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
			--local secs, usecs = util.gettime()
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

			--local nsecs, nusecs = util.gettime()
			--local dur = (nsecs - secs) * 1000000 + nusecs - usecs
			--Debug("E: T="..ev.type, " V="..ev.value, " C="..ev.code, " DUR=", dur)

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
	self.toc_expandable = false
	self.toc_children = nil
	self.toc_xview = nil
	self.toc_cview = nil
	self.toc_curidx_to_x = nil
	self:setDefaults()
	if self.doc ~= nil then
		self.doc:close()
	end
	if self.settings ~= nil then
		self:saveLastPageOrPos()
		self.settings:saveSetting("jump_history", self.jump_history)
		self.settings:saveSetting("bookmarks", self.bookmarks)
		self.settings:saveSetting("highlight", self.highlight)
		-- other parameters are reader-specific --> @TODO: move to a proper place, like saveSpecialSettings()
		self.settings:saveSetting("gamma", self.globalgamma)
		self.settings:saveSetting("bbox", self.bbox)
		self.settings:saveSetting("globalzoom", self.globalzoom)
		self.settings:saveSetting("globalzoom_mode", self.globalzoom_mode)
		self.settings:saveSetting("render_mode", self.render_mode)	-- djvu-related only
		--[[ the following parameters were already stored when user changed defaults
		self.settings:saveSetting("shift_x", self.shift_x)
		self.settings:saveSetting("shift_y", self.shift_y)
		self.settings:saveSetting("step_manual_zoom", self.step_manual_zoom)
		self.settings:saveSetting("rcountmax", self.rcountmax)
		]]
		self:saveSpecialSettings()
		self.settings:close()
	end

	return keep_running
end

function UniReader:gotoPrevNextTocEntry(direction)
	if not self.toc then
		self:fillToc()
	end
	if #self.toc == 0 then
		return InfoMessage:inform("No Table of Contents ", 1500, 1, MSG_WARN)
	end

	local numpages, last_toc_page, penul_toc_page = self.doc:getPages(), 1, 1
	local found_curr_toc = false
	for k, v in ipairs(self.toc) do
		if self.toc[k-1] then
			penul_toc_page = self.toc[k-1].page
		end
		last_toc_page = v.page
		if v.page >= 1 and v.page <= numpages and v.page > self.pageno then
			k = k - 1
			found_curr_toc = true
			if direction == -1 then -- skip all previous TOC entries with the same page
				while true do
					local curr_toc = self.toc[k]
					local prev_toc = self.toc[k-1]
					if prev_toc and (prev_toc.page == curr_toc.page) then
						k = k - 1
					else
						break
					end
				end
			end
			local toc_entry = self.toc[k + direction]
			if toc_entry then
				return self:goto(toc_entry.page, true)	
			end
			break
		end
	end

	if not found_curr_toc then
		if direction == 1 and self.pageno ~= numpages then
			return self:goto(numpages, true)
		elseif direction == -1 then
			if self.pageno == numpages then
				return self:goto(last_toc_page, true)
			else
				return self:goto(penul_toc_page, true)
			end
		end
	end
end

-- command definitions
function UniReader:addAllCommands()
	self.commands = Commands:new()
	self.commands:addGroup(MOD_ALT.."H/J", {Keydef:new(KEY_H,MOD_ALT), Keydef:new(KEY_J,MOD_ALT)},
		"go to prev/next TOC entry",
		function(unireader,keydef)
			if keydef.keycode == KEY_H then
				self:gotoPrevNextTocEntry(-1)
			else
				self:gotoPrevNextTocEntry(1)
			end
		end
	)
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
		"zoom out/in ".. self.step_manual_zoom .."% ",
		function(unireader,keydef)
			local is_zoom_out = (keydef.keycode == KEY_PGBCK or keydef.keycode == KEY_LPGBCK)
			local new_zoom = unireader.globalzoom_orig * (1 + (is_zoom_out and -1 or 1)*unireader.step_manual_zoom/100)
			InfoMessage:inform(string.format("New zoom is %.2f ", new_zoom), nil, 1, MSG_WARN)
			unireader:setGlobalZoom(new_zoom)
		end)
	-- NuPogodi, 03.09.12: make zoom step user-configurable
	self.commands:addGroup(MOD_SHIFT.."< >",{
		Keydef:new(KEY_PGBCK,MOD_SHIFT),Keydef:new(KEY_PGFWD,MOD_SHIFT),
		Keydef:new(KEY_LPGBCK,MOD_SHIFT),Keydef:new(KEY_LPGFWD,MOD_SHIFT)},
		"decrease/increase zoom step",
		function(unireader,keydef)
			if keydef.keycode == KEY_PGFWD or keydef.keycode == KEY_LPGFWD then
				unireader.step_manual_zoom = unireader.step_manual_zoom * 2
				self.settings:saveSetting("step_manual_zoom", self.step_manual_zoom)
				InfoMessage:inform("New zoom step is "..unireader.step_manual_zoom.."%. ", 2000, 1, MSG_WARN)
			else
				local minstep = 1
				if unireader.step_manual_zoom > 2*minstep then
					unireader.step_manual_zoom = unireader.step_manual_zoom / 2
					self.settings:saveSetting("step_manual_zoom", self.step_manual_zoom)
					InfoMessage:inform("New zoom step is "..unireader.step_manual_zoom.."%. ", 2000, 1, MSG_WARN)
				else
					InfoMessage:inform("Minimum zoom step is "..minstep.."%. ", 2000, 1, MSG_WARN)
				end
			end
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
				InfoMessage:inform("Already first jump ", 2000, 1, MSG_WARN)
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
				InfoMessage:inform("Already last jump ", 2000, 1, MSG_WARN)
			end
		end)
	self.commands:addGroup("vol-/+",{Keydef:new(KEY_VPLUS,nil),Keydef:new(KEY_VMINUS,nil)},
		"decrease/increase gamma 10%",
		function(unireader,keydef)
			unireader:modifyGamma(keydef.keycode==KEY_VPLUS and 1.1 or 0.9)
		end)
	--numeric key group
	local numeric_keydefs = {}
	for i=1,10 do numeric_keydefs[i]=Keydef:new(KEY_1+i-1,nil,tostring(i%10)) end
	self.commands:addGroup("[1, 2 .. 9, 0]",numeric_keydefs,
		"jump to 0%, 10% .. 90%, 100% of document",
		function(unireader,keydef)
			--Debug('jump to page:', math.max(math.floor(unireader.doc:getPages()*(keydef.keycode-KEY_1)/9),1), '/', unireader.doc:getPages())
			unireader:goto(math.max(math.floor(unireader.doc:getPages()*(keydef.keycode-KEY_1)/9),1))
		end)
	-- end numeric keys

	-- function calls menu to visualize and/or to switch zoom mode
	self.commands:add(KEY_M, nil, "M",
		"select zoom mode",
		function(unireader)
			local mode_list = {
				"Zoom by value",			-- ZOOM_BY_VALUE = 0, remove?
				"Fit zoom to page",			-- A	ZOOM_FIT_TO_PAGE = -1,
				"Fit zoom to page width",		-- S	ZOOM_FIT_TO_PAGE_WIDTH = -2,
				"Fit zoom to page height",		-- D	ZOOM_FIT_TO_PAGE_HEIGHT = -3,
				"Fit zoom to content",			-- ^A	ZOOM_FIT_TO_CONTENT = -4,
				"Fit zoom to content width",		-- ^S	ZOOM_FIT_TO_CONTENT_WIDTH = -5,
				"Fit zoom to content height",		-- ^D	ZOOM_FIT_TO_CONTENT_HEIGHT = -6,
				"Fit zoom to content width with panoraming",	-- 	ZOOM_FIT_TO_CONTENT_WIDTH_PAN = -7, remove?
				"Fit zoom to content height with panoraming",	-- 	ZOOM_FIT_TO_CONTENT_HEIGHT_PAN = -8, remove?
				"Fit zoom to content half-width with margin",	-- F	ZOOM_FIT_TO_CONTENT_HALF_WIDTH_MARGIN = -9,
				"Fit zoom to content half-width"		-- ^F	ZOOM_FIT_TO_CONTENT_HALF_WIDTH = -10,
				}
			local zoom_menu = SelectMenu:new{
				menu_title = "Select mode to zoom pages",
				item_array = mode_list,
				current_entry = - unireader.globalzoom_mode
				}
			local re = zoom_menu:choose(0, G_height)
			if not re or re==(1-unireader.globalzoom_mode) or re==1 or re==8 or re==9 then -- if not proper zoom-mode
				unireader:redrawCurrentPage()
			else
				unireader:setglobalzoom_mode(1-re)
			end
		end)
	-- to leave or to erase 8 hotkeys switching zoom-mode directly?

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
		"go to page",
		function(unireader)
			local numpages = unireader.doc:getPages()
			local page = NumInputBox:input(G_height-100, 100,
				"Page:", "current page "..self.pageno.." of "..numpages, true)
			-- convert string to number
			if not pcall(function () page = math.floor(page) end)
			or page < 1 or page > numpages then
				page = unireader.pageno
			end
			unireader:goto(page)
		end)
	self.commands:add(KEY_H,nil,"H",
		"show help page",
		function(unireader)
			HelpPage:show(0, G_height, unireader.commands)
			unireader:redrawCurrentPage()
		end)
	self.commands:add(KEY_DOT,MOD_ALT,".",
		"toggle battery level logging",
		function(unireader)
			G_battery_logging = not G_battery_logging
			InfoMessage:inform("Battery logging "..(G_battery_logging and "ON" or "OFF"), nil, 1, MSG_AUX)
			G_reader_settings:saveSetting("G_battery_logging", G_battery_logging)
			self:redrawCurrentPage()
		end)
	self.commands:add(KEY_T,nil,"T",
		"show table of content (TOC)",
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
				InfoMessage:inform("Page already marked ", 1500, 1, MSG_WARN)
			else
				InfoMessage:inform("Page marked ", 1500, 1, MSG_WARN)
			end
		end)
	self.commands:addGroup(MOD_ALT.."K/L",{
		Keydef:new(KEY_K,MOD_ALT), Keydef:new(KEY_L,MOD_ALT)},
		"jump between bookmarks",
		function(unireader,keydef)
			local bm = nil
			if keydef.keycode == KEY_K then
				bm = self:prevBookMarkedPage()
			else
				bm = self:nextBookMarkedPage()
			end
			if bm then self:goto(bm.page, true) end
		end)
	self.commands:add(KEY_B,MOD_SHIFT,"B",
		"show jump history",
		function(unireader)
			unireader:showJumpHist()
		end)
	self.commands:add(KEY_J,MOD_SHIFT,"J",
		"rotate 10° clockwise",
		function(unireader)
			unireader:setRotate(unireader.globalrotate + 10)
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
			unireader:setRotate(unireader.globalrotate - 10)
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

	self.commands:add(KEY_O, nil, "O",
		"toggle showing page overlap areas",
		function(unireader)
			unireader.show_overlap_enable = not unireader.show_overlap_enable
			InfoMessage:inform("Turning overlap "..(unireader.show_overlap_enable and "ON" or "OFF"), nil, 1, MSG_AUX)
			self.settings:saveSetting("show_overlap_enable", unireader.show_overlap_enable)
			self:redrawCurrentPage()
		end)

	self.commands:add(KEY_P, nil, "P",
		"toggle page-buttons mode: viewport/page",
		function(unireader)
			unireader.page_mode_enable = not unireader.page_mode_enable
			InfoMessage:inform("Page-buttons move "..(unireader.page_mode_enable and "page" or "viewport"), nil, 1, MSG_AUX)
			self.settings:saveSetting("page_mode_enable", unireader.page_mode_enable)
			self:redrawCurrentPage()
		end)

	self.commands:add(KEY_U, nil, "U",
		"toggle right-to-left mode on/off",
		function(unireader)
			unireader.rtl_mode_enable = not unireader.rtl_mode_enable
			InfoMessage:inform("Right-To-Left mode "..(unireader.rtl_mode_enable and "ON" or "OFF"), nil, 1, MSG_AUX)
			self.settings:saveSetting("rtl_mode_enable", unireader.rtl_mode_enable)
			self:redrawCurrentPage()
		end)

	self.commands:add(KEY_C, nil, "C",
		"toggle comics mode on/off",
		function(unireader)
			unireader.comics_mode_enable = not unireader.comics_mode_enable
			InfoMessage:inform("Comics mode "..(unireader.comics_mode_enable and "ON" or "OFF"), nil, 1, MSG_AUX)
			self.settings:saveSetting("comics_mode_enable", unireader.comics_mode_enable)
			self:redrawCurrentPage()
		end)

	self.commands:add(KEY_C, MOD_SHIFT, "C",
		"reset default reader preferences",
		function(unireader)
			G_reader_settings:delSetting("reader_preferences")
			InfoMessage:inform("Reseting reader preferences", 1000, 1, MSG_AUX)
		end)
	
	self.commands:add(KEY_C, MOD_ALT, "C",
		"clear reader association with this doc",
		function(unireader)
			if self.settings:readSetting("reader_association") == "N/A" then
				InfoMessage:inform("No reader associated", 1000, 1, MSG_AUX)
			else
				self.settings:saveSetting("reader_association", "N/A")
				InfoMessage:inform("Clearing reader association", 1000, 1, MSG_AUX)
			end
		end)

	self.commands:add(KEY_R, MOD_SHIFT, "R",
		"set full screen refresh count",
		function(unireader)
			local count = NumInputBox:input(G_height-100, 100,
				"Full refresh every N pages (0-200)", self.rcountmax, true)
			-- convert string to number
			if pcall(function () count = math.floor(count) end) then
				if count < 0 then
					count = 0
				elseif count > 200 then
					count = 200
				end
				self.rcountmax = count
				-- storing this parameter in both global and local settings
				G_reader_settings:saveSetting("rcountmax", self.rcountmax)
				self.settings:saveSetting("rcountmax", self.rcountmax)
			end
			self:redrawCurrentPage()
		end)

	self.commands:add(KEY_SPACE, nil, "Space",
		"manual full screen refresh",
		function(unireader)
			-- eInk will not refresh if nothing has changed on the screen so we fake a change here.
			fb.bb:invertRect(0, 0, 1, 1)
			fb:refresh(1)
			fb.bb:invertRect(0, 0, 1, 1)
			fb:refresh(0)
			self.rcount = self.rcountmax
			self:redrawCurrentPage()
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
			InfoMessage:inform("Manual crop setting saved. ", 2000, 1, MSG_WARN)
		end)
	self.commands:add(KEY_Z,MOD_SHIFT,"Z",
		"reset crop",
		function(unireader)
			unireader.bbox[unireader.pageno] = nil;
			InfoMessage:inform("Manual crop setting removed. ", 2000, 1, MSG_WARN)
			Debug("bbox remove", unireader.pageno, unireader.bbox);
		end)
	self.commands:add(KEY_Z,MOD_ALT,"Z",
		"toggle crop mode",
		function(unireader)
			unireader.bbox.enabled = not unireader.bbox.enabled;
			if unireader.bbox.enabled then
				InfoMessage:inform("Manual crop enabled. ", 2000, 1, MSG_WARN)
			else
				InfoMessage:inform("Manual crop disabled. ", 2000, 1, MSG_WARN)
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
			InfoMessage:inform(running_corner.." bbox ", nil, 1, MSG_WARN,
				running_corner.." bounding box")
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
							InfoMessage:inform(running_corner.." bbox ", nil, 1, MSG_WARN,
								running_corner.." bounding box")
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
					elseif ev.code == KEY_BACK then
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
								Debug("ERROR: unknown direction!")
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
			InfoMessage:inform("New page bbox ", 2000, 1, MSG_WARN, "New page bounding box")
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
	-- panning: NuPogodi, 03.09.2012: since Alt+KEY_FW-keys do not work and Shift+KEY_FW-keys alone
	-- are not enough to cover the wide range, I've extracted changing pansteps to separate functions
	local panning_keys = {	Keydef:new(KEY_FW_LEFT,nil), Keydef:new(KEY_FW_RIGHT,nil),
					Keydef:new(KEY_FW_UP,nil), Keydef:new(KEY_FW_DOWN,nil),
					Keydef:new(KEY_FW_PRESS,MOD_ANY) }

	self.commands:addGroup("[joypad]",panning_keys,
		"pan the active view",
		function(unireader,keydef)
			if keydef.keycode ~= KEY_FW_PRESS then
				if unireader.globalzoom_mode ~= unireader.ZOOM_BY_VALUE then
					Debug("save last_globalzoom_mode=", unireader.globalzoom_mode);
					self.last_globalzoom_mode = unireader.globalzoom_mode
					unireader.globalzoom_mode = unireader.ZOOM_BY_VALUE
				end
			end
			if unireader.globalzoom_mode == unireader.ZOOM_BY_VALUE then
				local x, y
				if unireader.pan_by_page then
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

					if self.rtl_mode_enable then	-- rtl_mode enabled				
						if unireader.pan_by_page then
							if unireader.offset_x - 0.01 > unireader.pan_x then 
								-- leftmost column
								if unireader.pageno < unireader.doc:getPages() then
									self.globalzoom_mode = self.pan_by_page
									Debug("recalculate top-right of next page")
									unireader:goto(unireader.pageno + 1)
								else
									unireader.offset_x = unireader.offset_x - x
									Debug("end of document - do nothing")
								end
							else
							-- rightmost column
								unireader.show_overlap = 0
								unireader.offset_y = unireader.pan_y
							end
						elseif unireader.offset_x > 0 then
							unireader.offset_x = 0
						end

					else -- rtl_mode disabled
						if unireader.pan_by_page then
							if unireader.offset_x - 0.01 > unireader.pan_x then 
								-- leftmost column
								if unireader.pageno > 1 then
									unireader.adjust_offset = function(unireader)
										unireader.offset_x = unireader.pan_x - G_width -- move to last column
										unireader.offset_y = unireader.pan_y1
										Debug("pan to right-bottom of previous page")
									end
									self.globalzoom_mode = self.pan_by_page
									Debug("recalculate top-left of previous page")
									unireader:goto(unireader.pageno - 1)
								else
									unireader.offset_x = unireader.offset_x - x
									Debug("first page - can't go any more left")
								end	
							else
							-- rightmost column
								unireader.show_overlap = 0
								unireader.offset_y = unireader.pan_y1
							end
						elseif unireader.offset_x > 0 then
							unireader.offset_x = 0
						end
					end

				elseif keydef.keycode == KEY_FW_RIGHT then
					Debug("KEY_FW_RIGHT", unireader.offset_x, "-", x, "<", unireader.min_offset_x, "-", unireader.pan_margin);
					unireader.offset_x = unireader.offset_x - x

					if self.rtl_mode_enable then -- rtl_mode enabled
						if unireader.pan_by_page then
							if unireader.offset_x + 0.01 < unireader.pan_x1 then
								-- rightmost column
								if unireader.pageno > 1 then
									unireader.adjust_offset = function(unireader)
										unireader.offset_x = unireader.pan_x
										unireader.offset_y = unireader.pan_y1
										Debug("pan to bottom-left of previous page")
									end
									self.globalzoom_mode = self.pan_by_page
									Debug("recalculate top-left of previous page")
									unireader:goto(unireader.pageno - 1)
								else
									unireader.offset_x = unireader.offset_x + x
									Debug("first page - can't go any more right")
								end	
							else -- left column
								unireader.show_overlap = 0
								unireader.offset_y = unireader.pan_y1
							end
						elseif unireader.offset_x < unireader.min_offset_x then
							unireader.offset_x = unireader.min_offset_x
						end

					else -- rtl_mode disabled
						if unireader.pan_by_page then
							if unireader.offset_x + 0.01 < unireader.pan_x1 then
								-- rightmost column
								if unireader.pageno < unireader.doc:getPages() then
									Debug("pan to top-left of next page")
									self.globalzoom_mode = self.pan_by_page
									unireader:goto(unireader.pageno + 1)
								else
									unireader.offset_x = unireader.offset_x + x
									Debug("end of document - do nothing")
								end	
							else
							-- leftmost column
								unireader.show_overlap = 0
								unireader.offset_y = unireader.pan_y
							end
						elseif unireader.offset_x < unireader.min_offset_x then
							unireader.offset_x = unireader.min_offset_x
						end
					end

				elseif keydef.keycode == KEY_FW_UP then
					unireader.offset_y = unireader.offset_y + y
					if unireader.pan_by_page then
						if unireader.offset_y > unireader.pan_y then
							unireader.show_overlap = unireader.offset_y + unireader.pan_overlap_vertical - unireader.pan_y
							unireader.offset_y = unireader.pan_y
						else
							unireader.show_overlap = unireader.pan_overlap_vertical -- bottom
						end
					else
						if unireader.offset_y > 0 then unireader.offset_y = 0 end
					end		
							
				elseif keydef.keycode == KEY_FW_DOWN then
					unireader.offset_y = unireader.offset_y - y
					if unireader.pan_by_page then
						if unireader.offset_y < unireader.pan_y1 then
							unireader.show_overlap = unireader.offset_y + y - unireader.pan_y1 - G_height
							unireader.offset_y = unireader.pan_y1
						else
							unireader.show_overlap = -unireader.pan_overlap_vertical -- top
						end
					else
						if unireader.offset_y < unireader.min_offset_y then 
							unireader.offset_y = unireader.min_offset_y
						end
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
	-- functions to change panning steps
	self.commands:addGroup("Shift + left/right", {Keydef:new(KEY_FW_LEFT,MOD_SHIFT), Keydef:new(KEY_FW_RIGHT,MOD_SHIFT)},
		"increase/decrease X-panning step",
		function(unireader,keydef)
			unireader.globalzoom_mode = unireader.ZOOM_BY_VALUE
			local minstep = 1
			if keydef.keycode == KEY_FW_RIGHT then
				unireader.shift_x = unireader.shift_x * 2
				if unireader.shift_x >= G_width then
					unireader.shift_x = G_width
					InfoMessage:inform("Maximum X-panning step is "..G_width..". ", 2000, 1, MSG_WARN)
				end
				self.settings:saveSetting("shift_x", self.shift_x)
				InfoMessage:inform("New X-panning step is "..unireader.shift_x..". ", 2000, 1, MSG_WARN)
			else
				if unireader.shift_x >= 2*minstep then
					unireader.shift_x = math.ceil(unireader.shift_x / 2)
					self.settings:saveSetting("shift_x", self.shift_x)
					InfoMessage:inform("New X-panning step is "..unireader.shift_x..". ", 2000, 1, MSG_WARN)
				else
					InfoMessage:inform("Minimum X-panning step is "..minstep..". ", 2000, 1, MSG_WARN)
				end
			end
		end)
	self.commands:addGroup("Shift + up/down", {Keydef:new(KEY_FW_DOWN,MOD_SHIFT), Keydef:new(KEY_FW_UP,MOD_SHIFT)},
		"increase/decrease Y-panning step",
		function(unireader,keydef)
			unireader.globalzoom_mode = unireader.ZOOM_BY_VALUE
			local minstep = 1
			if keydef.keycode == KEY_FW_UP then
				unireader.shift_y = unireader.shift_y * 2
				if unireader.shift_y >= G_height then
					unireader.shift_y = G_height
					InfoMessage:inform("Maximum Y-panning step is "..G_height..". ", 2000, 1, MSG_WARN)
				end
				self.settings:saveSetting("shift_y", self.shift_y)
				InfoMessage:inform("New Y-panning step is "..unireader.shift_y..". ", 2000, 1, MSG_WARN)
			else
				if unireader.shift_y >= 2*minstep then
					unireader.shift_y = math.ceil(unireader.shift_y / 2)
					self.settings:saveSetting("shift_y", self.shift_y)
					InfoMessage:inform("New Y-panning step is "..unireader.shift_y..". ", 2000, 1, MSG_WARN)
				else
					InfoMessage:inform("Minimum Y-panning step is "..minstep..". ", 2000, 1, MSG_WARN)
				end
			end
		end)
	-- end panning

	-- highlight mode
	self.commands:add(KEY_N, nil, "N",
		"enter highlight mode",
		function(unireader)
			unireader:startHighLightMode()
			unireader:goto(unireader.pageno)
		end
	)
	self.commands:add(KEY_N, MOD_SHIFT, "N",
		"show all highlights",
		function(unireader)
			unireader:showHighLight()
			unireader:goto(unireader.pageno)
		end
	)
	self.commands:add(KEY_DOT, nil, ".",
		"search and highlight text",
		function(unireader)
			Screen:saveCurrentBB()
			local search = InputBox:input(G_height - 100, 100,
				"Search:", self.last_search.search )
			Screen:restoreFromSavedBB()

			if search ~= nil and string.len( search ) > 0 then
				unireader:searchHighLight(search)
			else
				unireader:goto(unireader.pageno)
			end
		end
	)
	self.commands:add(KEY_L, MOD_SHIFT, "L",
		"show/hide link underlines",
		function(unireader)
			unireader.show_links_enable = not unireader.show_links_enable
			InfoMessage:inform("Link underlines "..(unireader.show_links_enable and "ON" or "OFF"), nil, 1, MSG_AUX)
			self.settings:saveSetting("show_links_enable", unireader.show_links_enable)
			self:redrawCurrentPage()
		end
	)
	self.commands:add(KEY_L, nil, "L",
		"page links shortcut keys",
		function(unireader)
			local links = unireader:getPageLinks( unireader.pageno )
			if links == nil or next(links) == nil then
				InfoMessage:inform("No links on this page ", 2000, 1, MSG_WARN)
			else
				Debug("shortcuts",SelectMenu.item_shortcuts)

				local page_links = 0
				local visible_links = {}
				local need_refresh = false

				for i, link in ipairs(links) do
					if link.page then -- from mupdf
						local x,y,w,h = self:zoomedRectCoordTransform( link.x0,link.y0, link.x1,link.y1 )
						if x > 0 and y > 0 and x < G_width and y < G_height then
							-- draw top and side borders so we get a box for each link (bottom one is on page)
							fb.bb:invertRect(x,    y, w,1)
							fb.bb:invertRect(x,    y, 1,h-2)
							fb.bb:invertRect(x+w-2,y, 1,h-2)

							fb.bb:dimRect(x,y,w,h) -- black 50%
							fb.bb:dimRect(x,y,w,h) -- black 25%
							page_links = page_links + 1
							visible_links[page_links] = link
						end
					elseif link.section and string.sub(link.section,1,1) == "#" then -- from crengine
						if link.start_y >= self.pos and link.start_y <= self.pos + G_height then
							link.start_y = link.start_y - self.pos -- top of screen
							page_links = page_links + 1
							visible_links[page_links] = link
							need_refresh = true
						end
					end
				end

				if page_links == 0 then
					InfoMessage:inform("No page links on this page ", 2000, 1, MSG_WARN)
					return
				end

				Debug("visible_links", visible_links)

				if need_refresh then
					unireader:redrawCurrentPage() -- show links
					need_refresh = false
				end

				Screen:saveCurrentBB() -- save dimmed links

				local shortcut_offset = 0
				local shortcut_map
				local num_shortcuts = #SelectMenu.item_shortcuts-1

				local render_shortcuts = function()
					if need_refresh then
						Screen:restoreFromSavedBB()
					end

					local shortcut_nr = 1
					shortcut_map = {}

					for i = 1, num_shortcuts, 1 do
						local link = visible_links[ i + shortcut_offset ]
						if link == nil then break end
						Debug("link", i, shortcut_offset, link)
						local x,y,w,h
						if link.page then
							x,y,w,h = self:zoomedRectCoordTransform( link.x0,link.y0, link.x1,link.y1 )
						elseif link.section
 then
							x,y,h = link.start_x, link.start_y, self.doc:zoomFont(0) -- delta=0, return font size
						end

						if x and y and h then
							local face = Font:getFace("rifont", h)
							Debug("shortcut position:", x,y, "letter=", SelectMenu.item_shortcuts[shortcut_nr], "for", shortcut_nr)
							if shortcut_nr == 29 then -- skip KEY_SLASH as not available on Kindle 3
								shortcut_nr = shortcut_nr + 1
							end
							renderUtf8Text(fb.bb, x, y + h - 1, face, SelectMenu.item_shortcuts[shortcut_nr])
							shortcut_map[shortcut_nr] = i + shortcut_offset
							shortcut_nr = shortcut_nr + 1
						end
					end

					Debug("shortcut_map", shortcut_map)

					fb:refresh(1)
				end

				render_shortcuts()

				local goto_page = nil

				while not goto_page do

					local ev = input.saveWaitForEvent()
					ev.code = adjustKeyEvents(ev)
					Debug("ev",ev)

					local link = nil

					if ev.type == EV_KEY and ev.value ~= EVENT_VALUE_KEY_RELEASE then
						need_refresh = true
						if ev.code >= KEY_Q and ev.code <= KEY_P then
							link = ev.code - KEY_Q + 1
						elseif ev.code >= KEY_A and ev.code <= KEY_L then
							link = ev.code - KEY_A + 11
						elseif ev.code >= KEY_Z and ev.code <= KEY_M then
							link = ev.code - KEY_Z + 21
						elseif ev.code == KEY_DOT then
							link = 28
						elseif ev.code == KEY_SYM then
							link = 20
						elseif ev.code == KEY_ENTER then
							link = 30
						elseif ev.code == KEY_BACK then
							goto_page = unireader.pageno
						elseif ( ev.code == KEY_FW_RIGHT or ev.code == KEY_FW_DOWN ) and shortcut_offset <= #visible_links - num_shortcuts then
							shortcut_offset = shortcut_offset + num_shortcuts
							render_shortcuts()
						elseif ( ev.code == KEY_FW_LEFT or ev.code == KEY_FW_UP ) and shortcut_offset >= num_shortcuts then
							shortcut_offset = shortcut_offset - num_shortcuts
							render_shortcuts()
						else
							need_refresh = false
						end
					end

					if link then
						link = shortcut_map[link]
						if visible_links[link] ~= nil then
							if visible_links[link].page ~= nil then
								goto_page = visible_links[link].page + 1
							elseif visible_links[link].section ~= nil then
								goto_page = visible_links[link].section
							else
								Debug("Unknown link target in", link)
							end
						else
							Debug("missing link", link)
						end
					end

					Debug("goto_page", goto_page, "now on", unireader.pageno, "link", link)
				end

				unireader:clearSelection()

				unireader:goto(goto_page, false, "link")

			end
		end
	)
	-- NuPogodi, 02.10.12: added functions to switch kpdfviewer mode from readers
	self.commands:add(KEY_M, MOD_ALT, "M",
		"set user privilege level",
		function(unireader)
			FileChooser:changeFileChooserMode()
			self:redrawCurrentPage()
		end
	)
	self.commands:add(KEY_E, nil, "E",
		"configure event notifications",
		function(unireader)
			InfoMessage:chooseNotificatonMethods()
			self:redrawCurrentPage()
		end
	)
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
	-- commands.map is very large, impacts startup performance on device
	--Debug("defined commands "..dump(self.commands.map))
end
