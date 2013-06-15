require "ui/reader/readerflip"
require "ui/reader/readerfooter"
require "ui/reader/readerdogear"

ReaderView = OverlapGroup:new{
	document = nil,

	-- single page state
	state = {
		page = 0,
		pos = 0,
		zoom = 1.0,
		rotation = 0,
		gamma = 1.0,
		offset = nil,
		bbox = nil,
	},
	outer_page_color = 0,
	-- hightlight
	highlight = {
		temp_drawer = "invert",
		temp = {},
		saved_drawer = "lighten",
		saved = {},
	},
	highlight_visible = true,
	-- PDF/DjVu continuous paging
	page_scroll = nil,
	page_bgcolor = 0,
	page_states = {},
	scroll_mode = "vertical",
	page_gap = {
		width = scaleByDPI(8),
		height = scaleByDPI(8),
		color = 8,
	},
	-- DjVu page rendering mode (used in djvu.c:drawPage())
	render_mode = 0, -- default to COLOR
	-- Crengine view mode
	view_mode = "page", -- default to page mode
	hinting = true,

	-- visible area within current viewing page
	visible_area = Geom:new{x = 0, y = 0},
	-- dimen for current viewing page
	page_area = Geom:new{},
	-- dimen for area to dim
	dim_area = Geom:new{w = 0, h = 0},
	-- has footer
	footer_visible = false,
	-- has dogear
	dogear_visible = false,
	-- in flipping state
	flipping_visible = false,
}

function ReaderView:init()
	self:resetLayout()
end

function ReaderView:resetLayout()
	self.dogear = ReaderDogear:new{
		view = self,
	}
	self.footer = ReaderFooter:new{
		view = self,
	}
	self.flipping = ReaderFlipping:new{
		view = self,
	}
	self[1] = self.dogear
	self[2] = self.footer
	self[3] = self.flipping
end

function ReaderView:paintTo(bb, x, y)
	DEBUG("painting", self.visible_area, "to", x, y)
	if self.page_scroll then
		self:drawPageBackground(bb, x, y)
	else
		self:drawPageSurround(bb, x, y)
	end

	-- draw page content
	if self.ui.document.info.has_pages then
		if self.page_scroll then
			self:drawScrollPages(bb, x, y)
		else
			self:drawSinglePage(bb, x, y)
		end
	else
		if self.view_mode == "page" then
			self:drawPageView(bb, x, y)
		elseif self.view_mode == "scroll" then
			self:drawScrollView(bb, x, y)
		end
	end

	-- dim last read area
	if self.document.view_mode ~= "page"
	and self.dim_area.w ~= 0 and self.dim_area.h ~= 0 then
		bb:dimRect(
			self.dim_area.x, self.dim_area.y,
			self.dim_area.w, self.dim_area.h
		)
	end
	
	-- draw saved highlight
	if self.highlight_visible then
		self:drawSavedHighlight(bb, x, y)
	end
	
	-- draw temporary highlight
	if self.highlight.temp then
		self:drawTempHighlight(bb, x, y)
	end

	-- paint dogear
	if self.dogear_visible then
		self.dogear:paintTo(bb, x, y)
	end
	-- paint footer
	if self.footer_visible then
		self.footer:paintTo(bb, x, y)
	end
	-- paint flipping
	if self.flipping_visible then
		self.flipping:paintTo(bb, x, y)
	end
	-- stop activity indicator
	self.ui:handleEvent(Event:new("StopActivityIndicator"))
end

--[[
Given coordinates on the screen return position in original page
]]--
function ReaderView:screenToPageTransform(pos)
	if self.ui.document.info.has_pages then
		if self.page_scroll then
			return self:getScrollPagePosition(pos)
		else
			return self:getSinglePagePosition(pos)
		end
	end
end

--[[
Given rectangle in original page return rectangle on the screen
]]--
function ReaderView:pageToScreenTransform(page, rect)
	if self.ui.document.info.has_pages then
		if self.page_scroll then
			return self:getScrollPageRect(page, rect)
		else
			return self:getSinglePageRect(rect)
		end
	end
end

function ReaderView:drawPageBackground(bb, x, y)
	bb:paintRect(x, y, self.dimen.w, self.dimen.h, self.page_bgcolor)
end

