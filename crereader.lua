require "unireader"
require "inputbox"

CREReader = UniReader:new{
	pos = 0,
	pan_overlap_vertical = 0,
}

function CREReader:init()
	self:addAllCommands()
	self:adjustCreReaderCommands()
end

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

function CREReader:getLastPageOrPos()
	return self.settings:readSetting("last_pos") or 0
end

function CREReader:saveLastPageOrPos()
	self.settings:savesetting("last_pos", self.pos)
end

function CREReader:setzoom(page, preCache)
	return
end

function CREReader:addJump(pos, notes)
end

function CREReader:goto(pos)
	local pos = math.min(pos, self.doc:GetFullHeight())
	pos = math.max(pos, 0)

	-- add to jump_stack, distinguish jump from normal page turn
	if self.pos and math.abs(self.pos - pos) > height then
		self:addJump(self.pos)
	end

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

-- used in CREReader:showMenu()
function CREReader:_drawReadingInfo()
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

function CREReader:adjustCreReaderCommands()
	-- delete commands
	self.commands:del(KEY_G, nil, "G")
	self.commands:del(KEY_J, nil, "J")
	self.commands:del(KEY_K, nil, "K")
	self.commands:del(KEY_Z, nil, "Z")
	self.commands:del(KEY_Z, MOD_SHIFT, "Z")
	self.commands:del(KEY_Z, MOD_ALT, "Z")
	self.commands:del(KEY_A, nil, "A")
	self.commands:del(KEY_A, MOD_SHIFT, "A")
	self.commands:del(KEY_A, MOD_ALT, "A")
	self.commands:del(KEY_S, nil, "S")
	self.commands:del(KEY_S, MOD_SHIFT, "S")
	self.commands:del(KEY_S, MOD_ALT, "S")
	self.commands:del(KEY_D, nil, "D")
	self.commands:del(KEY_D, MOD_SHIFT, "D")
	self.commands:del(KEY_D, MOD_ALT, "D")
	self.commands:del(KEY_F, nil, "F")
	self.commands:del(KEY_F, MOD_SHIFT, "F")
	self.commands:del(KEY_F, MOD_ALT, "F")

	-- overwrite commands
	self.commands:add(KEY_PGFWD, MOD_SHIFT_OR_ALT, ">",
		"increase font size",
		function(cr)
			cr.doc:zoomFont(1)
			cr:redrawCurrentPage()
		end
	)
	self.commands:add(KEY_PGBCK, MOD_SHIFT_OR_ALT, "<",
		"decrease font size",
		function(cr)
			cr.doc:zoomFont(-1)
			cr:redrawCurrentPage()
		end
	)
	local numeric_keydefs = {}
	for i=1,10 do 
		numeric_keydefs[i]=Keydef:new(KEY_1+i-1, nil, tostring(i%10)) 
	end
	self.commands:addGroup("[1..0]", numeric_keydefs,
		"jump to <key>*10% of document",
		function(cr, keydef)
			print('jump to position: '..
				math.floor(cr.doc:GetFullHeight()*(keydef.keycode-KEY_1)/9)..
				'/'..cr.doc:GetFullHeight())
			cr:goto(math.floor(cr.doc:GetFullHeight()*(keydef.keycode-KEY_1)/9))
		end
	)
end
