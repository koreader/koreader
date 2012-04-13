require "font"
require "unireader"
require "inputbox"
require "selectmenu"

CREReader = UniReader:new{
	pos = nil,
	percent = 0,

	gamma_index = 15,
	font_face = nil,

	line_space_percent = 100,
}

function CREReader:init()
	self:addAllCommands()
	self:adjustCreReaderCommands()
	-- we need to initialize the CRE font list
	local fonts = Font:getFontList()
	for _k, _v in ipairs(fonts) do
		local ok, err = pcall(cre.registerFont, Font.fontdir..'/'.._v)
		if not ok then
			print(err)
		end
	end
end

-- open a CREngine supported file and its settings store
function CREReader:open(filename)
	local ok
	local file_type = string.lower(string.match(filename, ".+%.([^.]+)"))
	-- these two format use the same css file
	if file_type == "html" then
		file_type = "htm"
	end
	local style_sheet = "./data/"..file_type..".css"
	ok, self.doc = pcall(cre.openDocument, filename, style_sheet, 
						G_width, G_height)
	if not ok then
		return false, self.doc -- will contain error message
	end

	self.doc:setDefaultInterlineSpace(self.line_space_percent)

	return true
end

----------------------------------------------------
-- setting related methods
----------------------------------------------------
function CREReader:loadSpecialSettings()
	local font_face = self.settings:readSetting("font_face")
	self.font_face = font_face or "FreeSerif"
	self.doc:setFontFace(self.font_face)

	local gamma_index = self.settings:readSetting("gamma_index")
	self.gamma_index = gamma_index or self.gamma_index
	cre.setGammaIndex(self.gamma_index)

	local line_space_percent = self.settings:readSetting("line_space_percent")
	self.line_space_percent = line_space_percent or self.line_space_percent
end

function CREReader:getLastPageOrPos()
	local last_percent = self.settings:readSetting("last_percent") 
	if last_percent then
		return math.floor((last_percent * self.doc:getFullHeight()) / 10000)
	else
		return 0
	end
end

function CREReader:saveSpecialSettings()
	self.settings:savesetting("font_face", self.font_face)
	self.settings:savesetting("gamma_index", self.gamma_index)
	self.settings:savesetting("line_space_percent", self.line_space_percent)
end

function CREReader:saveLastPageOrPos()
	self.settings:savesetting("last_percent", self.percent)
end

----------------------------------------------------
-- render related methods
----------------------------------------------------
-- we don't need setzoom in CREReader
function CREReader:setzoom(page, preCache)
	return
end

function CREReader:redrawCurrentPage()
	self:goto(self.pos)
end

-- there is no zoom mode in CREReader
function CREReader:setGlobalZoomMode()
	return
end

----------------------------------------------------
-- goto related methods
----------------------------------------------------
function CREReader:goto(pos, pos_type)
	local prev_xpointer = self.doc:getXPointer()
	local width, height = G_width, G_height

	if pos_type == "xpointer" then
		self.doc:gotoXPointer(pos)
		pos = self.doc:getCurrentPos()
	else -- pos_type is PERCENT * 100
		pos = math.min(pos, self.doc:getFullHeight() - height)
		pos = math.max(pos, 0)
		self.doc:gotoPos(pos)
	end

	-- add to jump_stack, distinguish jump from normal page turn
	-- NOTE:
	-- even though we have called gotoPos() or gotoXPointer() previously, 
	-- self.pos hasn't been updated yet here, so we can still make use of it.
	if self.pos and math.abs(self.pos - pos) > height then
		self:addJump(prev_xpointer)
	end

	self.doc:drawCurrentPage(self.nulldc, fb.bb)

	print("## self.show_overlap "..self.show_overlap)
	if self.show_overlap < 0 then
		fb.bb:dimRect(0,0, width, -self.show_overlap)
	elseif self.show_overlap > 0 then
		fb.bb:dimRect(0,height - self.show_overlap, width, self.show_overlap)
	end
	self.show_overlap = 0

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
	print("------", self.pos)
	self.pageno = self.doc:getCurrentPage()
	self.percent = self.doc:getCurrentPercent()
end

function CREReader:gotoPercent(percent)
	self:goto(percent * self.doc:getFullHeight() / 10000)
end

function CREReader:gotoTocEntry(entry)
	self:goto(entry.xpointer, "xpointer")
end

function CREReader:nextView()
	self.show_overlap = -self.pan_overlap_vertical
	return self.pos + G_height - self.pan_overlap_vertical
end

function CREReader:prevView()
	self.show_overlap = self.pan_overlap_vertical
	return self.pos - G_height + self.pan_overlap_vertical
end

----------------------------------------------------
-- jump stack related methods
----------------------------------------------------
function CREReader:isSamePage(p1, p2)
	return self.doc:getPageFromXPointer(p1) == self.doc:getPageFromXPointer(p2)
end

function CREReader:showJumpStack()
	local menu_items = {}
	print(dump(self.jump_stack))
	for k,v in ipairs(self.jump_stack) do
		table.insert(menu_items,
			v.datetime.." -> page "..
			(self.doc:getPageFromXPointer(v.page)).." "..v.notes)
	end
	jump_menu = SelectMenu:new{
		menu_title = "Jump Keeper      (current page: "..self.pageno..")",
		item_array = menu_items,
		no_item_msg = "No jump history.",
	}
	item_no = jump_menu:choose(0, fb.bb:getHeight())
	if item_no then
		local jump_item = self.jump_stack[item_no]
		self:goto(jump_item.page, "xpointer")
	else
		self:redrawCurrentPage()
	end
