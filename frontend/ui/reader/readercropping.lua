require "ui/bbox"

ReaderCropping = InputContainer:new{}

function ReaderCropping:onPageCrop(mode)
	if mode == "auto" then return end
	self.ui:handleEvent(Event:new("CloseConfig"))
	-- backup original zoom mode as cropping use "page" zoom mode
	self.orig_zoom_mode = self.view.zoom_mode
	-- backup original reflow mode as cropping use non-reflow mode
	self.orig_reflow_mode = self.document.configurable.text_wrap
	if self.orig_reflow_mode == 1 then
		self.document.configurable.text_wrap = 0
		-- if we are in reflow mode, then we are already in page
		-- mode, just force readerview to recalculate visible_area
		self.view:recalculate()
	else
		self.ui:handleEvent(Event:new("SetZoomMode", "page", "cropping"))
	end
	self.crop_bbox = BBoxWidget:new{
		ui = self.ui,
		view = self.view,
		document = self.document,
	}
	UIManager:show(self.crop_bbox)
	return true
end

function ReaderCropping:onConfirmPageCrop(new_bbox)
	--DEBUG("new bbox", new_bbox)
	UIManager:close(self.crop_bbox)
	self.ui:handleEvent(Event:new("BBoxUpdate"), new_bbox)
	local pageno = self.view.state.page
	self.document.bbox[pageno] = new_bbox
	self.document.bbox[math.oddEven(pageno)] = new_bbox
	self:exitPageCrop(true)
	return true
end

function ReaderCropping:onCancelPageCrop()
	UIManager:close(self.crop_bbox)
	self:exitPageCrop(false)
	return true
end

function ReaderCropping:exitPageCrop(confirmed)
	self.document.configurable.text_wrap = self.orig_reflow_mode
	self.view:recalculate()
	-- Exiting should have the same look and feel with entering.
	if self.orig_reflow_mode == 1 then
		-- restore original reflow mode
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
end

function ReaderCropping:onReadSettings(config)
	local bbox = config:readSetting("bbox")
	self.document.bbox = bbox
	--DEBUG("read document bbox", self.document.bbox)
end

function ReaderCropping:onCloseDocument()
	self.ui.doc_settings:saveSetting("bbox", self.document.bbox)
end
