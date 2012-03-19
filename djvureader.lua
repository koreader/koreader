require "unireader"

DJVUReader = UniReader:new{}

-- open a DJVU file and its settings store
-- DJVU does not support password yet
function DJVUReader:open(filename)
	self.doc = djvu.openDocument(filename)
	return self:loadSettings(filename)
end
