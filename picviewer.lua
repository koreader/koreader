require "unireader"

PICViewer = UniReader:new{}

function PICViewer:setDefaults()
	self.show_overlap_enable = false
	self.show_links_enable = false
end

function PICViewer:open(filename)
	ok, self.doc = pcall(pic.openDocument, filename)
	if not ok then
		return ok, self.doc
	end
	return ok
end

function PICViewer:_drawReadingInfo()
	local width = G_width
	local face = Font:getFace("rifont", 20)
	local page_width, page_height, page_components = self.doc:getOriginalPageSize()

	-- display memory, time, battery and image info on top of page
	fb.bb:paintRect(0, 0, width, 40+6*2, 0)
	renderUtf8Text(fb.bb, 10, 15+6, face,
		"M: "..
		math.ceil( self.cache_current_memsize / 1024 ).."/"..math.ceil( self.cache_max_memsize / 1024 ).."k, "..
		math.ceil( self.doc:getCacheSize() / 1024 ).."/"..math.ceil( self.cache_document_size / 1024 ).."k", true)
	local txt = os.date("%a %d %b %Y %T").." ["..BatteryLevel().."]"
	local w = sizeUtf8Text(0, width, face, txt, true).x
	renderUtf8Text(fb.bb, width - w - 10, 15+6, face, txt, true)
	renderUtf8Text(fb.bb, 10, 15+6+22, face,
		"Gm:"..string.format("%.1f",self.globalgamma)..", "..
		tostring(page_width).."x"..tostring(page_height).."x"..tostring(page_components)..", "..
		string.format("%.1fx", self.globalzoom), true)
end
