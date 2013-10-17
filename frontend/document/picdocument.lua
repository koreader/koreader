
PicDocument = Document:new{
	_document = false,
	dc_null = DrawContext.new(),
}

function PicDocument:init()
	ok, self._document = pcall(pic.openDocument, self.file)
	if not ok then
		self.error_message = "failed to open jpeg image"
		return
	end

	self.info.has_pages = true
	self.info.configurable = false

	self:readMetadata()
end

function PicDocument:readMetadata()
	self.info.number_of_pages = 1
end


DocumentRegistry:addProvider("jpeg", "application/jpeg", PicDocument)
DocumentRegistry:addProvider("jpg", "application/jpeg", PicDocument)
