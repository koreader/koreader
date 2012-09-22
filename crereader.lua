require "font"
require "unireader"
require "inputbox"
require "selectmenu"

CREReader = UniReader:new{
	pos = nil,
	percent = 0,

	gamma_index = 15,
	font_face = nil,
	default_font = "Droid Sans",
	font_zoom = 0,

	line_space_percent = 100,
}

function CREReader:init()
	self:addAllCommands()
	self:adjustCreReaderCommands()

	-- initialize cache
	cre.initCache(1024*1024*64)
	-- we need to initialize the CRE font list
	local fonts = Font:getFontList()
	for _k, _v in ipairs(fonts) do
		local ok, err = pcall(cre.registerFont, Font.fontdir..'/'.._v)
		if not ok then
			Debug(err)
		end
	end

	local default_font = G_reader_settings:readSetting("cre_font")
	if default_font then
		self.default_font = default_font
	end
end
-- inspect the zipfile content
function CREReader:ZipContentExt(fname)
	local outfile, s = "./data/zip_content"
	os.execute("unzip -l \""..fname.."\" > "..outfile)
	local i = 1
	if io.open(outfile,"r") then
		for lines in io.lines(outfile) do 
			if i == 4 then s = lines break else i = i + 1 end
		end
	end
	if s then -- return the extension
		return string.lower(string.match(s, ".+%.([^.]+)") or "")
	else
		return nil
	end
end


-- open a CREngine supported file and its settings store
function CREReader:open(filename)
	local ok
	local file_type = string.lower(string.match(filename, ".+%.([^.]+)") or "")
	-- check zips for potential problems - wrong zip & wrong content
	if file_type == "zip" then
		file_type = self:ZipContentExt(filename)
	end
	if not file_type then
		return false, "Error unzipping file. "
	end
	-- if the zip entry is not cre-document
	if ext:getReader(file_type) ~= CREReader then
		return false, "Zip contains improper content. "
	end
	-- these two format use the same css file
	if file_type == "html" then
		file_type = "htm"
	end
	-- if native css-file doesn't exist, one needs to use default cr3.css
	if not io.open("./data/"..file_type..".css") then
		file_type = "cr3"
	end
	local style_sheet = "./data/"..file_type..".css"
	ok, self.doc = pcall(cre.openDocument, filename, style_sheet, G_width, G_height)
	if not ok then
		return false, "Error opening cre-document. " -- self.doc, will contain error message
	end
	self.doc:setDefaultInterlineSpace(self.line_space_percent)
	return true
end

----------------------------------------------------
-- setting related methods
----------------------------------------------------
function CREReader:loadSpecialSettings()
	local font_face = self.settings:readSetting("font_face")
	if not font_face then
		font_face = self.default_font
	end
	self.font_face = font_face
	self.doc:setFontFace(self.font_face)

	local gamma_index = self.settings:readSetting("gamma_index")
	self.gamma_index = gamma_index or self.gamma_index
	cre.setGammaIndex(self.gamma_index)

	local line_space_percent = self.settings:readSetting("line_space_percent")
	self.line_space_percent = line_space_percent or self.line_space_percent

	self.font_zoom = self.settings:readSetting("font_zoom") or 0
	if self.font_zoom ~= 0 then
		local i = math.abs(self.font_zoom)
		local step = self.font_zoom / i
		while i>0 do
			self.doc:zoomFont(step)
			i=i-1
		end
	end
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
	self.settings:saveSetting("font_zoom", self.font_zoom)
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

	Debug("## self.show_overlap "..self.show_overlap)
	if self.show_overlap < 0 then
		fb.bb:dimRect(0,0, width, -self.show_overlap)
	elseif self.show_overlap > 0 then
		fb.bb:dimRect(0,height - self.show_overlap, width, self.show_overlap)
	end
	self.show_overlap = 0

	if self.rcount >= self.rcountmax then
		Debug("full refresh")
		self.rcount = 0
		fb:refresh(0)
	else
		Debug("partial refresh")
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
	self:redrawCurrentPage()
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
		item_no = jump_menu:choose(0, G_height)
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
function CREReader:isBookmarkInSequence(a, b)
	return self.doc:getPosFromXPointer(a.page) < self.doc:getPosFromXPointer(b.page)
