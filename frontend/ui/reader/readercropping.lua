require "ui/bbox"

ReaderCropping = InputContainer:new{}

function ReaderCropping:onPageCrop(mode)
	if mode == "auto" then return end
	self.orig_reflow_mode = self.document.configurable.text_wrap
	self.ui:handleEvent(Event:new("CloseConfig"))
	self.cropping_offset = true
	if self.orig_reflow_mode == 1 then
		self.document.configurable.text_wrap = 0
		-- if we are in reflow mode, then we are already in page
		-- mode, just force readerview to recalculate visible_area
		self.view:recalculate()
	else
		self.ui:handleEvent(Event:new("SetZoomMode", "page", "cropping"))
	end
	local ubbox = self.document:getPageBBox(self.current_page)
	--DEBUG("used page bbox", ubbox)
	self.crop_bbox = BBoxWidget:new{
		page_bbox = ubbox,
		ui = self.ui,
		crop = self,
		document = self.document,
		pageno = self.current_page,
	}
	UIManager:show(self.crop_bbox)
	return true
end

function ReaderCropping:onExitPageCrop(confirmed)
	self.document.configurable.text_wrap = self.orig_reflow_mode
	self.view:recalculate()
	-- Exiting should have the same look and feel with entering.
	if self.orig_reflow_mode == 1 then
		self.document.configurable.text_wrap = 1
		self.view:recalculate()
	else
		if confirmed then
			-- if original zoom mode is not "content", set zoom mode to "content"
			self.ui:handleEvent(Event:new("SetZoomMode", self.orig_zoom_mode:find("content") and self.orig_zoom_mode or "content"))
		else
			self.ui:handleEvent(Event:new("SetZoomMode", self.orig_zoom_mode))
		end
	end
	UIManager.repaint_all = true
	return true
end

function ReaderCropping:onPageUpdate(page_no)
	--DEBUG("page updated to", page_no)
	self.current_page = page_no
end

function ReaderCropping:onZoomUpdate(zoom)
	--DEBUG("zoom updated to", zoom)
	self.zoom = zoom
end

function ReaderCropping:onScreenOffsetUpdate(screen_offset)
	if self.cropping_offset then
		--DEBUG("offset updated to", screen_offset)
		self.screen_offset = screen_offset
		self.cropping_offset = false
	end
end

function ReaderCropping:onSetZoomMode(mode, orig)
	if orig ~= "cropping" and mode then
		--DEBUG("backup zoom mode", mode)
		self.orig_zoom_mode = mode
	end
end

function ReaderCropping:onReadSettings(config)
	local bbox = config:readSetting("bbox")
	self.document.bbox = bbox
	--DEBUG("read document bbox", self.document.bbox)
end

function ReaderCropping:onCloseDocument()
	self.ui.doc_settings:saveSetting("bbox", self.document.bbox)
end
