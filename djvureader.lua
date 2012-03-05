require "unireader"

DJVUReader = UniReader:new{
	newDC = function()
		print("djvu.newDC")
		return djvu.newDC()
	end,
}

function DJVUReader:init()
	self.nulldc = self.newDC()
end

-- open a DJVU file and its settings store
function DJVUReader:open(filename)
	self.doc = djvu.openDocument(filename)
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

--set viewer state according to zoom state
function DJVUReader:setzoom(page)
	local dc = self.newDC()
	local pwidth, pheight = page:getSize(self.nulldc)

	if self.globalzoommode == self.ZOOM_FIT_TO_PAGE then
		self.globalzoom = width / pwidth
		self.offset_x = 0
		self.offset_y = (height - (self.globalzoom * pheight)) / 2
		if height / pheight < self.globalzoom then
			self.globalzoom = height / pheight
			print(width, (self.globalzoom * pwidth))
			self.offset_x = (width - (self.globalzoom * pwidth)) / 2
			self.offset_y = 0
		end
	elseif self.globalzoommode == self.ZOOM_FIT_TO_PAGE_WIDTH then
		self.globalzoom = width / pwidth
		self.offset_x = 0
		self.offset_y = (height - (self.globalzoom * pheight)) / 2
	elseif self.globalzoommode == self.ZOOM_FIT_TO_PAGE_HEIGHT then
		self.globalzoom = height / pheight
		self.offset_x = (width - (self.globalzoom * pwidth)) / 2
		self.offset_y = 0
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
