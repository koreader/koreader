require "unireader"
require "inputbox"

CREReader = UniReader:new{
	pos = 0,
	pan_overlap_vertical = 0,
}

-- open a CREngine supported file and its settings store
function CREReader:open(filename)
	local ok
	local file_type = string.lower(string.match(filename, ".+%.([^.]+)"))
	local style_sheet = "./data/"..file_type..".css"
	ok, self.doc = pcall(cre.openDocument, filename, style_sheet, 
						width, height)
	if not ok then
		return false, self.doc -- will contain error message
	end

	return true
end

function CREReader:goto(pos)
	local pos = math.min(pos, self.doc:GetFullHeight())
	pos = math.max(pos, 0)
	self.doc:gotoPos(pos)
	self.doc:drawCurrentPage(self.nulldc, fb.bb)

	if self.rcount == self.rcountmax then
		print("full refresh")
		self.rcount = 1
		fb:refresh(0)
	else
		print("partial refresh")
		self.rcount = self.rcount + 1
		fb:refresh(1)
	end

	self.pos = pos
	self.pageno = self.doc:getCurrentPage()
end

function CREReader:redrawCurrentPage()
	self:goto(self.pos)
end

function CREReader:getTocTitleByPage(page)
	return ""
end

function CREReader:nextView()
	return self.pos + height - self.pan_overlap_vertical
end

function CREReader:prevView()
	return self.pos - height + self.pan_overlap_vertical
end
