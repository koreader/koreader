require "unireader"
require "inputbox"

PDFReader = UniReader:new{
	filename -- stores the absolute pathname of the open file
}

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
	self.filename = filename
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
	--Debug("## page:getPageText "..dump(text)) -- performance impact on device
	page:close()
	return text
end

function PDFReader:getPageLinks(pageno)
	local ok, page = pcall(self.doc.openPage, self.doc, pageno)
	if not ok then
		-- TODO: error handling
		return nil
	end
	local links = page:getPageLinks()
	Debug("## page:getPageLinks ", links)
	page:close()
	return links
end

function PDFReader:init()
	self:addAllCommands()
	self:adjustCommands()
end

function PDFReader:adjustCommands()
	self.commands:add(KEY_S, MOD_ALT, "S",
		"save all attachments on this page",
		function(self)
			self:saveAttachments()
	end) 
end

-- saves all attachments on the current page in the same directory
-- as the file itself (see extr.c utility)
function PDFReader:saveAttachments()
	InfoMessage:inform("Saving attachments...", DINFO_NODELAY, 1, MSG_AUX)
	local p = io.popen('./extr "'..self.filename..'" '..tostring(self.pageno), "r")
	local count = p:read("*a")
	p:close()
	if count ~= "" then
		-- double braces are needed because string.gsub() returns more than one value
		count = tonumber((string.gsub(count, "[\n\r]+", "")))
		if count == 0 then
			InfoMessage:inform("No attachments found ", DINFO_DELAY, 1, MSG_WARN)
		else
			InfoMessage:inform(count.." attachment"..(count > 1 and "s" or "").." saved ",
				DINFO_DELAY, 1, MSG_AUX)
		end
	else
		InfoMessage:inform("Failed to save attachments ", DINFO_DELAY, 1, MSG_WARN)
	end
	-- needed because of inform(..DINFO_NODELAY..) above
	self:redrawCurrentPage()
end
