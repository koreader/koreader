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
			debug(err)
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
	self.font_face = font_face or "Droid Sans Fallback"
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
	self.settings:saveSetting("font_face", self.font_face)
	self.settings:saveSetting("gamma_index", self.gamma_index)
	self.settings:saveSetting("line_space_percent", self.line_space_percent)
end

function CREReader:saveLastPageOrPos()
	self.settings:saveSetting("last_percent", self.percent)
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
function CREReader:goto(pos, is_ignore_jump, pos_type)
	local prev_xpointer = self.doc:getXPointer()
	local width, height = G_width, G_height

	if pos_type == "xpointer" then
		self.doc:gotoXPointer(pos)
		pos = self.doc:getCurrentPos()
	else -- pos_type is position within document
		pos = math.min(pos, self.doc:getFullHeight() - height)
		pos = math.max(pos, 0)
		self.doc:gotoPos(pos)
	end

	-- add to jump history, distinguish jump from normal page turn
	-- NOTE:
	-- even though we have called gotoPos() or gotoXPointer() previously, 
	-- self.pos hasn't been updated yet here, so we can still make use of it.
	if not is_ignore_jump then
		if self.pos and math.abs(self.pos - pos) > height then
			self:addJump(prev_xpointer)
		end
	end

	self.doc:drawCurrentPage(self.nulldc, fb.bb)

	debug("## self.show_overlap "..self.show_overlap)
	if self.show_overlap < 0 then
		fb.bb:dimRect(0,0, width, -self.show_overlap)
	elseif self.show_overlap > 0 then
		fb.bb:dimRect(0,height - self.show_overlap, width, self.show_overlap)
	end
	self.show_overlap = 0

	if self.rcount >= self.rcountmax then
		debug("full refresh")
		self.rcount = 0
		fb:refresh(0)
	else
		debug("partial refresh")
		self.rcount = self.rcount + 1
		fb:refresh(1)
	end

	self.pos = pos
	self.pageno = self.doc:getCurrentPage()
	self.percent = self.doc:getCurrentPercent()
end

function CREReader:gotoPercent(percent)
	self:goto(percent * self.doc:getFullHeight() / 10000)
end

function CREReader:gotoTocEntry(entry)
	self:goto(entry.xpointer, nil, "xpointer")
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
-- jump history related methods
----------------------------------------------------
function CREReader:isSamePage(p1, p2)
	return self.doc:getPageFromXPointer(p1) == self.doc:getPageFromXPointer(p2)
end

function CREReader:showJumpHist()
	local menu_items = {}
	for k,v in ipairs(self.jump_history) do
		if k == self.jump_history.cur then
			cur_sign = "*(Cur) "
		else
			cur_sign = ""
		end
		table.insert(menu_items,
			cur_sign..v.datetime.." -> Page "
			..self.doc:getPageFromXPointer(v.page).." "..v.notes)
	end

	if #menu_items == 0 then
		showInfoMsgWithDelay(
			"No jump history found.", 2000, 1)
	else
		-- if cur points to head, draw entry for current page
		if self.jump_history.cur > #self.jump_history then
			table.insert(menu_items,
				"Current Page "..self.pageno)
		end

		jump_menu = SelectMenu:new{
			menu_title = "Jump History",
			item_array = menu_items,
		}
		item_no = jump_menu:choose(0, fb.bb:getHeight())
		if item_no and item_no <= #self.jump_history then
			local jump_item = self.jump_history[item_no]
			self.jump_history.cur = item_no
			self:goto(jump_item.page, true, "xpointer")
		else
			self:redrawCurrentPage()
		end
	end
end

----------------------------------------------------
-- bookmarks related methods
----------------------------------------------------
function CREReader:showBookMarks()
	local menu_items = {}
	-- build menu items
	for k,v in ipairs(self.bookmarks) do
		table.insert(menu_items,
			"Page "..self.doc:getPageFromXPointer(v.page)
			.." "..v.notes.." @ "..v.datetime)
	end
	if #menu_items == 0 then
		showInfoMsgWithDelay(
			"No bookmark found.", 2000, 1)
	else
		toc_menu = SelectMenu:new{
			menu_title = "Bookmarks",
			item_array = menu_items,
		}
		item_no = toc_menu:choose(0, fb.bb:getHeight())
		if item_no then
			self:goto(self.bookmarks[item_no].page, nil, "xpointer")
		else
			self:redrawCurrentPage()
		end
	end
end


----------------------------------------------------
-- TOC related methods
----------------------------------------------------
function CREReader:getTocTitleByPage(page_or_xpoint)
	local page = 1
	-- tranform xpointer to page
	if type(page_or_xpoint) == "string" then
		page = self.doc:getPageFromXPointer(page_or_xpoint)
	else
		page = page_or_xpoint
	end
	return self:_getTocTitleByPage(page)
end

