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
	cache_item_max_pixels = 1024*1024*2, -- max. size of rendered tiles
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
-- you must always overwrite following two methods:
--
-- * self:open()
-- * self:init()
--
-- overwrite other methods if needed.
----------------------------------------------------
function UniReader:init()
end

-- open a file and its settings store
-- tips: you can use self:loadSettings in open() method.
function UniReader:open(filename, cache_size)
	return false
end

----------------------------------------------------
-- You need to overwrite following two methods if your
-- reader supports highlight feature.
----------------------------------------------------

function UniReader:startHighLightMode()
	return
end

function UniReader:highLightText()
	return
end

function UniReader:toggleTextHighLight(word_list)
	return
end

----------------------------------------------------
-- renderer memory
----------------------------------------------------

function UniReader:getCacheSize()
	return -1
end

function UniReader:cleanCache()
	return
end


--[ following are default methods ]--

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

		return true
	end
	return false
end

function UniReader:initGlobalSettings(settings)
	local pan_overlap_vertical = settings:readSetting("pan_overlap_vertical")
	if pan_overlap_vertical then
		self.pan_overlap_vertical = pan_overlap_vertical
	end
	-- initialize commands
	self:addAllCommands()

	local cache_max_memsize = settings:readSetting("cache_max_memsize")
	if cache_max_memsize then
		self.cache_max_memsize = cache_max_memsize
	end

	local cache_max_ttl = settings:readSetting("cache_max_ttl")
	if cache_max_ttl then
		self.cache_max_ttl = cache_max_ttl
	end
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
	elseif (tile.w*tile.h / 2) > max_cache then
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
			if tile.y + tile.h < self.fullheigth then
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
	self.cache = {}
	self.cache_current_memsize = 0
end

-- set viewer state according to zoom state
function UniReader:setzoom(page, preCache)
	local dc = DrawContext.new()
	local pwidth, pheight = page:getSize(self.nulldc)
	print("# page::getSize "..pwidth.."*"..pheight);
	local x0, y0, x1, y1 = page:getUsedBBox()
	if x0 == 0.01 and y0 == 0.01 and x1 == -0.01 and y1 == -0.01 then
		x0 = 0
		y0 = 0
		x1 = pwidth
		y1 = pheight
	end
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
			-- Since this a real page turn, we need to recalcunate stuff.
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
		self.globalzoom = width / (x1 - x0 + margin)
		self.offset_x = -1 * x0 * self.globalzoom * 2 + margin
		self.globalzoom = height / (y1 - y0)
		self.offset_y = -1 * y0 * self.globalzoom * 2 + margin
		self.globalzoom = width / (x1 - x0 + margin) * 2
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
	if not pagehash then
		return
	end
	self.pagehash = pagehash
	local bb = self.cache[pagehash].bb
	local dest_x = 0
	local dest_y = 0
	if bb:getWidth() - offset_x < width then
		-- we can't fill the whole output width, center the content
		dest_x = (width - (bb:getWidth() - offset_x)) / 2
	end
	if bb:getHeight() - offset_y < height and
	self.globalzoommode ~= self.ZOOM_FIT_TO_CONTENT_WIDTH_PAN then
		-- we can't fill the whole output height and not in
		-- ZOOM_FIT_TO_CONTENT_WIDTH_PAN mode, center the content
		dest_y = (height - (bb:getHeight() - offset_y)) / 2
	elseif self.globalzoommode == self.ZOOM_FIT_TO_CONTENT_WIDTH_PAN and
	self.offset_y > 0 then
		-- if we are in ZOOM_FIT_TO_CONTENT_WIDTH_PAN mode and turning to
		-- the top of the page, we might leave an empty space between the
		-- page top and screen top.
		dest_y = self.offset_y
	end
	if dest_x or dest_y then
		fb.bb:paintRect(0, 0, width, height, 8)
	end
	print("# blitFrom dest_off:("..dest_x..", "..dest_y..
		"), src_off:("..offset_x..", "..offset_y.."), "..
		"width:"..width..", height:"..height)
	fb.bb:blitFrom(bb, dest_x, dest_y, offset_x, offset_y, width, height)

	-- render highlights to page
	if self.highlight[no] then
		self:toggleTextHighLight(self.highlight[no])
	end

	if self.rcount == self.rcountmax then
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