function ReaderView:drawPageSurround(bb, x, y)
	if self.dimen.h > self.visible_area.h then
		bb:paintRect(x, y, self.dimen.w, self.state.offset.y, self.outer_page_color)
		bb:paintRect(x, y + self.dimen.h - self.state.offset.y - 1,
			self.dimen.w, self.state.offset.y + 1, self.outer_page_color)
	end
	if self.dimen.w > self.visible_area.w then
		bb:paintRect(x, y, self.state.offset.x, self.dimen.h, self.outer_page_color)
		bb:paintRect(x + self.dimen.w - self.state.offset.x - 1, y,
			self.state.offset.x + 1, self.dimen.h, self.outer_page_color)
	end
end

function ReaderView:drawScrollPages(bb, x, y)
	local pos = Geom:new{x = x , y = y}
	for page, state in ipairs(self.page_states) do
		self.ui.document:drawPage(
			bb,
			pos.x + state.offset.x,
			pos.y + state.offset.y,
			state.visible_area,
			state.page,
			state.zoom,
			state.rotation,
			state.gamma,
			self.render_mode)
		pos.y = pos.y + state.visible_area.h
		-- draw page gap if not the last part
		if page ~= #self.page_states then
			self:drawPageGap(bb, pos.x, pos.y)
			pos.y = pos.y + self.page_gap.height
		end
	end
	UIManager:scheduleIn(0, function()
		self.ui:handleEvent(Event:new("HintPage", self.hinting))
	end)
end

function ReaderView:getCurrentPageList()
	local pages = {}
	if self.ui.document.info.has_pages then
		if self.page_scroll then
			for _, state in ipairs(self.page_states) do
				table.insert(pages, state.page)
			end
		else
			table.insert(pages, self.state.page)
		end
	end
	return pages
end

function ReaderView:getScrollPagePosition(pos)
	local x_s, y_s = pos.x, pos.y
	local x_p, y_p = nil, nil
	for _, state in ipairs(self.page_states) do
		if y_s < state.visible_area.h + state.offset.y then
			y_p = (state.visible_area.y + y_s - state.offset.y) / state.zoom
			x_p = (state.visible_area.x + x_s - state.offset.x) / state.zoom
			return {
				x = x_p,
				y = y_p,
				page = state.page,
				zoom = state.zoom,
				rotation = state.rotation,
			}
		else
			y_s = y_s - state.visible_area.h - self.page_gap.height
		end
	end
end

function ReaderView:getScrollPageRect(page, rect_p)
	local rect_s = Geom:new{}
	for _, state in ipairs(self.page_states) do
		local trans_p = Geom:new(rect_p)
		trans_p:transformByScale(state.zoom, state.zoom)
		if page == state.page and state.visible_area:contains(trans_p) then
			rect_s.x = rect_s.x + state.offset.x + trans_p.x - state.visible_area.x
			rect_s.y = rect_s.y + state.offset.y + trans_p.y - state.visible_area.y
			rect_s.w = trans_p.w
			rect_s.h = trans_p.h
			return rect_s
		end
		rect_s.y = rect_s.y + state.visible_area.h + self.page_gap.height
	end
end

function ReaderView:drawPageGap(bb, x, y)
	if self.scroll_mode == "vertical" then
		bb:paintRect(x, y, self.dimen.w, self.page_gap.height, self.page_gap.color)
	elseif self.scroll_mode == "horizontal" then
		bb:paintRect(x, y, self.page_gap.width, self.dimen.h, self.page_gap.color)
	end
end

function ReaderView:drawSinglePage(bb, x, y)
	self.ui.document:drawPage(
		bb,
		x + self.state.offset.x,
		y + self.state.offset.y,
		self.visible_area,
		self.state.page,
		self.state.zoom,
		self.state.rotation,
		self.state.gamma,
		self.render_mode)
	UIManager:scheduleIn(0, function()
		self.ui:handleEvent(Event:new("HintPage", self.hinting))
	end)
end

function ReaderView:getSinglePagePosition(pos)
	local x_s, y_s = pos.x, pos.y
	return {
		x = (self.visible_area.x + x_s - self.state.offset.x) / self.state.zoom,
		y = (self.visible_area.y + y_s - self.state.offset.y) / self.state.zoom,
		page = self.state.page,
		zoom = self.state.zoom,
		rotation = self.state.rotation,
	}
end

