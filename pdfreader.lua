require "unireader"

PDFReader = UniReader:new{}

-- open a PDF file and its settings store
function PDFReader:open(filename, password)
	self.doc = pdf.openDocument(filename, password or "")
	return self:loadSettings(filename)
end