function CREReader:getTocTitleOfCurrentPage()
	return self:getTocTitleByPage(self.doc:getXPointer())
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
	self.commands:del(KEY_X, nil, "X")
	self.commands:del(KEY_F, MOD_SHIFT, "F")
	self.commands:del(KEY_F, MOD_ALT, "F")
	self.commands:del(KEY_N, nil, "N") -- highlight
	self.commands:del(KEY_N, MOD_SHIFT, "N") -- show highlights

	-- overwrite commands
	
	self.commands:addGroup(MOD_SHIFT.."< >",{
		Keydef:new(KEY_PGBCK,MOD_SHIFT),Keydef:new(KEY_PGFWD,MOD_SHIFT),
		Keydef:new(KEY_LPGBCK,MOD_SHIFT),Keydef:new(KEY_LPGFWD,MOD_SHIFT)},
		"increase/decrease font size",
		function(self)
			local delta = 1
			local change = "increase"
			if keydef.keycode == KEY_PGBCK or keydef.keycode == KEY_LPGBCK then
				delta = -1
				change = "decrease"
			end
			InfoMessage:show(change.." font size", 0)
			self.doc:zoomFont(delta)
			self:redrawCurrentPage()
		end
	)
	self.commands:addGroup(MOD_ALT.."< >",{
		Keydef:new(KEY_PGBCK,MOD_ALT),Keydef:new(KEY_PGFWD,MOD_ALT),
		Keydef:new(KEY_LPGBCK,MOD_ALT),Keydef:new(KEY_LPGFWD,MOD_ALT)},
		"increase/decrease line spacing",
		function(self)
			if keydef.keycode == KEY_PGBCK or keydef.keycode == KEY_LPGBCK then
				self.line_space_percent = self.line_space_percent - 10
				if self.line_space_percent < 100 then
					self.line_space_percent = 100
				end
			else
				self.line_space_percent = self.line_space_percent + 10
				if self.line_space_percent > 200 then
					self.line_space_percent = 200
				end
			end
			InfoMessage:show("line spacing "..self.line_space_percent.."%", 0)
			debug("line spacing set to", self.line_space_percent)
			self.doc:setDefaultInterlineSpace(self.line_space_percent)
			self:redrawCurrentPage()
		end
	)
	local numeric_keydefs = {}
	for i=1,10 do 
		numeric_keydefs[i]=Keydef:new(KEY_1+i-1, nil, tostring(i%10)) 
	end
	self.commands:addGroup("[1..0]", numeric_keydefs,
		"jump to <key>*10% of document",
		function(self, keydef)
			debug('jump to position: '..
				math.floor(self.doc:getFullHeight()*(keydef.keycode-KEY_1)/9)..
				'/'..self.doc:getFullHeight())
			self:goto(math.floor(self.doc:getFullHeight()*(keydef.keycode-KEY_1)/9))
		end
	)
	self.commands:add(KEY_F, nil, "F",
		"change document font",
		function(self)
			Screen:saveCurrentBB()

			local face_list = cre.getFontFaces()

			local fonts_menu = SelectMenu:new{
				menu_title = "Fonts Menu",
				item_array = face_list,
			}

			local item_no = fonts_menu:choose(0, G_height)
			debug(face_list[item_no])
			if item_no then
				Screen:restoreFromSavedBB()
				self.doc:setFontFace(face_list[item_no])
				self.font_face = face_list[item_no]
				InfoMessage:show("Redrawing with "..face_list[item_no], 0)
			end
			self:redrawCurrentPage()
		end
	)
	self.commands:add(KEY_F, MOD_ALT, "F",
		"Toggle font bolder attribute",
		function(self)
			self.doc:toggleFontBolder()
			self:redrawCurrentPage()
		end
	)
	self.commands:add(KEY_B, MOD_ALT, "B",
		"add bookmark to current page",
		function(self)
			ok = self:addBookmark(self.doc:getXPointer())
			if not ok then
				showInfoMsgWithDelay("Page already marked!", 2000, 1)
			else
				showInfoMsgWithDelay("Page marked.", 2000, 1)
			end
		end
	)
	self.commands:add(KEY_BACK, nil, "Back",
		"go backward in jump history",
		function(self)
			local prev_jump_no = self.jump_history.cur - 1
			if prev_jump_no >= 1 then
				self.jump_history.cur = prev_jump_no
				self:goto(self.jump_history[prev_jump_no].page, true, "xpointer")
			else
				showInfoMsgWithDelay("Already first jump!", 2000, 1)
			end
		end
	)
	self.commands:add(KEY_BACK, MOD_SHIFT, "Back",
		"go forward in jump history",
		function(self)
			local next_jump_no = self.jump_history.cur + 1
			if next_jump_no <= #self.jump_history then
				self.jump_history.cur = next_jump_no
				self:goto(self.jump_history[next_jump_no].page, true, "xpointer")
			else
				showInfoMsgWithDelay("Already last jump!", 2000, 1)
			end
		end
	)
	self.commands:addGroup("vol-/+",
		{Keydef:new(KEY_VPLUS,nil), Keydef:new(KEY_VMINUS,nil)},
		"decrease/increase gamma",
		function(self, keydef)
			local delta = 1
			if keydef.keycode == KEY_VMINUS then
				delta = -1
			end
			cre.setGammaIndex(self.gamma_index+delta)
			self.gamma_index = cre.getGammaIndex()
			self:redrawCurrentPage()
		end
	)
	self.commands:add(KEY_FW_UP, nil, "joypad up",
		"pan "..self.shift_y.." pixels upwards",
		function(self)
			self:goto(self.pos - self.shift_y)
		end
	)
	self.commands:add(KEY_FW_DOWN, nil, "joypad down",
		"pan "..self.shift_y.." pixels downwards",
		function(self)
			self:goto(self.pos + self.shift_y)
		end
	)
end