function ReaderView:getSinglePageRect(rect_p)
	local rect_s = Geom:new{}
	local trans_p = Geom:new(rect_p)
	trans_p:transformByScale(self.state.zoom, self.state.zoom)
	if self.visible_area:contains(trans_p) then
		rect_s.x = self.state.offset.x + trans_p.x - self.visible_area.x
		rect_s.y = self.state.offset.y + trans_p.y - self.visible_area.y
		rect_s.w = trans_p.w
		rect_s.h = trans_p.h
		return rect_s
	end
end

function ReaderView:drawPageView(bb, x, y)
	self.ui.document:drawCurrentViewByPage(
		bb,
		x + self.state.offset.x,
		y + self.state.offset.y,
		self.visible_area,
		self.state.page)
end

function ReaderView:drawScrollView(bb, x, y)
	self.ui.document:drawCurrentViewByPos(
		bb,
		x + self.state.offset.x,
		y + self.state.offset.y,
		self.visible_area,
		self.state.pos)
end

function ReaderView:drawTempHighlight(bb, x, y)
	for page, boxes in pairs(self.highlight.temp) do
		for i = 1, #boxes do
			local rect = self:pageToScreenTransform(page, boxes[i])
			if rect then
				self:drawHighlightRect(bb, x, y, rect, self.highlight.temp_drawer)
			end
		end
	end
end

function ReaderView:drawSavedHighlight(bb, x, y)
	local pages = self:getCurrentPageList()
	for _, page in pairs(pages) do
		local items = self.highlight.saved[page]
		if not items then items = {} end
		for i = 1, #items do
			for j = 1, #items[i].boxes do
				local rect = self:pageToScreenTransform(page, items[i].boxes[j])
				if rect then
					self:drawHighlightRect(bb, x, y, rect, self.highlight.saved_drawer)
				end
			end -- end for each box
		end -- end for each hightlight
	end -- end for each page
end

function ReaderView:drawHighlightRect(bb, x, y, rect, drawer)
	local x, y, w, h = rect.x, rect.y, rect.w, rect.h
	
	if drawer == "underscore" then
		self.highlight.line_width = self.highlight.line_width or 2
		self.highlight.line_color = self.highlight.line_color or 5
		bb:paintRect(x, y+h-1, w,
			self.highlight.line_width,
			self.highlight.line_color)
	elseif drawer == "lighten" then
		bb:lightenRect(x, y, w, h, 0.1)
	elseif drawer == "invert" then
		bb:invertRect(x, y, w, h)
	end
end

function ReaderView:getPageArea(page, zoom, rotation)
	if self.use_bbox then
		return self.ui.document:getUsedBBoxDimensions(page, zoom, rotation)
	else
		return self.ui.document:getPageDimensions(page, zoom, rotation)
	end
end

--[[
This method is supposed to be only used by ReaderPaging
--]]
function ReaderView:recalculate()
	local page_size = nil
	if self.ui.document.info.has_pages then
		self.page_area = self:getPageArea(
			self.state.page,
			self.state.zoom,
			self.state.rotation)
		-- starts from left top of page_area
		self.visible_area.x = self.page_area.x
		self.visible_area.y = self.page_area.y
		-- reset our size
		self.visible_area:setSizeTo(self.dimen)
		-- and recalculate it according to page size
		self.visible_area:offsetWithin(self.page_area, 0, 0)
		-- clear dim area
		self.dim_area.w = 0
		self.dim_area.h = 0
		self.ui:handleEvent(
			Event:new("ViewRecalculate", self.visible_area, self.page_area))
	else
		self.visible_area:setSizeTo(self.dimen)
	end
	self.state.offset = Geom:new{x = 0, y = 0}
	if self.dimen.h > self.visible_area.h then
		self.state.offset.y = (self.dimen.h - self.visible_area.h) / 2
	end
	if self.dimen.w > self.visible_area.w then
		self.state.offset.x = (self.dimen.w - self.visible_area.w) / 2
	end
	-- flag a repaint so self:paintTo will be called
	UIManager:setDirty(self.dialog)
end

function ReaderView:PanningUpdate(dx, dy)
	DEBUG("pan by", dx, dy)
	local old = self.visible_area:copy()
	self.visible_area:offsetWithin(self.page_area, dx, dy)
	if self.visible_area ~= old then
		-- flag a repaint
		UIManager:setDirty(self.dialog)
		DEBUG("on pan: page_area", self.page_area)
		DEBUG("on pan: visible_area", self.visible_area)
		self.ui:handleEvent(
			Event:new("ViewRecalculate", self.visible_area, self.page_area))
	end
	return true
end

