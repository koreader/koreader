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

function CREReader:setzoom(page, preCache)
	return
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

-- used in UniReader:showMenu()
function UniReader:_drawReadingInfo()
	local ypos = height - 50
	local load_percent = (self.pos / self.doc:GetFullHeight())

	fb.bb:paintRect(0, ypos, width, 50, 0)

	ypos = ypos + 15
	local face, fhash = Font:getFaceAndHash(22)
	local cur_section = self:getTocTitleByPage(self.pos)
	if cur_section ~= "" then
		cur_section = "Section: "..cur_section
	end
	renderUtf8Text(fb.bb, 10, ypos+6, face, fhash,
		"Position: "..math.floor((load_percent*100)).."%"..
		"    "..cur_section, true)

	ypos = ypos + 15
	blitbuffer.progressBar(fb.bb, 10, ypos, width-20, 15,
							5, 4, load_percent, 8)
end

function CREReader:nextView()
	return self.pos + height - self.pan_overlap_vertical
end

function CREReader:prevView()
	return self.pos - height + self.pan_overlap_vertical
end
