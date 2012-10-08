require "unireader"

PICViewer = UniReader:new{}

function PICViewer:open(filename)
	ok, self.doc = pcall(pic.openDocument, filename)
	if not ok then
		return ok, self.doc
	end
	return ok
end
