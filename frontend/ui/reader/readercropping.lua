--[[
BBoxWidget shows a bbox for page cropping
]]
BBoxWidget = InputContainer:new{
	page_bbox = nil,
	screen_bbox = nil,
	linesize = 2,
}

function BBoxWidget:getSize()
	return Geom:new{
		x = 0, y = 0,
		w = Screen:getWidth(),
		h = Screen:getHeight()
	}
end

function BBoxWidget:paintTo(bb, x, y)
	self.screen_bbox = self.screen_bbox or self:page_to_screen()
	local bbox = self.screen_bbox
	-- upper_left
	bb:invertRect(bbox.x0 + self.linesize, bbox.y0, bbox.x1 - bbox.x0, self.linesize)
	bb:invertRect(bbox.x0, bbox.y0, self.linesize, bbox.y1 - bbox.y0 + self.linesize)
	-- bottom_right
	bb:invertRect(bbox.x0 + self.linesize, bbox.y1, bbox.x1 - bbox.x0 - self.linesize, self.linesize)
	bb:invertRect(bbox.x1, bbox.y0 + self.linesize, self.linesize, bbox.y1 - bbox.y0)
end

-- transform page bbox to screen bbox
function BBoxWidget:page_to_screen()
	local bbox = {}
	local scale = self.crop.zoom
	local screen_offset = self.crop.screen_offset
	DEBUG("screen offset in page_to_screen", screen_offset)
	bbox.x0 = self.page_bbox.x0 * scale + screen_offset.x
	bbox.y0 = self.page_bbox.y0 * scale + screen_offset.y
	bbox.x1 = self.page_bbox.x1 * scale + screen_offset.x
	bbox.y1 = self.page_bbox.y1 * scale + screen_offset.y
	return bbox
end

-- transform screen bbox to page bbox
function BBoxWidget:screen_to_page()
	local bbox = {}
	local scale = self.crop.zoom
	local screen_offset = self.crop.screen_offset
	DEBUG("screen offset in screen_to_page", screen_offset)
	bbox.x0 = self.screen_bbox.x0 / scale - screen_offset.x
	bbox.y0 = self.screen_bbox.y0 / scale - screen_offset.y
	bbox.x1 = self.screen_bbox.x1 / scale - screen_offset.x
	bbox.y1 = self.screen_bbox.y1 / scale - screen_offset.y
	return bbox
end

function BBoxWidget:oddEven(number)
	if number % 2 == 1 then
		return "odd"
	else
		return "even"
	end
end

function BBoxWidget:init()
	if Device:isTouchDevice() then
		self.ges_events = {
			AdjustCrop = {
				GestureRange:new{
					ges = "tap",
					range = Geom:new{
						x = 0, y = 0,
						w = Screen:getWidth(),
						h = Screen:getHeight()
					}
				}
			},
			ConfirmCrop = {
				GestureRange:new{
					ges = "double_tap",
					range = Geom:new{
						x = 0, y = 0,
						w = Screen:getWidth(),
						h = Screen:getHeight()
					}
				}
			},
			CancelCrop = {
				GestureRange:new{
					ges = "hold_release",
					range = Geom:new{
						x = 0, y = 0,
						w = Screen:getWidth(),
						h = Screen:getHeight()
					}
				}
			},
		}
	end
end

function BBoxWidget:onGesture(ev)
	for name, gsseq in pairs(self.ges_events) do
		for _, gs_range in ipairs(gsseq) do
			--DEBUG("gs_range", gs_range)
			if gs_range:match(ev) then
				local eventname = gsseq.event or name
				return self:handleEvent(Event:new(eventname, ev.pos))
			end
		end
	end
end

function BBoxWidget:onAdjustCrop(pos)
	DEBUG("adjusting crop bbox with pos", pos)
	local bbox = self.screen_bbox
	local upper_left = Geom:new{ x = bbox.x0, y = bbox.y0}
	local bottom_right = Geom:new{ x = bbox.x1, y = bbox.y1}
	if upper_left:distance(pos) < bottom_right:distance(pos) then
		upper_left.x = pos.x
		upper_left.y = pos.y
	else
		bottom_right.x = pos.x
		bottom_right.y = pos.y
	end
	self.screen_bbox = {
		x0 = upper_left.x, 
		y0 = upper_left.y,
		x1 = bottom_right.x,
		y1 = bottom_right.y
	}
	UIManager.repaint_all = true
end

function BBoxWidget:onConfirmCrop()
	self.page_bbox = self:screen_to_page()
	--DEBUG("new bbox", self.page_bbox)
	UIManager:close(self)
	self.ui:handleEvent(Event:new("BBoxUpdate"), self.page_bbox)
	self.document.bbox[self.pageno] = self.page_bbox
	self.document.bbox[self:oddEven(self.pageno)] = self.page_bbox
	self.ui:handleEvent(Event:new("SetZoomMode", self.orig_zoom_mode))
	self.document.configurable.text_wrap = self.orig_reflow_mode
	UIManager.repaint_all = true
end

ReaderCropping = InputContainer:new{}

function ReaderCropping:onPageCrop(mode)
	if mode == "auto" then return end
	local orig_reflow_mode = self.document.configurable.text_wrap
	self.document.configurable.text_wrap = 0
	self.ui:handleEvent(Event:new("CloseConfig"))
	self.ui:handleEvent(Event:new("SetZoomMode", "page"))
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
	--DEBUG("offset updated to", screen_offset)
	self.screen_offset = screen_offset
end

function ReaderCropping:onSetZoomMode(mode)
	if self.orig_zoom_mode == nil then
		--DEBUG("backup zoom mode", mode)
		self.orig_zoom_mode = mode
	end
end

function ReaderCropping:onReadSettings(config)
	local bbox = config:readSetting("bbox")
	self.document.bbox = bbox
	DEBUG("read document bbox", self.document.bbox)
end

function ReaderCropping:onCloseDocument()
	self.ui.doc_settings:saveSetting("bbox", self.document.bbox)
end