--[[
	@ pageno is the page you want to add to jump_stack
--]]
function UniReader:addJump(pageno, notes)
	local jump_item = nil
	local notes_to_add = notes
	if not notes_to_add then
		-- no notes given, auto generate from TOC entry
		notes_to_add = self:getTOCTitleByPage(self.pageno)
		if notes_to_add ~= "" then
			notes_to_add = "in "..notes_to_add
		end
	end
	-- move pageno page to jump_stack top if already in
	for _t,_v in ipairs(self.jump_stack) do
		if _v.page == pageno then
			jump_item = _v
			table.remove(self.jump_stack, _t)
			-- if original notes is not empty, probably defined by users,
			-- we use the original notes to overwrite auto generated notes
			-- from TOC entry
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

function UniReader:nextView()
	local pageno = self.pageno

	if self.globalzoommode == self.ZOOM_FIT_TO_CONTENT_WIDTH_PAN then
		if self.offset_y <= self.min_offset_y then
			-- hit content bottom, turn to next page
			self.globalzoommode = self.ZOOM_FIT_TO_CONTENT_WIDTH
			pageno = pageno + 1
		else
			-- goto next view of current page
			self.offset_y = self.offset_y - height + self.pan_overlap_vertical
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
			self.offset_y = self.offset_y + height - self.pan_overlap_vertical
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
	self:goto(self.pageno)
end

-- adjust zoom state and trigger re-rendering
function UniReader:setGlobalZoomMode(newzoommode)
	if self.globalzoommode ~= newzoommode then
		self.globalzoommode = newzoommode
		self:goto(self.pageno)
	end
end

-- adjust zoom state and trigger re-rendering
function UniReader:setGlobalZoom(zoom)
	if self.globalzoom ~= zoom then
		self.globalzoommode = self.ZOOM_BY_VALUE
		self.globalzoom = zoom
		self:goto(self.pageno)
	end
end

function UniReader:setRotate(rotate)
	self.globalrotate = rotate
	self:goto(self.pageno)
end

-- @ orien: 1 for clockwise rotate, -1 for anti-clockwise
function UniReader:screenRotate(orien)
	Screen:screenRotate(orien)
	width, height = fb:getSize()
	self:clearCache()
	self:goto(self.pageno)
end

function UniReader:cleanUpTOCTitle(title)
	return title:gsub("\13", "")
end

function UniReader:fillTOC()
	self.toc = self.doc:getTOC()
end

function UniReader:getTOCTitleByPage(pageno)
	if not self.toc then
		-- build toc when needed.
		self:fillTOC()
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
	return self:cleanUpTOCTitle(pre_entry.title)
end

function UniReader:showTOC()
	if not self.toc then
		-- build toc when needed.
		self:fillTOC()
	end
	local menu_items = {}
	local filtered_toc = {}
	-- build menu items
	for k,v in ipairs(self.toc) do
		table.insert(menu_items,
		("        "):rep(v.depth-1)..self:cleanUpTOCTitle(v.title))
		table.insert(filtered_toc,v.page)
	end
	toc_menu = SelectMenu:new{
		menu_title = "Table of Contents",
		item_array = menu_items,
		no_item_msg = "This document does not have a Table of Contents.",
	}
	item_no = toc_menu:choose(0, fb.bb:getHeight())
	if item_no then
		self:goto(filtered_toc[item_no])
	else
		self:goto(self.pageno)
	end
end

