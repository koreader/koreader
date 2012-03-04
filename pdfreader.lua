require "unireader"

PDFReader = UniReader:new{}


function PDFReader:init()
	self.nulldc = pdf.newDC()
end

-- open a PDF file and its settings store
function PDFReader:open(filename, password)
	self.doc = pdf.openDocument(filename, password or "")
	if self.doc ~= nil then
		self.settings = DocSettings:open(filename)
		local gamma = self.settings:readsetting("gamma")
		if gamma then
			self.globalgamma = gamma
		end
		return true
	end
	return false
end

-- set viewer state according to zoom state
function PDFReader:setzoom(page)
	local dc = pdf.newDC()
	local pwidth, pheight = page:getSize(self.nulldc)

	if self.globalzoommode == self.ZOOM_FIT_TO_PAGE
	or self.globalzoommode == self.ZOOM_FIT_TO_CONTENT then
		self.globalzoom = width / pwidth
		self.offset_x = 0
		self.offset_y = (height - (self.globalzoom * pheight)) / 2
		if height / pheight < self.globalzoom then
			self.globalzoom = height / pheight
			self.offset_x = (width - (self.globalzoom * pwidth)) / 2
			self.offset_y = 0
		end
	elseif self.globalzoommode == self.ZOOM_FIT_TO_PAGE_WIDTH
	or self.globalzoommode == self.ZOOM_FIT_TO_CONTENT_WIDTH then
		self.globalzoom = width / pwidth
		self.offset_x = 0
		self.offset_y = (height - (self.globalzoom * pheight)) / 2
	elseif self.globalzoommode == self.ZOOM_FIT_TO_PAGE_HEIGHT
	or self.globalzoommode == self.ZOOM_FIT_TO_CONTENT_HEIGHT then
		self.globalzoom = height / pheight
		self.offset_x = (width - (self.globalzoom * pwidth)) / 2
		self.offset_y = 0
	end
	if self.globalzoommode == self.ZOOM_FIT_TO_CONTENT then
		local x0, y0, x1, y1 = page:getUsedBBox()
		if (x1 - x0) < pwidth then
			self.globalzoom = width / (x1 - x0)
			self.offset_x = -1 * x0 * self.globalzoom
			self.offset_y = -1 * y0 * self.globalzoom + (height - (self.globalzoom * (y1 - y0))) / 2
			if height / (y1 - y0) < self.globalzoom then
				self.globalzoom = height / (y1 - y0)
				self.offset_x = -1 * x0 * self.globalzoom + (width - (self.globalzoom * (x1 - x0))) / 2
				self.offset_y = -1 * y0 * self.globalzoom
			end
		end
	elseif self.globalzoommode == self.ZOOM_FIT_TO_CONTENT_WIDTH then
		local x0, y0, x1, y1 = page:getUsedBBox()
		if (x1 - x0) < pwidth then
			self.globalzoom = width / (x1 - x0)
			self.offset_x = -1 * x0 * self.globalzoom
			self.offset_y = -1 * y0 * self.globalzoom + (height - (self.globalzoom * (y1 - y0))) / 2
		end
	elseif self.globalzoommode == self.ZOOM_FIT_TO_CONTENT_HEIGHT then
		local x0, y0, x1, y1 = page:getUsedBBox()
		if (y1 - y0) < pheight then
			self.globalzoom = height / (y1 - y0)
			self.offset_x = -1 * x0 * self.globalzoom + (width - (self.globalzoom * (x1 - x0))) / 2
			self.offset_y = -1 * y0 * self.globalzoom
		end
	elseif self.globalzoommode == self.ZOOM_FIT_TO_CONTENT_HALF_WIDTH then
		local x0, y0, x1, y1 = page:getUsedBBox()
		self.globalzoom = width / (x1 - x0 + self.pan_margin)
		self.offset_x = -1 * x0 * self.globalzoom * 2 + self.pan_margin
		self.globalzoom = height / (y1 - y0)
		self.offset_y = -1 * y0 * self.globalzoom * 2 + self.pan_margin
		self.globalzoom = width / (x1 - x0 + self.pan_margin) * 2
		print("column mode offset:"..self.offset_x.."*"..self.offset_y.." zoom:"..self.globalzoom);
		self.globalzoommode = self.ZOOM_BY_VALUE -- enable pan mode
		self.pan_x = self.offset_x
		self.pan_y = self.offset_y
		self.pan_by_page = true
	end

	dc:setZoom(self.globalzoom)
	-- record globalzoom for manual zoom in/out
	self.globalzoom_orig = self.globalzoom

	dc:setRotate(self.globalrotate);
	dc:setOffset(self.offset_x, self.offset_y)
	self.fullwidth, self.fullheight = page:getSize(dc)
	self.min_offset_x = fb.bb:getWidth() - self.fullwidth
	self.min_offset_y = fb.bb:getHeight() - self.fullheight
	if(self.min_offset_x > 0) then
		self.min_offset_x = 0
	end
	if(self.min_offset_y > 0) then
		self.min_offset_y = 0
	end

	-- set gamma here, we don't have any other good place for this right now:
	if self.globalgamma ~= self.GAMMA_NO_GAMMA then
		print("gamma correction: "..self.globalgamma)
		dc:setGamma(self.globalgamma)
	end
	return dc
end

