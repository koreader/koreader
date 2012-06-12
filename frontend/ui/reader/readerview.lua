ReaderView = WidgetContainer:new{
	document = nil,

	state = {
		page = 0,
		pos = 0,
		zoom = 1.0,
		rotation = 0,
		offset = {},
		bbox = nil,
	},

	outer_page_color = 7,

	visible_area = Geom:new{x = 0, y = 0},
	page_area = Geom:new{},
}

function ReaderView:paintTo(bb, x, y)
	DEBUG("painting", self.visible_area, "to", x, y)
	local inner_offset = Geom:new{x = 0, y = 0}

	-- draw surrounding space, if any
	if self.ui.dimen.h > self.visible_area.h then
		inner_offset.y = (self.ui.dimen.h - self.visible_area.h) / 2
		bb:paintRect(x, y, self.ui.dimen.w, inner_offset.y, self.outer_page_color)
		bb:paintRect(x, y + self.ui.dimen.h - inner_offset.y - 1, self.ui.dimen.w, inner_offset.y + 1, self.outer_page_color)
	end
	if self.ui.dimen.w > self.visible_area.w then
		inner_offset.x = (self.ui.dimen.w - self.visible_area.w) / 2
		bb:paintRect(x, y, inner_offset.x, self.ui.dimen.h, self.outer_page_color)
		bb:paintRect(x + self.ui.dimen.w - inner_offset.x - 1, y, inner_offset.x + 1, self.ui.dimen.h, self.outer_page_color)
	end

	-- draw content
	if self.ui.document.info.has_pages then
		self.ui.document:drawPage(
			bb,
			x + inner_offset.x,
			y + inner_offset.y,
			self.visible_area,
			self.state.page,
			self.state.zoom,
			self.state.rotation)
	else
		self.ui.document:drawCurrentView(
			bb,
			x + inner_offset.x,
			y + inner_offset.y,
			self.visible_area,
			self.state.pos)
	end
end

function ReaderView:recalculate()
	if self.ui.document.info.has_pages then
		local page_size = self.ui.document:getPageDimensions(self.state.page, self.state.zoom, self.state.rotation)
		-- TODO: bbox
		self.page_area = page_size

		-- reset our size
		self.visible_area:setSizeTo(self.dimen)
		-- and recalculate it according to page size
		self.visible_area:offsetWithin(self.page_area, 0, 0)
	else
		self.visible_area:setSizeTo(self.dimen)
	end
	-- flag a repaint
	UIManager:setDirty(self.dialog)
end

function ReaderView:PanningUpdate(dx, dy)
	DEBUG("pan by", dx, dy)
	local old = self.visible_area:copy()
	self.visible_area:offsetWithin(self.page_area, dx, dy)
	if self.visible_area ~= old then
		-- flag a repaint
		UIManager:setDirty(self.dialog)
		DEBUG(self.page_area)
		DEBUG(self.visible_area)
	end
	return true
end

function ReaderView:onSetDimensions(dimensions)
	self.dimen = dimensions
	-- recalculate view
	self:recalculate()
end

function ReaderView:onPageUpdate(new_page_no)
	self.state.page = new_page_no
	self:recalculate()
end

function ReaderView:onPosUpdate(new_pos)
	self.state.pos = new_pos
	self:recalculate()
end

function ReaderView:ZoomUpdate(zoom)
	self.state.zoom = zoom
	self:recalculate()
end

function ReaderView:onRotationUpdate(rotation)
	self.state.rotation = rotation
	self:recalculate()
end