function UniReader:showJumpStack()
	local menu_items = {}
	for k,v in ipairs(self.jump_stack) do
		table.insert(menu_items,
			v.datetime.." -> Page "..v.page.." "..v.notes)
	end
	jump_menu = SelectMenu:new{
		menu_title = "Jump Keeper      (current page: "..self.pageno..")",
		item_array = menu_items,
		no_item_msg = "No jump history.",
	}
	item_no = jump_menu:choose(0, fb.bb:getHeight())
	if item_no then
		local jump_item = self.jump_stack[item_no]
		self:goto(jump_item.page)
	else
		self:goto(self.pageno)
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
	toc_menu = SelectMenu:new{
		menu_title = "HighLights",
		item_array = menu_items,
		no_item_msg = "No HighLight found.",
	}
	item_no = toc_menu:choose(0, fb.bb:getHeight())
	if item_no then
		self:goto(highlight_dict[item_no].page)
	end
end

function UniReader:showMenu()
	local ypos = height - 50
	local load_percent = (self.pageno / self.doc:getPages())

	fb.bb:paintRect(0, ypos, width, 50, 0)

	ypos = ypos + 15
	local face, fhash = Font:getFaceAndHash(22)
	local cur_section = self:getTOCTitleByPage(self.pageno)
	if cur_section ~= "" then
		cur_section = "Section: "..cur_section
	end
	renderUtf8Text(fb.bb, 10, ypos+6, face, fhash,
		"Page: "..self.pageno.."/"..self.doc:getPages()..
		"    "..cur_section, true)

	ypos = ypos + 15
	blitbuffer.progressBar(fb.bb, 10, ypos, width-20, 15,
							5, 4, load_percent, 8)

	-- display memory on top of page
	fb.bb:paintRect(0, 0, width, 15+6*2, 0)
	renderUtf8Text(fb.bb, 10, 15+6, face, fhash,
		"Memory: "..
		math.ceil( self.cache_current_memsize / 1024 ).."/"..( self.cache_max_memsize / 1024 )..
		" "..( self.cache_item_max_pixels / 1024 ).." "..( self.cache_document_size / 1024 ).." k",
	true)

	fb:refresh(1)
	while 1 do
		local ev = input.waitForEvent()
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
		local ev = input.waitForEvent()
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
		self.settings:savesetting("last_page", self.pageno)
		self.settings:savesetting("gamma", self.globalgamma)
		self.settings:savesetting("jumpstack", self.jump_stack)
		self.settings:savesetting("bbox", self.bbox)
		self.settings:savesetting("globalzoom", self.globalzoom)
		self.settings:savesetting("globalzoommode", self.globalzoommode)
		self.settings:savesetting("highlight", self.highlight)
		self.settings:close()
	end

	return keep_running
end

