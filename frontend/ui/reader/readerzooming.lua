ReaderZooming = InputContainer:new{
	key_events = {
		ZoomIn = { { "Shift", Input.group.PgFwd }, doc = "zoom in", event = "Zoom", args = "in" },
		ZoomOut = { { "Shift", Input.group.PgBack }, doc = "zoom out", event = "Zoom", args = "out" },
		ZoomToFitPage = { {"A"}, doc = "zoom to fit page", event = "SetZoomMode", args = "page" },
		ZoomToFitContent = { {"Shift", "A"}, doc = "zoom to fit content", event = "SetZoomMode", args = "content" },
		ZoomToFitPageWidth = { {"S"}, doc = "zoom to fit page width", event = "SetZoomMode", args = "pagewidth" },
		ZoomToFitContentWidth = { {"Shift", "S"}, doc = "zoom to fit content width", event = "SetZoomMode", args = "contentwidth" },
		ZoomToFitPageHeight = { {"D"}, doc = "zoom to fit page height", event = "SetZoomMode", args = "pageheight" },
		ZoomToFitContentHeight = { {"Shift", "D"}, doc = "zoom to fit content height", event = "SetZoomMode", args = "contentheight" },
	},
	zoom = 1.0,
	zoom_mode = "free",
	current_page = 1,
	rotation = 0
}

function ReaderZooming:onSetDimensions(dimensions)
	-- we were resized
	self.dimen = dimensions
end

function ReaderZooming:onRotationUpdate(rotation)
	self.rotation = rotation
	self:setZoom()
end

function ReaderZooming:setZoom()
	-- nothing to do in free zoom mode
	if self.zoom_mode == "free" then
		return
	end
	-- check if we're in bbox mode and work on bbox if that's the case
	local page_size = {}
	if self.zoom_mode == "content" or self.zoom_mode == "contentwidth" or self.zoom_mode == "content_height" then
		-- TODO: enable this, still incomplete
		page_size = self.ui.document:getUsedBBox(self.current_page)
		self.view:handleEvent(Event:new("BBoxUpdate", page_size))
	else
		-- otherwise, operate on full page
		page_size = self.ui.document:getNativePageDimensions(self.current_page)
	end
	-- calculate zoom value:
	local zoom_w = self.dimen.w / page_size.w
	local zoom_h = self.dimen.h / page_size.h
	if self.rotation % 180 ~= 0 then
		-- rotated by 90 or 270 degrees
		zoom_w = self.dimen.w / page_size.h
		zoom_h = self.dimen.h / page_size.w
	end
	if self.zoom_mode == "content" or self.zoom_mode == "page" then
		if zoom_w < zoom_h then
			self.zoom = zoom_w
		else
			self.zoom = zoom_h
		end
	elseif self.zoom_mode == "contentwidth" or self.zoom_mode == "pagewidth" then
		self.zoom = zoom_w
	elseif self.zoom_mode == "contentheight" or self.zoom_mode == "pageheight" then
		self.zoom = zoom_h
	end
	self.view:ZoomUpdate(self.zoom)
end

function ReaderZooming:onZoom(direction)
	DEBUG("zoom", direction)
	if direction == "in" then
		self.zoom = self.zoom * 1.333333
	elseif direction == "out" then
		self.zoom = self.zoom * 0.75
	end
	DEBUG("zoom is now at", self.zoom)
	self:onSetZoomMode("free")
	self.view:ZoomUpdate(self.zoom)
	return true
end

function ReaderZooming:onSetZoomMode(what)
	if self.zoom_mode ~= what then
		DEBUG("setting zoom mode to", what)
		self.zoom_mode = what
		self:setZoom()
	end
	return true
end

function ReaderZooming:onPageUpdate(new_page_no)
	self.current_page = new_page_no
	self:setZoom()
end
