require "ui/widget"
require "ui/bbox"

PageCropDialog = VerticalGroup:new{
	ok_text = "OK",
	cancel_text = "Cancel",
	ok_callback = function() end,
	cancel_callback = function() end,
	button_width = math.floor(70*Screen:getDPI()/167),
}

function PageCropDialog:init()
	local horizontal_group = HorizontalGroup:new{}
	local ok_button = Button:new{
		text = self.ok_text,
		callback = self.ok_callback,
		width = self.button_width,
		bordersize = 2,
		radius = 7,
		text_font_face = "cfont",
		text_font_size = 20,
	}
	local cancel_button = Button:new{
		text = self.cancel_text,
		callback = self.cancel_callback,
		width = self.button_width,
		bordersize = 2,
		radius = 7,
		text_font_face = "cfont",
		text_font_size = 20,
	}
	local ok_container = RightContainer:new{
		dimen = Geom:new{ w = Screen:getWidth()*0.33, h = Screen:getHeight()/12},
		ok_button,
	}
	local cancel_container = LeftContainer:new{
		dimen = Geom:new{ w = Screen:getWidth()*0.33, h = Screen:getHeight()/12},
		cancel_button,
	}
	table.insert(horizontal_group, ok_container)
	table.insert(horizontal_group, HorizontalSpan:new{ width = Screen:getWidth()*0.34})
	table.insert(horizontal_group, cancel_container)
	self[2] = FrameContainer:new{
		horizontal_group,
		background = 0,
		bordersize = 0,
		padding = 0,
	}
end

ReaderCropping = InputContainer:new{}

function ReaderCropping:onPageCrop(mode)
	if mode == "auto" then return end
	self.ui:handleEvent(Event:new("CloseConfig"))
	-- backup original view dimen
	self.orig_view_dimen = Geom:new{w = self.view.dimen.w, h = self.view.dimen.h}
	DEBUG("backup view dimen", self.orig_view_dimen)
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
	self.ui:handleEvent(Event:new("SetDimensions", 
		Geom:new{w = Screen:getWidth(), h = Screen:getHeight()*11/12})
	)
	self.bbox_widget = BBoxWidget:new{
		ui = self.ui,
		view = self.view,
		document = self.document,
	}
	self.crop_dialog = PageCropDialog:new{
		self.bbox_widget,
		ok_callback = function() self:confirmPageCrop() end,
		cancel_callback = function() self:cancelPageCrop() end,
	}
	UIManager:show(self.crop_dialog)
	return true
end

function ReaderCropping:confirmPageCrop()
	--DEBUG("new bbox", new_bbox)
	UIManager:close(self.crop_dialog)
	local new_bbox = self.bbox_widget:getModifiedPageBBox()
	self.ui:handleEvent(Event:new("BBoxUpdate"), new_bbox)
	local pageno = self.view.state.page
	self.document.bbox[pageno] = new_bbox
	self.document.bbox[math.oddEven(pageno)] = new_bbox
	self:exitPageCrop(true)
	return true
end

function ReaderCropping:cancelPageCrop()
	UIManager:close(self.crop_dialog)
	self:exitPageCrop(false)
	return true
end

function ReaderCropping:exitPageCrop(confirmed)
	self.ui:handleEvent(Event:new("RestoreDimensions", self.orig_view_dimen))
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
	self.document.bbox = config:readSetting("bbox")
end

function ReaderCropping:onCloseDocument()
	self.ui.doc_settings:saveSetting("bbox", self.document.bbox)
end
