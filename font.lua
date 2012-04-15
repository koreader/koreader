
Font = {
	fontmap = {
		-- default font for menu contents
		cfont = "droid/DroidSans.ttf",
		-- default font for title
		tfont = "NimbusSanL-BoldItal.cff",
		-- default font for footer
		ffont = "droid/DroidSans.ttf",

		-- default font for reading position info
		rifont = "droid/DroidSans.ttf",

		-- default font for pagination display
		pgfont = "droid/DroidSans.ttf",

		-- selectmenu: font for item shortcut
		scfont = "droid/DroidSansMono.ttf",

		-- help page: font for displaying keys
		hpkfont = "droid/DroidSansMono.ttf",
		-- font for displaying help messages
		hfont = "droid/DroidSans.ttf",

		-- font for displaying input content
		-- we have to use mono here for better distance controlling
		infont = "droid/DroidSansMono.ttf",

		-- font for info messages
		infofont = "droid/DroidSans.ttf",
	},

	fontdir = os.getenv("FONTDIR") or "./fonts",

	-- face table
	faces = {},
}


function Font:getFace(font, size)
print("getFace: "..font.." size:"..size)
	if not font then
		-- default to content font
		font = self.cfont
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
			print("#! Font "..font.." ("..realname..") not supported: "..face)
			return nil
		end
		self.faces[font..size] = face
print("getFace, found: "..realname.." size:"..size)
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
