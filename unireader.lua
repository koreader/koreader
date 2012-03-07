require "keys"
require "settings"
require "selectmenu"

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

	-- size of current page for current zoom level in pixels
	fullwidth = 0,
	fullheight = 0,
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

	-- you have to initialize newDC, nulldc in specific reader
	newDC = function() return nil end,
	-- we will use this one often, so keep it "static":
	nulldc = nil, 

	-- tile cache configuration:
	cache_max_memsize = 1024*1024*5, -- 5MB tile cache
	cache_item_max_pixels = 1024*1024*2, -- max. size of rendered tiles
	cache_max_ttl = 20, -- time to live
	-- tile cache state:
	cache_current_memsize = 0,
	cache = {},
	jump_stack = {},
	toc = nil,

	bbox = {}, -- override getUsedBBox
}

function UniReader:new(o)
	o = o or {}
	setmetatable(o, self)
	self.__index = self
	return o
end

--[[ 
	For a new specific reader,
	you must always overwrite following two methods:

	* self:init()
	* self:open()

	overwrite other methods if needed.
--]]
function UniReader:init()
	print("empty initialization method!")
end

-- open a file and its settings store
-- tips: you can use self:loadSettings in open() method.
function UniReader:open(filename, password)
	return false
end



--[ following are default methods ]--

function UniReader:loadSettings(filename)
	if self.doc ~= nil then
		self.settings = DocSettings:open(filename)

		local gamma = self.settings:readsetting("gamma")
		if gamma then
			self.globalgamma = gamma
		end

		local jumpstack = self.settings:readsetting("jumpstack")
		self.jump_stack = jumpstack or {}

		return true
	end
	return false
end

function UniReader:initGlobalSettings(settings)
	local pan_overlap_vertical = settings:readsetting("pan_overlap_vertical")
	if pan_overlap_vertical then
		self.pan_overlap_vertical = pan_overlap_vertical
	end
	local bbox = settings:readsetting("bbox")
	if bbox then
		self.bbox = bbox
	end
end

-- guarantee that we have enough memory in cache
function UniReader:cacheclaim(size)
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

function UniReader:draworcache(no, zoom, offset_x, offset_y, width, height, gamma, rotate)
	-- hash draw state
	local hash = self:cachehash(no, zoom, offset_x, offset_y, width, height, gamma, rotate)
	if self.cache[hash] == nil then
		-- not in cache, so prepare cache slot...
		self:cacheclaim(width * height / 2);
		self.cache[hash] = {
			ttl = self.cache_max_ttl,
			size = width * height / 2,
			bb = Blitbuffer.new(width, height)
		}
		-- and draw the page
		local page = self.doc:openPage(no)
		local dc = self:setzoom(page, hash)
		page:draw(dc, self.cache[hash].bb, 0, 0)
		page:close()
	else
		-- we have the page in our cache,
		-- so give it more ttl.
		self.cache[hash].ttl = self.cache_max_ttl
	end
	return hash
end

-- calculate a hash for our current state
function UniReader:cachehash(no, zoom, offset_x, offset_y, width, height, gamma, rotate)
	-- TODO (?): make this a "real" hash...
	return no..'_'..zoom..'_'..offset_x..','..offset_y..'-'..width..'x'..height..'_'..gamma..'_'..rotate
end

-- blank the cache
function UniReader:clearcache()
	self.cache = {}
	self.cache_current_memsize = 0
end