function ReaderView:onSetScreenMode(new_mode)
	if new_mode == "landscape" or new_mode == "portrait" then
		self.screen_mode = new_mode
		Screen:setScreenMode(new_mode)
		self.ui:handleEvent(Event:new("SetDimensions", Screen:getSize()))
	end

	if new_mode == "landscape" and self.document.info.has_pages then
		self.ui:handleEvent(Event:new("SetZoomMode", "contentwidth"))
		self.ui:handleEvent(Event:new("InitScrollPageStates"))
	end
	return true
end

-- for returning to FileManager
function ReaderView:onRestoreScreenMode(old_mode)
	if old_mode == "landscape" or old_mode == "portrait" then
		Screen:setScreenMode(old_mode)
		self.ui:handleEvent(Event:new("SetDimensions", Screen:getSize()))
	end
	return true
end

function ReaderView:onSetDimensions(dimensions)
	--DEBUG("set dimen", dimensions)
	self:resetLayout()
	self.dimen = dimensions
	if self.footer_visible then
		self.dimen.h = dimensions.h - self.footer.height
	end
	-- recalculate view
	self:recalculate()
end

function ReaderView:onRestoreDimensions(dimensions)
	--DEBUG("restore dimen", dimensions)
	self:resetLayout()
	self.dimen = dimensions
	-- recalculate view
	self:recalculate()
end

function ReaderView:onSetFullScreen(full_screen)
	self.footer_visible = not full_screen
	self.ui:handleEvent(Event:new("SetDimensions", Screen:getSize()))
end

function ReaderView:onToggleScrollMode(page_scroll)
	self.page_scroll = page_scroll
	self:recalculate()
	self.ui:handleEvent(Event:new("InitScrollPageStates"))
end

function ReaderView:onReadSettings(config)
	self.render_mode = config:readSetting("render_mode") or 0
	local screen_mode = config:readSetting("screen_mode")
	if screen_mode then
	    table.insert(self.ui.postInitCallback, function()
	        self:onSetScreenMode(screen_mode) end)
	end
	self.state.gamma = config:readSetting("gamma") or 1.0
	local full_screen = config:readSetting("kopt_full_screen")
	if full_screen == nil then
		full_screen = self.document.configurable.full_screen
	end
	self.footer_visible = full_screen == 0 and true or false
	self:resetLayout()
	local page_scroll = config:readSetting("kopt_page_scroll")
	if page_scroll == nil then
		page_scroll = self.document.configurable.page_scroll
	end
	self.page_scroll = page_scroll == 1 and true or false
	self.highlight.saved = config:readSetting("highlight") or {}
end

function ReaderView:onPageUpdate(new_page_no)
	self.state.page = new_page_no
	self:recalculate()
end

function ReaderView:onPosUpdate(new_pos)
	self.state.pos = new_pos
	self:recalculate()
end

function ReaderView:onZoomUpdate(zoom)
	self.state.zoom = zoom
	self:recalculate()
end

function ReaderView:onBBoxUpdate(bbox)
	self.use_bbox = bbox and true or false
end

function ReaderView:onRotationUpdate(rotation)
	self.state.rotation = rotation
	self:recalculate()
end

function ReaderView:onGammaUpdate(gamma)
	self.state.gamma = gamma
	if self.page_scroll then
		self.ui:handleEvent(Event:new("UpdateScrollPageGamma", gamma))
	end
end

function ReaderView:onFontSizeUpdate()
	self.ui:handleEvent(Event:new("ReZoom"))
end

function ReaderView:onDefectSizeUpdate()
	self.ui:handleEvent(Event:new("ReZoom"))
end

function ReaderView:onPageCrop()
	self.ui:handleEvent(Event:new("ReZoom"))
end

function ReaderView:onMarginUpdate()
	self.ui:handleEvent(Event:new("ReZoom"))
end

function ReaderView:onSetViewMode(new_mode)
	self.view_mode = new_mode
	self.ui.document:setViewMode(new_mode)
	self.ui:handleEvent(Event:new("ChangeViewMode"))
	return true
end

function ReaderView:onCloseDocument()
	self.ui.doc_settings:saveSetting("render_mode", self.render_mode)
	self.ui.doc_settings:saveSetting("screen_mode", self.screen_mode)
	self.ui.doc_settings:saveSetting("gamma", self.state.gamma)
	self.ui.doc_settings:saveSetting("highlight", self.highlight.saved)	
end
