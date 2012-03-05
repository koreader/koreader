require "unireader"

DJVUReader = UniReader:new{
	newDC = function()
		print("djvu.newDC")
		return djvu.newDC()
	end,
}

function DJVUReader:init()
	self.nulldc = self.newDC()
end

-- open a DJVU file and its settings store
-- DJVU does not support password yet
function DJVUReader:open(filename)
	self.doc = djvu.openDocument(filename)
	return self:loadSettings(filename)
end
