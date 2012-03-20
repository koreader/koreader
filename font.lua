
Font = {
	-- default font for menu contents
	cfont = "sans",
	-- default font for title
	tfont = "Helvetica-BoldOblique",
	-- default font for footer
	ffont = "sans",

	-- built in fonts
	fonts = {"sans", "cjk", "mono",
		"Courier", "Courier-Bold", "Courier-Oblique", "Courier-BoldOblique",
		"Helvetica", "Helvetica-Oblique", "Helvetica-BoldOblique",
		"Times-Roman", "Times-Bold", "Times-Italic", "Times-BoldItalic",},

	-- face table
	faces = {},
}

function Font:getFaceAndHash(size, font)
	if not font then
		-- default to content font
		font = self.cfont
	end

	local face = self.faces[font..size]
	-- build face if not found
	if not face then
		for _k,_v in ipairs(self.fonts) do
			if font == _v then
				face = freetype.newBuiltinFace(font, size)
				self.faces[font..size] = face
			end
		end
		if not face then
			print("#! Font "..font.." not supported!!")
			return nil
		end
	end
	return face, font..size
end

function Font:update()
	self.faces = {}
	clearGlyphCache()
end
