require "ui/reader/readerflip"
require "ui/reader/readerfooter"
require "ui/reader/readerdogear"

ReaderView = OverlapGroup:new{
	_name = "ReaderView",
	document = nil,

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
	-- DjVu page rendering mode (used in djvu.c:drawPage())
	render_mode = 0, -- default to COLOR
	-- Crengine view mode
	view_mode = "page", -- default to page mode

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
	local inner_offset = Geom:new{x = 0, y = 0}

	-- draw surrounding space, if any
	if self.dimen.h > self.visible_area.h then
		inner_offset.y = (self.dimen.h - self.visible_area.h) / 2
		bb:paintRect(x, y, self.dimen.w, inner_offset.y, self.outer_page_color)
		bb:paintRect(x, y + self.dimen.h - inner_offset.y - 1, self.dimen.w, inner_offset.y + 1, self.outer_page_color)
	end
	if self.dimen.w > self.visible_area.w then
		inner_offset.x = (self.dimen.w - self.visible_area.w) / 2
		bb:paintRect(x, y, inner_offset.x, self.dimen.h, self.outer_page_color)
		bb:paintRect(x + self.dimen.w - inner_offset.x - 1, y, inner_offset.x + 1, self.dimen.h, self.outer_page_color)
	end
	self.state.offset = inner_offset
	-- draw content
	if self.ui.document.info.has_pages then
		self.ui.document:drawPage(
			bb,
			x + inner_offset.x,
			y + inner_offset.y,
			self.visible_area,
			self.state.page,
			self.state.zoom,
			self.state.rotation,
			self.state.gamma,
			self.render_mode)
		UIManager:scheduleIn(0, function() self.ui:handleEvent(Event:new("HintPage")) end)
	else
		if self.view_mode == "page" then
			self.ui.document:drawCurrentViewByPage(
				bb,
				x + inner_offset.x,
				y + inner_offset.y,
				self.visible_area,
				self.state.page)
		else
			self.ui.document:drawCurrentViewByPos(
				bb,
				x + inner_offset.x,
				y + inner_offset.y,
				self.visible_area,
				self.state.pos)
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
end

--[[
This method is supposed to be only used by ReaderPaging
--]]
function ReaderView:recalculate()
	local page_size = nil
	if self.ui.document.info.has_pages then
		if not self.bbox then
			self.page_area = self.ui.document:getPageDimensions(
				self.state.page,
				self.state.zoom,
				self.state.rotation)
		else
			self.page_area = self.ui.document:getUsedBBoxDimensions(
				self.state.page,
				self.state.zoom,
				self.state.rotation)
		end
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
	self:onSetDimensions(Screen:getSize())
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
		self.footer_visible = self.document.info.has_pages
		self.document.configurable.full_screen = self.footer_visible and 0 or 1
	else
		self.footer_visible = full_screen == 0 and true or false
	end
	self:resetLayout()
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
	self.bbox = bbox
end

function ReaderView:onRotationUpdate(rotation)
	self.state.rotation = rotation
	self:recalculate()
end

function ReaderView:onGammaUpdate(gamma)
	self.state.gamma = gamma
end

function ReaderView:onHintPage()
	if self.state.page < self.ui.document.info.number_of_pages then
		self.ui.document:hintPage(
			self.state.page+1, 
			self.state.zoom, 
			self.state.rotation, 
			self.state.gamma, 
			self.render_mode)
	end
	return true
end

function ReaderView:onSetViewMode(new_mode)
	self.ui.view_mode = new_mode
	self.ui.document:setViewMode(new_mode)
	self.ui:handleEvent(Event:new("UpdatePos"))
	return true
end

function ReaderView:onCloseDocument()
	self.ui.doc_settings:saveSetting("render_mode", self.render_mode)
	self.ui.doc_settings:saveSetting("screen_mode", self.screen_mode)
	self.ui.doc_settings:saveSetting("gamma", self.state.gamma)
end