-- set viewer state according to zoom state
function UniReader:setzoom(page)
	local dc = self.newDC()
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

	if self.bbox then
		print("# ORIGINAL page::getUsedBBox "..x0.."*"..y0.." "..x1.."*"..y1);
		local bbox = self.bbox[self.pageno] -- exact

		local odd_even = self:odd_even(self.pageno)
		if bbox ~= nil then
			print("## bbox from "..self.pageno)
		else
			bbox = self.bbox[odd_even] -- odd/even
		end
		if bbox ~= nil then -- last used up to this page
			print("## bbox from "..odd_even)
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
	dc:setOffset(self.offset_x, self.offset_y)
	self.fullwidth, self.fullheight = page:getSize(dc)
	self.min_offset_x = fb.bb:getWidth() - self.fullwidth
	self.min_offset_y = fb.bb:getHeight() - self.fullheight
	if(self.min_offset_x > 0) then
		self.min_offset_x = 0
	end
	if(self.min_offset_y > 0) then
		self.min_offset_y = 0
	end

	print("# Reader:setzoom globalzoom:"..self.globalzoom.." globalrotate:"..self.globalrotate.." offset:"..self.offset_x.."*"..self.offset_y.." pagesize:"..self.fullwidth.."*"..self.fullheight.." min_offset:"..self.min_offset_x.."*"..self.min_offset_y)

	-- set gamma here, we don't have any other good place for this right now:
	if self.globalgamma ~= self.GAMMA_NO_GAMMA then
		print("gamma correction: "..self.globalgamma)
		dc:setGamma(self.globalgamma)
	end
	return dc
end

-- render and blit a page
function UniReader:show(no)
	local slot
	if self.globalzoommode ~= self.ZOOM_BY_VALUE then
		slot = self:draworcache(no,self.globalzoommode,self.offset_x,self.offset_y,width,height,self.globalgamma,self.globalrotate)
	else
		slot = self:draworcache(no,self.globalzoom,self.offset_x,self.offset_y,width,height,self.globalgamma,self.globalrotate)
	end
	fb.bb:blitFullFrom(self.cache[slot].bb)
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
function UniReader:add_jump(pageno, notes)
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

function UniReader:del_jump(pageno)
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
		self:add_jump(self.pageno)
	end

	self.pageno = no
	self:show(no)

	if no < self.doc:getPages() then
		if self.globalzoommode ~= self.ZOOM_BY_VALUE then
			if #self.bbox == 0 then
				-- pre-cache next page, but if we will modify bbox don't!
				self:draworcache(no+1,self.globalzoommode,self.offset_x,self.offset_y,width,height,self.globalgamma,self.globalrotate)
			end
		else
			self:draworcache(no,self.globalzoom,self.offset_x,self.offset_y,width,height,self.globalgamma,self.globalrotate)
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
			-- set self.content_top with magic num to signal self:setzoom 
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
function UniReader:modify_gamma(factor)
	print("modify_gamma, gamma="..self.globalgamma.." factor="..factor)
	self.globalgamma = self.globalgamma * factor;
	self:goto(self.pageno)
end

-- adjust zoom state and trigger re-rendering
function UniReader:setglobalzoommode(newzoommode)
	if self.globalzoommode ~= newzoommode then
		self.globalzoommode = newzoommode
		self:goto(self.pageno)
	end
end

-- adjust zoom state and trigger re-rendering
function UniReader:setglobalzoom(zoom)
	if self.globalzoom ~= zoom then
		self.globalzoommode = self.ZOOM_BY_VALUE
		self.globalzoom = zoom
		self:goto(self.pageno)
	end
end

function UniReader:setrotate(rotate)
	self.globalrotate = rotate
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
	
	for _k,_v in ipairs(self.toc) do
		if _v.page >= pageno then
			return self:cleanUpTOCTitle(_v.title)
		end
	end
	return ""
end

function UniReader:showTOC()
	if not self.toc then
		-- build toc when needed.
		self:fillTOC()
	end
	local menu_items = {}
	local filtered_toc = {}
	local curr_page = -1
	-- build menu items
	for _k,_v in ipairs(self.toc) do
		if(_v.page >= curr_page) then
			table.insert(menu_items,
			("        "):rep(_v.depth-1)..self:cleanUpTOCTitle(_v.title))
			table.insert(filtered_toc,_v.page)
			curr_page = _v.page
		end
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
	for _k,_v in ipairs(self.jump_stack) do
		table.insert(menu_items, 
			_v.datetime.." -> Page ".._v.page.." ".._v.notes)
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

function UniReader:odd_even(number)
	print("## odd_even "..number)
	if number % 2 == 1 then
		return "odd"
	else
		return "even"
	end
end

