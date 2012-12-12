Font = {
	fontmap = {
		cfont = "droid/DroidSansFallback.ttf",		-- filemanager: for menu contents
		tfont = "droid/DroidSans.ttf",		-- filemanager: for title
		ffont = "droid/DroidSans.ttf",		-- filemanager: for footer
		infofont = "droid/DroidSans.ttf",	-- info messages
		rifont = "droid/DroidSans.ttf",		-- readers: for reading position info
		scfont = "droid/DroidSansMono.ttf",	-- selectmenu: font for item shortcut
		hpkfont = "droid/DroidSansMono.ttf",	-- help page: font for displaying keys
		hfont = "droid/DroidSans.ttf",		-- help page: font for displaying help messages
		infont = "droid/DroidSansMono.ttf",	-- inputbox: use mono for better distance controlling
	},
	fontdir = os.getenv("FONTDIR") or "./fonts",
	-- face table
	faces = {},
}


function Font:getFace(font, size)
	if not font then
		-- default to content font
		font = "cfont"
	end

	local face = self.faces[font..size]
	-- build face if not found
	if not face then
		local realname = self.fontmap[font]
		if not realname then
			realname = font
		end
		realname = self.fontdir.."/"..realname
		ok, face = pcall(freetype.newFace, realname, size)
		if not ok then
			Debug("#! Font "..font.." ("..realname..") not supported: "..face)
			return nil
		end
		self.faces[font..size] = face
	--Debug("getFace, found: "..realname.." size:"..size)
	end
	return { size = size, ftface = face, hash = font..size }
end

function Font:_readList(target, dir, effective_dir)
	for f in lfs.dir(dir) do
		if lfs.attributes(dir.."/"..f, "mode") == "directory" and f ~= "." and f ~= ".." then
			self:_readList(target, dir.."/"..f, effective_dir..f.."/")
		else
			local file_type = string.lower(string.match(f, ".+%.([^.]+)") or "")
			if file_type == "ttf" or file_type == "cff" or file_type == "otf" then
				table.insert(target, effective_dir..f)
			end
		end
	end
end

function Font:getFontList()
	fontlist = {}
	self:_readList(fontlist, self.fontdir, "")
	table.sort(fontlist)
	return fontlist
end

function Font:update()
	for _k, _v in ipairs(self.faces) do
		_v:done()
	end
	self.faces = {}
	clearGlyphCache()
end

-- NuPogodi, 05.09.12: added function to change fontface for ANY item in Font.fontmap
-- choose the Fonts.fontmap-item that has to be changed
function Font:chooseItemForFont(initial)
	local items_list = {}
	local item_no, item_found = 1, false
	local description -- additional info to display in menu
	-- define auxilary function
	function add_element(_index)
		if	_index == "cfont" 	then	description = "filemanager: menu contents"
		elseif	_index == "tfont"	then	description = "filemanager: header title"
		elseif	_index == "ffont"	then	description = "filemanager: footer"
		elseif	_index == "rifont"	then	description = "readers: reading position info"
		elseif	_index == "scfont"	then	description = "selectmenu: item shortcuts"
		elseif	_index == "hpkfont"	then	description = "help page: hotkeys"
		elseif	_index == "hfont"	then	description = "help page: description"
		elseif	_index == "infont"	then	description = "inputbox: on-screen keyboard & user input"
		elseif	_index == "infofont" then	description = "info messages"
		else	--[[ not included in Font.fontmap ]] description = "nothing; not used anymore"
		end
		-- then, search for number of initial item in the list Font.fontmap
		if not item_found then
			if _index ~= initial then
				item_no = item_no + 1
			else
				item_found = true
			end
		end
		table.insert(items_list, "[".._index.."] for "..description)
	end
	table.foreach(Font.fontmap, add_element)

	-- goto menu to select the item which font should be changed
	local items_menu = SelectMenu:new{
		menu_title = "Select item to change",
		item_array = items_list,
		current_entry = item_no - 1,
		own_glyph = 2, -- use Font.fontmap-values to render 'items_menu'-items
		}
	local ok, item_font = items_menu:choose(0, fb.bb:getHeight())
	if not ok then
		return nil
	end
	-- and selecting from the font index included in [...] from the whole string
	return string.sub(string.match(item_font,"%b[]"), 2, -2)
end

-- choose font for the 'item_font' in Fonts.fontmap
function Font:chooseFontForItem(item_font)
	item_font = item_font or "cfont"
	local item_no = 0
	local face_list = Font:getFontList()
	while face_list[item_no] ~= Font.fontmap[item_font] and item_no < #face_list do
		item_no = item_no + 1 
	end
	local fonts_menu = SelectMenu:new{
		menu_title = "Fonts Menu",
		item_array = face_list,
		current_entry = item_no - 1,
		own_glyph = 1, -- use the item from item_array to render 'fonts_menu'-items
		}
	local re, font = fonts_menu:choose(0, G_height)
	if re then
		Font.fontmap[item_font] = font
		Font:update()
	end
end

-- to remain in menu with Font.fontmap-items until 'Back'
function Font:chooseFonts()
	local item_font = "cfont" -- initial value
	while item_font ~= nil do
		item_font = self:chooseItemForFont(item_font)
		if item_font then
			self:chooseFontForItem(item_font)
		end
	end
end
