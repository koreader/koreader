local Document = require("document/document")
local DrawContext = require("ffi/drawcontext")

local PicDocument = Document:new{
	_document = false,
	dc_null = DrawContext.new()
}

function PicDocument:init()
	require "libs/libkoreader-pic"
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

function PicDocument:register(registry)
	registry:addProvider("jpeg", "application/jpeg", self)
	registry:addProvider("jpg", "application/jpeg", self)
end

return PicDocument
