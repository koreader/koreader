require "ui/bbox"

ReaderCropping = InputContainer:new{}

function ReaderCropping:onPageCrop(mode)
	if mode == "auto" then return end
	local orig_reflow_mode = self.document.configurable.text_wrap
	self.document.configurable.text_wrap = 0
	self.ui:handleEvent(Event:new("CloseConfig"))
	self.cropping_zoommode = true
	self.cropping_offset = true
	-- we are already in page mode, tell ReaderView to recalculate stuff
	-- for non-reflow mode
	self.view:recalculate()
	self.cropping_zoommode = false
	local ubbox = self.document:getPageBBox(self.current_page)
	--DEBUG("used page bbox", ubbox)
	self.crop_bbox = BBoxWidget:new{
		page_bbox = ubbox,
		ui = self.ui,
		crop = self,
		document = self.document,
		pageno = self.current_page,
		orig_zoom_mode = self.orig_zoom_mode,
		orig_reflow_mode = orig_reflow_mode,
	}
	UIManager:show(self.crop_bbox)
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
		DEBUG("offset updated to", screen_offset)
		self.screen_offset = screen_offset
		self.cropping_offset = false
	end
end

function ReaderCropping:onSetZoomMode(mode)
	if not self.cropping_zoommode then
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