-- wait for input and handle it
function UniReader:inputloop()
	local keep_running = true
	self.bbox = {}
	while 1 do
		local ev = input.waitForEvent()
		ev.code = adjustKeyEvents(ev)
		if ev.type == EV_KEY and ev.value == EVENT_VALUE_KEY_PRESS then
			local secs, usecs = util.gettime()
			if ev.code == KEY_PGFWD or ev.code == KEY_LPGFWD then
				if Keys.shiftmode then
					self:setglobalzoom(self.globalzoom+self.globalzoom_orig*0.2)
				elseif Keys.altmode then
					self:setglobalzoom(self.globalzoom+self.globalzoom_orig*0.1)
				else
					-- turn page forward
					local pageno = self:nextView()
					self:goto(pageno)
				end
			elseif ev.code == KEY_PGBCK or ev.code == KEY_LPGBCK then
				if Keys.shiftmode then
					self:setglobalzoom(self.globalzoom-self.globalzoom_orig*0.2)
				elseif Keys.altmode then
					self:setglobalzoom(self.globalzoom-self.globalzoom_orig*0.1)
				else
					-- turn page back
					local pageno = self:prevView()
					self:goto(pageno)
				end
			elseif ev.code == KEY_BACK then
				if Keys.altmode then
					-- altmode, exit reader
					break
				else
					-- not altmode, back to last jump
					if #self.jump_stack ~= 0 then
						self:goto(self.jump_stack[1].page)
					end
				end
			elseif ev.code == KEY_VPLUS then
				self:modify_gamma( 1.25 )
			elseif ev.code == KEY_VMINUS then
				self:modify_gamma( 0.8 )
			elseif ev.code == KEY_1 then
				self:goto(1)
			elseif ev.code >= KEY_2 and ev.code <= KEY_9 then
				self:goto(math.floor(self.doc:getPages()/90*(ev.code-KEY_1)*10))
			elseif ev.code == KEY_0 then
				self:goto(self.doc:getPages())						
			elseif ev.code == KEY_A then
				if Keys.shiftmode then
					self:setglobalzoommode(self.ZOOM_FIT_TO_CONTENT)
				else
					self:setglobalzoommode(self.ZOOM_FIT_TO_PAGE)
				end
			elseif ev.code == KEY_S then
				if Keys.shiftmode then
					self:setglobalzoommode(self.ZOOM_FIT_TO_CONTENT_WIDTH)
				else
					self:setglobalzoommode(self.ZOOM_FIT_TO_PAGE_WIDTH)
				end
			elseif ev.code == KEY_D then
				if Keys.shiftmode then
					self:setglobalzoommode(self.ZOOM_FIT_TO_CONTENT_HEIGHT)
				else
					self:setglobalzoommode(self.ZOOM_FIT_TO_PAGE_HEIGHT)
				end
			elseif ev.code == KEY_F then
				if Keys.shiftmode then
					self:setglobalzoommode(self.ZOOM_FIT_TO_CONTENT_HALF_WIDTH)
				else
					self:setglobalzoommode(self.ZOOM_FIT_TO_CONTENT_HALF_WIDTH_MARGIN)
				end
			elseif ev.code == KEY_T then
				self:showTOC()
			elseif ev.code == KEY_B then
				if Keys.shiftmode then
					self:add_jump(self.pageno)
				else
					self:showJumpStack()
				end
			elseif ev.code == KEY_J then
				self:setrotate( self.globalrotate + 10 )
			elseif ev.code == KEY_K then
				self:setrotate( self.globalrotate - 10 )
			elseif ev.code == KEY_HOME then
				if Keys.shiftmode or Keys.altmode then
					-- signal quit
					keep_running = false
				end
				break
			elseif ev.code == KEY_Z then
				local bbox = {}
				bbox["x0"] = - self.offset_x / self.globalzoom
				bbox["y0"] = - self.offset_y / self.globalzoom
				bbox["x1"] = bbox["x0"] + width / self.globalzoom
				bbox["y1"] = bbox["y0"] + height / self.globalzoom
				self.bbox[self.pageno] = bbox
				self.bbox[self:odd_even(self.pageno)] = bbox
				print("# bbox " .. self.pageno .. dump(self.bbox)) 
				self.globalzoommode = self.ZOOM_FIT_TO_CONTENT -- use bbox
			end

			-- switch to ZOOM_BY_VALUE to enable panning on fiveway move
			if ev.code == KEY_FW_LEFT
			or ev.code == KEY_FW_RIGHT
			or ev.code == KEY_FW_UP
			or ev.code == KEY_FW_DOWN
			then
				self.globalzoommode = self.ZOOM_BY_VALUE
			end

			-- switch to ZOOM_BY_VALUE to enable panning on fiveway move
			if ev.code == KEY_FW_LEFT
			or ev.code == KEY_FW_RIGHT
			or ev.code == KEY_FW_UP
			or ev.code == KEY_FW_DOWN
			then
				self.globalzoommode = self.ZOOM_BY_VALUE
			end

			if self.globalzoommode == self.ZOOM_BY_VALUE then
				local x
				local y

				if Keys.shiftmode then -- shift always moves in small steps
					x = self.shift_x / 2
					y = self.shift_y / 2
				elseif Keys.altmode then
					x = self.shift_x / 5
					y = self.shift_y / 5
				elseif self.pan_by_page then
					x = width;
					y = height - self.pan_overlap_vertical; -- overlap for lines which didn't fit
				else
					x = self.shift_x
					y = self.shift_y
				end

				print("offset "..self.offset_x.."*"..self.offset_x.." shift "..x.."*"..y.." globalzoom="..self.globalzoom)
				local old_offset_x = self.offset_x
				local old_offset_y = self.offset_y

				if ev.code == KEY_FW_LEFT then
					print("# KEY_FW_LEFT "..self.offset_x.." + "..x.." > 0");
					self.offset_x = self.offset_x + x
					if self.pan_by_page then
						if self.offset_x > 0 and self.pageno > 1 then
							self.offset_x = self.pan_x
							self.offset_y = self.min_offset_y -- bottom
							self:goto(self.pageno - 1)
						else
							self.offset_y = self.min_offset_y
						end
					elseif self.offset_x > 0 then
						self.offset_x = 0
					end
				elseif ev.code == KEY_FW_RIGHT then
					print("# KEY_FW_RIGHT "..self.offset_x.." - "..x.." < "..self.min_offset_x);
					self.offset_x = self.offset_x - x
					if self.pan_by_page then
						if self.offset_x < self.min_offset_x - self.pan_margin and self.pageno < self.doc:getPages() then
							self.offset_x = self.pan_x
							self.offset_y = self.pan_y
							self:goto(self.pageno + 1)
						else
							self.offset_y = self.pan_y
						end
					elseif self.offset_x < self.min_offset_x then
						self.offset_x = self.min_offset_x
					end
				elseif ev.code == KEY_FW_UP then
					self.offset_y = self.offset_y + y
					if self.offset_y > 0 then
						self.offset_y = 0
					end
				elseif ev.code == KEY_FW_DOWN then
					self.offset_y = self.offset_y - y
					if self.offset_y < self.min_offset_y then
						self.offset_y = self.min_offset_y
					end
				elseif ev.code == KEY_FW_PRESS then
					if Keys.shiftmode then
						if self.pan_by_page then
							self.offset_x = self.pan_x
							self.offset_y = self.pan_y
						else
							self.offset_x = 0
							self.offset_y = 0
						end
					else
						self.pan_by_page = not self.pan_by_page
						if self.pan_by_page then
							self.pan_x = self.offset_x
							self.pan_y = self.offset_y
						end
					end
				end
				if old_offset_x ~= self.offset_x
				or old_offset_y ~= self.offset_y then
						self:goto(self.pageno)
				end
			end

			local nsecs, nusecs = util.gettime()
			local dur = (nsecs - secs) * 1000000 + nusecs - usecs
			print("E: T="..ev.type.." V="..ev.value.." C="..ev.code.." DUR="..dur)
		end
	end

	-- do clean up stuff
	self:clearcache()
	self.toc = nil
	if self.doc ~= nil then
		self.doc:close()
	end
	if self.settings ~= nil then
		self.settings:savesetting("last_page", self.pageno)
		self.settings:savesetting("gamma", self.globalgamma)
		self.settings:savesetting("jumpstack", self.jump_stack)
		--self.settings:savesetting("pan_overlap_vertical", self.pan_overlap_vertical)
		self.settings:savesetting("bbox", self.bbox)
		self.settings:close()
	end

	return keep_running
end