end

function CREReader:nextBookMarkedPage()
	for k,v in ipairs(self.bookmarks) do
		if self.pos < self.doc:getPosFromXPointer(v.page) then
			return v
		end
	end
	return nil
end

function CREReader:prevBookMarkedPage()
	local pre_item = nil
	for k,v in ipairs(self.bookmarks) do
		if self.pos <= self.doc:getPosFromXPointer(v.page) then
			if not pre_item then
				break
			elseif self.doc:getPosFromXPointer(pre_item.page) < self.pos then
				return pre_item
			end
		end
		pre_item = v
	end
	return pre_item
end

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
		local bkmk_menu = SelectMenu:new{
			menu_title = "Bookmarks",
			item_array = menu_items,
		}
		item_no = bkmk_menu:choose(0, G_height)
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

--[[ function to scroll chapters without calling TOC-menu,
direction is either +1 (next chapter) or -1 (previous one).
Jump over several chapters is principally possible when direction > 1 ]]

function CREReader:gotoPrevNextTocEntry(direction)
	if not self.toc then
		self:fillToc()
	end
	if #self.toc == 0 then
		showInfoMsgWithDelay("No Table of Contents", 1500, 1)
		return
	end
	-- search for current TOC-entry
	local item_no = 0
	for k,v in ipairs(self.toc) do
		if v.page <= self.pageno then
			item_no = item_no + 1
		else
			break
		end
	end
	-- minor correction when current page is not the page opening current chapter
	if self.pageno > self.toc[item_no].page and direction < 0 then
		direction = direction + 1
	end
	-- define the jump target
	item_no = item_no + direction
	if item_no > #self.toc then -- jump to last page
		self:goto(self.doc:getFullHeight()-G_height)
	elseif item_no > 0 then
		self:gotoTocEntry(self.toc[item_no])
	else
		self:goto(0) -- jump to first page
	end
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
	local face = Font:getFace("rifont", 20)

	local cur_section = self:getTocTitleOfCurrentPage()
	if cur_section ~= "" then
		cur_section = "  Section: "..cur_section
	end
	--[[ NuPogodi, 30.08.12: to show or not to show (page numbers in info message)?
		"  Page: "..self.pageno.." of "..self.doc:getPages()
	TODO: similar bar at the page top with the book author, book title, etc. ]]
	local footer = "Position: "..load_percent.."%"..cur_section
	if sizeUtf8Text(10, fb.bb:getWidth(), face, footer, true).x < (fb.bb:getWidth() - 20) then
		renderUtf8Text(fb.bb, 10, ypos+6, face, footer, true)
	else
		local gapx = sizeUtf8Text(10, fb.bb:getWidth(), face, "...", true).x
		gapx = 10 + renderUtf8TextWidth(fb.bb, 10, ypos+6, face, footer, true, fb.bb:getWidth() - 30 - gapx).x
		renderUtf8Text(fb.bb, gapx, ypos+6, face, "...", true)
	end
	ypos = ypos + 15
	blitbuffer.progressBar(fb.bb, 10, ypos, G_width - 20, 15, 5, 4, load_percent/100, 8)
end

