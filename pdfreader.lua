require "unireader"

PDFReader = UniReader:new{
	newDC = function()
		print("pdf.newDC")
		return pdf.newDC()
	end,
}

function PDFReader:init()
	self.nulldc = self.newDC();
end

-- open a PDF file and its settings store
function PDFReader:open(filename, password)
	self.doc = pdf.openDocument(filename, password or "")
	return self:loadSettings(filename)
end
