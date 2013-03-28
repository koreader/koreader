ReaderZooming = InputContainer:new{
	zoom = 1.0,
	-- default to nil so we can trigger ZoomModeUpdate events on start up
	zoom_mode = nil,
	DEFAULT_ZOOM_MODE = "page",
	current_page = 1,
	rotation = 0
}

function ReaderZooming:init()
	if Device:hasKeyboard() then
		self.key_events = {
			ZoomIn = {
				{ "Shift", Input.group.PgFwd },
				doc = "zoom in",
				event = "Zoom", args = "in"
			},
			ZoomOut = {
				{ "Shift", Input.group.PgBack },
				doc = "zoom out",
				event = "Zoom", args = "out"
			},
			ZoomToFitPage = {
				{ "A" },
				doc = "zoom to fit page",
				event = "SetZoomMode", args = "page"
			},
			ZoomToFitContent = {
				{ "Shift", "A" },
				doc = "zoom to fit content",
				event = "SetZoomMode", args = "content"
			},
			ZoomToFitPageWidth = {
				{ "S" },
				doc = "zoom to fit page width",
				event = "SetZoomMode", args = "pagewidth"
			},
			ZoomToFitContentWidth = {
				{ "Shift", "S" },
				doc = "zoom to fit content width",
				event = "SetZoomMode", args = "contentwidth"
			},
			ZoomToFitPageHeight = {
				{ "D" },
				doc = "zoom to fit page height",
				event = "SetZoomMode", args = "pageheight"
			},
			ZoomToFitContentHeight = {
				{ "Shift", "D" },
				doc = "zoom to fit content height",
				event = "SetZoomMode", args = "contentheight"
			},
		}
	end
	if Device:isTouchDevice() then
		self.ges_events = {
			Spread = {
				GestureRange:new{
					ges = "spread",
					range = Geom:new{
						x = 0, y = 0,
						w = Screen:getWidth(),
						h = Screen:getHeight(),
					}
				}
			},
			Pinch = {
				GestureRange:new{
					ges = "pinch",
					range = Geom:new{
						x = 0, y = 0,
						w = Screen:getWidth(),
						h = Screen:getHeight(),
					}
				}
			},
		}
	end
	self.ui.menu:registerToMainMenu(self)
end

function ReaderZooming:onReadSettings(config)
	-- @TODO config file from old code base uses globalzoom_mode
	-- instead of zoom_mode, we need to handle this imcompatibility
	-- 04.12 2012 (houqp)
	local zoom_mode = config:readSetting("zoom_mode")
	if not zoom_mode then
		zoom_mode = self.DEFAULT_ZOOM_MODE
	end
	self.ui:handleEvent(Event:new("SetZoomMode", zoom_mode))
end

function ReaderZooming:onCloseDocument()
	self.ui.doc_settings:saveSetting("zoom_mode", self.zoom_mode)
end

function ReaderZooming:onSpread(arg, ges)
	if ges.direction == "horizontal" then
		self:setZoomMode("contentwidth")
	elseif ges.direction == "vertical" then
		self:setZoomMode("contentheight")
	elseif ges.direction == "diagonal" then
		self:setZoomMode("content")
	end
	return true
end

function ReaderZooming:onPinch(arg, ges)
	if ges.direction == "diagonal" then
		self:setZoomMode("page")
	elseif ges.direction == "horizontal" then
		self:setZoomMode("pagewidth")
	elseif ges.direction == "vertical" then
		self:setZoomMode("pageheight")
	end
	return true
end

function ReaderZooming:onSetDimensions(dimensions)
	-- we were resized
	self.dimen = dimensions
	self:setZoom()
end

function ReaderZooming:onRotationUpdate(rotation)
	self.rotation = rotation
	self:setZoom()
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
	self.view:onZoomUpdate(self.zoom)
	return true
end

function ReaderZooming:onSetZoomMode(new_mode)
	self.view.zoom_mode = new_mode
	if self.zoom_mode ~= new_mode then
		DEBUG("setting zoom mode to", new_mode)
		self.zoom_mode = new_mode
		self:setZoom()
		self.ui:handleEvent(Event:new("ZoomModeUpdate", new_mode))
	end
end

function ReaderZooming:onPageUpdate(new_page_no)
	self.current_page = new_page_no
	self:setZoom()
end

function ReaderZooming:onHintPage()
	if not self.view.hinting then return true end
	if self.current_page < self.ui.document.info.number_of_pages then
		self.ui.document:hintPage(
			self.view.state.page + 1,
			self:getZoom(self.view.state.page + 1),
			self.view.state.rotation,
			self.view.state.gamma,
			self.view.render_mode)
	end
	return true
end

function ReaderZooming:getZoom(pageno)
	-- check if we're in bbox mode and work on bbox if that's the case
	local zoom = nil
	local page_size = {}
	if self.zoom_mode == "content"
	or self.zoom_mode == "contentwidth"
	or self.zoom_mode == "contentheight" then
		local ubbox_dimen = self.ui.document:getUsedBBoxDimensions(pageno, 1)
		--self.view:handleEvent(Event:new("BBoxUpdate", page_size))
		self.view:onBBoxUpdate(ubbox_dimen)
		page_size = ubbox_dimen
	else
		-- otherwise, operate on full page
		self.view:onBBoxUpdate(nil)
		page_size = self.ui.document:getNativePageDimensions(pageno)
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
			zoom = zoom_w
		else
			zoom = zoom_h
		end
	elseif self.zoom_mode == "contentwidth" or self.zoom_mode == "pagewidth" then
		zoom = zoom_w
	elseif self.zoom_mode == "contentheight" or self.zoom_mode == "pageheight" then
		zoom = zoom_h
	end
	return zoom
end

function ReaderZooming:setZoom()
	-- nothing to do in free zoom mode
	if self.zoom_mode == "free" then
		return
	end
	if not self.dimen then
		self.dimen = self.ui.dimen
	end
	self.zoom = self:getZoom(self.current_page)
	self.ui:handleEvent(Event:new("ZoomUpdate", self.zoom))
end

function ReaderZooming:genSetZoomModeCallBack(mode)
	return function()
		self:setZoomMode(mode)
	end
end

function ReaderZooming:setZoomMode(mode)
	self.ui:handleEvent(Event:new("SetZoomMode", mode))
	self.ui:handleEvent(Event:new("InitScrollPageStates"))
end

function ReaderZooming:addToMainMenu(tab_item_table)
	if self.ui.document.info.has_pages then
		table.insert(tab_item_table.typeset, {
			text = "Switch zoom mode",
			sub_item_table = {
				{
					text = "Zoom to fit content width",
					callback = self:genSetZoomModeCallBack("contentwidth")
				},
				{
					text = "Zoom to fit content height",
					callback = self:genSetZoomModeCallBack("contentheight")
				},
				{
					text = "Zoom to fit page width",
					callback = self:genSetZoomModeCallBack("pagewidth")
				},
				{
					text = "Zoom to fit page height",
					callback = self:genSetZoomModeCallBack("pageheight")
				},
				{
					text = "Zoom to fit content",
					callback = self:genSetZoomModeCallBack("content")
				},
				{
					text = "Zoom to fit page",
					callback = self:genSetZoomModeCallBack("page")
				},
			}
		})
	end
end