function UniReader:showMenu()
	self:_drawReadingInfo()
	fb:refresh(1)
	while true do
		local ev = input.saveWaitForEvent()
		ev.code = adjustKeyEvents(ev)
		if ev.type == EV_KEY and ev.value == EVENT_VALUE_KEY_PRESS then
			if ev.code == KEY_BACK or ev.code == KEY_MENU then
				return
			end
		end
	end
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
	self.commands:del(KEY_N, nil, "N")
	self.commands:del(KEY_N, MOD_SHIFT, "N")
	self.commands:del(KEY_X, MOD_SHIFT, "X")	-- remove manual cropping

	-- NuPogodi, 01.09.12: remove new hotkey in unireader.lua
	-- that calls 'zoom-mode' menu
	self.commands:del(KEY_M, nil, "M")

	-- CCW-rotation
	self.commands:add(KEY_K, nil, "K",
		"rotate screen counterclockwise",
		function(self)
			InfoMessage:show("Rotating counterclockwise ", 0)
			local prev_xpointer = self.doc:getXPointer()
			Screen:screenRotate("anticlockwise")
			G_width, G_height = fb:getSize()
			self:goto(prev_xpointer, nil, "xpointer")
			self.pos = self.doc:getCurrentPos()
		end
	)
	-- CW-rotation
	self.commands:add(KEY_J, nil, "J",
		"rotate screen clockwise",
		function(self)
			InfoMessage:show("Rotating clockwise ", 0)
			local prev_xpointer = self.doc:getXPointer()
			Screen:screenRotate("clockwise")
			G_width, G_height = fb:getSize()
			self:goto(prev_xpointer, nil, "xpointer")
			self.pos = self.doc:getCurrentPos()
		end
	)
	-- navigate between chapters by Shift+Up & Shift-Down
	self.commands:addGroup(MOD_SHIFT.."up/down",{
		Keydef:new(KEY_FW_UP,MOD_SHIFT), Keydef:new(KEY_FW_DOWN,MOD_SHIFT)},
		"scroll to previous/next chapter",
		function(self)
			if keydef.keycode == KEY_FW_UP then
				--InfoMessage:show("Jumping to previous chapter ", 0)
				self:gotoPrevNextTocEntry(-1)
			else
				--InfoMessage:show("Jumping to next chapter ", 0)
				self:gotoPrevNextTocEntry(1)
			end
		end
	)
	-- fast navigation by Shift+Left & Shift-Right
	local scrollpages = 10
	self.commands:addGroup(MOD_SHIFT.."left/right",
		{Keydef:new(KEY_FW_LEFT,MOD_SHIFT),Keydef:new(KEY_FW_RIGHT,MOD_SHIFT)},
		"scroll "..scrollpages.." pages backwards/forward",
		function(self)
			if keydef.keycode == KEY_FW_LEFT then
				--InfoMessage:show("Scrolling "..scrollpages.." pages backwards ", 0)
				self:goto(math.max(0, self.pos - scrollpages*G_height))
			else
				--InfoMessage:show("Scrolling "..scrollpages.." pages forward ", 0)
				self:goto(math.min(self.pos + scrollpages*G_height, self.doc:getFullHeight()-G_height))
			end
		end
	)
	self.commands:addGroup(MOD_SHIFT.."< >",{
		Keydef:new(KEY_PGBCK,MOD_SHIFT),Keydef:new(KEY_PGFWD,MOD_SHIFT),
		Keydef:new(KEY_LPGBCK,MOD_SHIFT),Keydef:new(KEY_LPGFWD,MOD_SHIFT)},
		"increase/decrease font size",
		function(self)
			local delta = 1
			local change = "Increase"
			if keydef.keycode == KEY_PGBCK or keydef.keycode == KEY_LPGBCK then
			   delta = -1
			   change = "Decrease"
			end
			self.font_zoom = self.font_zoom + delta
			InfoMessage:show(change.." font size to "..self.font_zoom, 0)
			-- NuPogodi, 18.08.12: XPointer-method to restore position
			Debug("font zoomed to", self.font_zoom)
			local prev_xpointer = self.doc:getXPointer()
			self.doc:zoomFont(delta)
			self:goto(prev_xpointer, nil, "xpointer")
		end
	)
	self.commands:addGroup(MOD_ALT.."< >",{
		Keydef:new(KEY_PGBCK,MOD_ALT),Keydef:new(KEY_PGFWD,MOD_ALT),
		Keydef:new(KEY_LPGBCK,MOD_ALT),Keydef:new(KEY_LPGFWD,MOD_ALT)},
		"increase/decrease line spacing",
		function(self)
			if keydef.keycode == KEY_PGBCK or keydef.keycode == KEY_LPGBCK then
				self.line_space_percent = self.line_space_percent - 10
				self.line_space_percent = math.max(self.line_space_percent, 80)
			else
				self.line_space_percent = self.line_space_percent + 10
				self.line_space_percent = math.min(self.line_space_percent, 200)
			end
			InfoMessage:show("Line spacing "..self.line_space_percent.."%", 0)
			Debug("line spacing set to", self.line_space_percent)
			-- NuPogodi, 18.08.12: XPointer-method to restore position
			local prev_xpointer = self.doc:getXPointer()
			self.doc:setDefaultInterlineSpace(self.line_space_percent)
			self:goto(prev_xpointer, nil, "xpointer")
		end
	)
	local numeric_keydefs = {}
	for i=1,10 do
		numeric_keydefs[i]=Keydef:new(KEY_1+i-1, nil, tostring(i%10))
	end
	self.commands:addGroup("[1..0]", numeric_keydefs,
		"jump to <key>*10% of document",
		function(self, keydef)
			Debug('jump to position: '..
				math.floor(self.doc:getFullHeight()*(keydef.keycode-KEY_1)/9)..
				'/'..self.doc:getFullHeight())
			self:goto(math.floor(self.doc:getFullHeight()*(keydef.keycode-KEY_1)/9))
		end
	)
	self.commands:add(KEY_G,nil,"G",
		"open 'go to position' input box",
		function(unireader)
			local height = self.doc:getFullHeight()
			local position = NumInputBox:input(G_height-100, 100,
				"Position in percent:", "current: "..math.floor((self.pos / height)*100), true)
			-- convert string to number
			if position and pcall(function () position = position + 0 end) then
				if position >= 0 and position <= 100 then
					self:goto(math.floor(height * position / 100))
					return
				end
			end
			self:redrawCurrentPage()
		end
	)
	self.commands:add({KEY_F, KEY_AA}, nil, "F",
		"change document font",
		function(self)
			--[[ NuPogodi, 18.08.12:
			1.	removed excessive saving [saveCurrentBB()] and restoring [restoreFromSavedBB()]
				the screen, respectively, before & after calling 'fonts_menu'
			2.	used XPointer-based method to restore position after document rescaling ]]
			local face_list = cre.getFontFaces()
			-- define the current font in face_list 
			local item_no = 0
			while face_list[item_no] ~= self.font_face and item_no < #face_list do 
				item_no = item_no + 1 
			end
			local fonts_menu = SelectMenu:new{
				menu_title = "Fonts Menu ",
				item_array = face_list, 
				current_entry = item_no - 1,
			}
			item_no = fonts_menu:choose(0, G_height)
			local prev_xpointer = self.doc:getXPointer()
			if item_no then
				Debug(face_list[item_no])
				InfoMessage:show("Redrawing with "..face_list[item_no], 0)
				self.doc:setFontFace(face_list[item_no])
				self.font_face = face_list[item_no]
			end
			self:goto(prev_xpointer, nil, "xpointer")
		end
	)
	self.commands:add(KEY_F, MOD_SHIFT, "F",
		"use document font as default font",
		function(self)
			self.default_font = self.font_face
			G_reader_settings:saveSetting("cre_font", self.font_face)
			showInfoMsgWithDelay("Default document font set", 2000, 1)
		end
	)
	self.commands:add(KEY_F, MOD_ALT, "F",
		--[[ NuPogodi, 18.08.12: 1. Changed a description to be shown in helppage
		2. Added message to user; 3. Improved a method to restore position ]]
		"toggle font-weight: bold <> normal",
		function(self)
			
			InfoMessage:show("Changing font-weight ", 0)
			local prev_xpointer = self.doc:getXPointer()
			self.doc:toggleFontBolder()
			self:goto(prev_xpointer, nil, "xpointer")
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
			InfoMessage:show("Redraw with gamma = "..self.gamma_index, 1) -- no delay
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

----------------------------------------------------
--- search
----------------------------------------------------
function CREReader:searchHighLight(search)
	Debug("FIXME CreReader::searchHighLight", search)

	if self.last_search == nil or self.last_search.search == nil then
		self.last_search = {
			search = "",
		}
	end

	local origin = 0 -- 0=current 1=next-last -1=first-current
	if self.last_search.search == search then
		origin = 1
	end

	local found, pos = self.doc:findText(
		search,
		origin,
		0, -- reverse: boolean
		1  -- caseInsensitive: boolean
	)

	if found then
		self.pos = pos -- first metch position
		self:redrawCurrentPage()
		showInfoMsgWithDelay( found.." hits '"..search.."' pos "..pos, 2000, 1)
	else
		showInfoMsgWithDelay( "'"..search.."' not found in document", 2000, 1)
	end

	self.last_search.search = search

end