-- command definitions
function UniReader:addAllCommands()
	self.commands = Commands:new()
	self.commands:add({KEY_PGFWD,KEY_LPGFWD},nil,">",
		"next page",
		function(unireader)
			unireader:goto(unireader:nextView())
		end)
	self.commands:add({KEY_PGBCK,KEY_LPGBCK},nil,"<",
		"previous page",
		function(unireader)
			unireader:goto(unireader:prevView())
		end)
	self.commands:add(KEY_PGFWD,MOD_ALT,">",
		"zoom in 10%",
		function(unireader)
			unireader:setGlobalZoom(unireader.globalzoom+unireader.globalzoom_orig*0.1)
		end)
	self.commands:add(KEY_PGBCK,MOD_ALT,"<",
		"zoom out 10%",
		function(unireader)
			unireader:setGlobalZoom(unireader.globalzoom-unireader.globalzoom_orig*0.1)
		end)
	self.commands:add(KEY_PGFWD,MOD_SHIFT,">",
		"zoom in 20%",
		function(unireader)
			unireader:setGlobalZoom(unireader.globalzoom+unireader.globalzoom_orig*0.2)
		end)
	self.commands:add(KEY_PGBCK,MOD_SHIFT,"<",
		"zoom out 20%",
		function(unireader)
			unireader:setGlobalZoom(unireader.globalzoom-unireader.globalzoom_orig*0.2)
		end)
	self.commands:add(KEY_BACK,nil,"back",
		"back to last jump",
		function(unireader)
			if #unireader.jump_stack ~= 0 then
				unireader:goto(unireader.jump_stack[1].page)
			end
		end)
	self.commands:add(KEY_BACK,MOD_ALT,"back",
		"close document",
		function(unireader)
			return "break"
		end)
	self.commands:add(KEY_VPLUS,nil,"vol+",
		"increase gamma 25%",
		function(unireader)
			unireader:modifyGamma( 1.25 )
		end)
	self.commands:add(KEY_VMINUS,nil,"vol-",
		"decrease gamma 25%",
		function(unireader)
			unireader:modifyGamma( 0.80 )
		end)
	--numeric key group
	local numeric_keydefs = {}
	for i=1,10 do numeric_keydefs[i]=Keydef:new(KEY_1+i-1,nil,tostring(i%10)) end
	self.commands:addGroup("[1..0]",numeric_keydefs,
		"jump to <key>*10% of document",
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
		"goto page",
		function(unireader)
			local page = InputBox:input(height-100, 100, "Page:")
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
			HelpPage:show(0,height,unireader.commands)
			unireader:goto(unireader.pageno)
		end)
	self.commands:add(KEY_T,nil,"T",
		"show table of content",
		function(unireader)
			unireader:showTOC()
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
	self.commands:add(KEY_J,nil,"J",
		"rotate 10° clockwise",
		function(unireader)
			unireader:setRotate( unireader.globalrotate + 10 )
		end)
	self.commands:add(KEY_J,MOD_SHIFT,"J",
		"rotate screen 90° clockwise",
		function(unireader)
			unireader:screenRotate("clockwise")
		end)
	self.commands:add(KEY_K,nil,"K",
		"rotate 10° counterclockwise",
		function(unireader)
			unireader:setRotate( unireader.globalrotate - 10 )
		end)
	self.commands:add(KEY_K,MOD_SHIFT,"K",
		"rotate screen 90° counterclockwise",
		function(unireader)
			unireader:screenRotate("anticlockwise")
		end)
	self.commands:add(KEY_N, nil, "N",
		"start highlight mode",
		function(unireader)
			unireader:startHighLightMode()
			unireader:goto(unireader.pageno)
		end)
	self.commands:add(KEY_N, MOD_SHIFT, "N",
		"display all highlights",
		function(unireader)
			unireader:showHighLight()
			unireader:goto(unireader.pageno)
		end)
	self.commands:add(KEY_HOME,nil,"Home",
		"exit application",
		function(unireader)
			keep_running = false
			return "break"
		end)
	self.commands:add(KEY_Z,nil,"Z",
		"set crop mode",
		function(unireader)
			local bbox = {}
			bbox["x0"] = - unireader.offset_x / unireader.globalzoom
			bbox["y0"] = - unireader.offset_y / unireader.globalzoom
			bbox["x1"] = bbox["x0"] + width / unireader.globalzoom
			bbox["y1"] = bbox["y0"] + height / unireader.globalzoom
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
		"open menu",
		function(unireader)
			unireader:showMenu()
			unireader:goto(unireader.pageno)
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
					x = width;
					y = height - unireader.pan_overlap_vertical; -- overlap for lines which didn't fit
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
							unireader.offset_y = unireader.pan_y
						end
					elseif unireader.offset_x < unireader.min_offset_x then
						unireader.offset_x = unireader.min_offset_x
					end
				elseif keydef.keycode == KEY_FW_UP then
					unireader.offset_y = unireader.offset_y + y
					if unireader.offset_y > 0 then
						unireader.offset_y = 0
					end
				elseif keydef.keycode == KEY_FW_DOWN then
					unireader.offset_y = unireader.offset_y - y
					if unireader.offset_y < unireader.min_offset_y then
						unireader.offset_y = unireader.min_offset_y
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
						unireader:goto(unireader.pageno)
				end
			end
		end)
	-- end panning
	print("## defined commands "..dump(self.commands.map))
end