end

----------------------------------------------------
-- TOC related methods
----------------------------------------------------
function CREReader:getTocTitleOfCurrentPage()
	return self:getTocTitleByPage(self.percent)
end


----------------------------------------------------
-- menu related methods
----------------------------------------------------
-- used in CREReader:showMenu()
function CREReader:_drawReadingInfo()
	local ypos = G_height - 50
	local load_percent = self.percent/100

	fb.bb:paintRect(0, ypos, G_width, 50, 0)

	ypos = ypos + 15
	local face = Font:getFace("rifont", 22)
	local cur_section = self:getTocTitleOfCurrentPage()
	if cur_section ~= "" then
		cur_section = "Section: "..cur_section
	end
	renderUtf8Text(fb.bb, 10, ypos+6, face,
		"Position: "..load_percent.."%".."    "..cur_section, true)

	ypos = ypos + 15
	blitbuffer.progressBar(fb.bb, 10, ypos, G_width - 20, 15,
							5, 4, load_percent/100, 8)
end



function CREReader:adjustCreReaderCommands()
	-- delete commands
	self.commands:delGroup("[joypad]")
	self.commands:del(KEY_G, nil, "G")
	self.commands:del(KEY_J, MOD_SHIFT, "J")
	self.commands:del(KEY_K, MOD_SHIFT, "K")
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
	self.commands:del(KEY_F, MOD_SHIFT, "F")
	self.commands:del(KEY_F, MOD_ALT, "F")
	self.commands:del(KEY_N, nil, "N") -- highlight
	self.commands:del(KEY_N, MOD_SHIFT, "N") -- show highlights

	-- overwrite commands
	self.commands:add(KEY_PGFWD, MOD_SHIFT, ">",
		"increase font size",
		function(cr)
			cr.doc:zoomFont(1)
			cr:redrawCurrentPage()
		end
	)
	self.commands:add(KEY_PGBCK, MOD_SHIFT, "<",
		"decrease font size",
		function(cr)
			cr.doc:zoomFont(-1)
			cr:redrawCurrentPage()
		end
	)
	self.commands:add(KEY_PGFWD, MOD_ALT, ">",
		"increase line spacing",
		function(cr)
			self.line_space_percent = self.line_space_percent + 10
			if self.line_space_percent > 200 then
				self.line_space_percent = 200
			end
			print("line spacing set to", self.line_space_percent)
			cr.doc:setDefaultInterlineSpace(self.line_space_percent)
			cr:redrawCurrentPage()
		end
	)
	self.commands:add(KEY_PGBCK, MOD_ALT, "<",
		"decrease line spacing",
		function(cr)
			self.line_space_percent = self.line_space_percent - 10
			if self.line_space_percent < 100 then
				self.line_space_percent = 100
			end
			print("line spacing set to", self.line_space_percent)
			cr.doc:setDefaultInterlineSpace(self.line_space_percent)
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
				math.floor(cr.doc:getFullHeight()*(keydef.keycode-KEY_1)/9)..
				'/'..cr.doc:getFullHeight())
			cr:goto(math.floor(cr.doc:getFullHeight()*(keydef.keycode-KEY_1)/9))
		end
	)
	self.commands:add(KEY_F, nil, "F",
		"invoke font menu",
		function(cr)
			local face_list = cre.getFontFaces()

			local fonts_menu = SelectMenu:new{
				menu_title = "Fonts Menu",
				item_array = face_list,
			}

			local item_no = fonts_menu:choose(0, G_height)
			print(face_list[item_no])
			if item_no then
				cr.doc:setFontFace(face_list[item_no])
				self.font_face = face_list[item_no]
			end
			cr:redrawCurrentPage()
		end
	)
	self.commands:add(KEY_F, MOD_ALT, "F",
		"Toggle font bolder attribute",
		function(cr)
			cr.doc:toggleFontBolder()
			cr:redrawCurrentPage()
		end
	)
	self.commands:add(KEY_B, MOD_SHIFT, "B",
		"add jump",
		function(cr)
			cr:addJump(self.doc:getXPointer())
		end
	)
	self.commands:add(KEY_BACK,nil,"back",
		"back to last jump",
		function(cr)
			if #cr.jump_stack ~= 0 then
				cr:goto(cr.jump_stack[1].page, "xpointer")
			end
		end
	)
	self.commands:add(KEY_VPLUS, nil, "vol+",
		"increase gamma",
		function(cr)
			cre.setGammaIndex(self.gamma_index + 1)
			self.gamma_index = cre.getGammaIndex()
			cr:redrawCurrentPage()
		end
	)
	self.commands:add(KEY_VMINUS, nil, "vol-",
		"decrease gamma",
		function(cr)
			cre.setGammaIndex(self.gamma_index - 1)
			self.gamma_index = cre.getGammaIndex()
			cr:redrawCurrentPage()
		end
	)
	self.commands:add(KEY_FW_UP, nil, "joypad up",
		"pan "..self.shift_y.." pixels upwards",
		function(cr)
			cr:goto(cr.pos - cr.shift_y)
		end
	)
	self.commands:add(KEY_FW_DOWN, nil, "joypad down",
		"pan "..self.shift_y.." pixels downwards",
		function(cr)
			cr:goto(cr.pos + cr.shift_y)
		end
	)
end
