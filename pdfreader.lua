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
