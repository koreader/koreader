require "unireader"
require "inputbox"

PDFReader = UniReader:new{}

-- open a PDF file and its settings store
function PDFReader:open(filename)
	-- muPDF manages its own cache, set second parameter
	-- to the maximum size you want it to grow
	local ok
	ok, self.doc = pcall(pdf.openDocument, filename, self.cache_document_size)
	if not ok then
		return false, self.doc -- will contain error message
	end
	if self.doc:needsPassword() then
		local password = InputBox:input(G_height-100, 100, "Pass:")
		if not password or not self.doc:authenticatePassword(password) then
			self.doc:close()
			self.doc = nil
			return false, "wrong or missing password"
		end
		-- password wrong or not entered
	end
	local ok, err = pcall(self.doc.getPages, self.doc)
	if not ok then
		-- for PDFs, they might trigger errors later when accessing page tree
		self.doc:close()
		self.doc = nil
		return false, "damaged page tree"
	end
	return true
end

----------------------------------------------------
-- highlight support 
----------------------------------------------------
function PDFReader:getText(pageno)
	local ok, page = pcall(self.doc.openPage, self.doc, pageno)
	if not ok then
		-- TODO: error handling
		return nil
	end
	local text = page:getPageText()
	--debug("## page:getPageText "..dump(text)) -- performance impact on device
	page:close()
	return text
end
