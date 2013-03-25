require "cache"

--[[
TODO: all these functions should probably be methods on Face objects
]]--

GlyphCache = Cache:new{
	max_memsize = 512*1024,
	current_memsize = 0,
	cache = {},
	-- this will hold the LRU order of the cache
	cache_order = {}
}

function getGlyph(face, charcode, bgcolor, fgcolor)
	if bgcolor == nil then bgcolor = 0.0 end
	if fgcolor == nil then fgcolor = 1.0 end
	local hash = "glyph|"..face.hash.."|"..charcode.."|"..bgcolor.."|"..fgcolor
	local glyph = GlyphCache:check(hash)
	if glyph then
		-- cache hit
		return glyph[1]
	end
	local rendered_glyph = face.ftface:renderGlyph(charcode, bgcolor, fgcolor)
	if not rendered_glyph then
		DEBUG("error rendering glyph (charcode=", charcode, ") for face", face)
		return
	end
	glyph = CacheItem:new{rendered_glyph}
	glyph.size = glyph[1].bb:getWidth() * glyph[1].bb:getHeight() / 2 + 32
	GlyphCache:insert(hash, glyph)
	return rendered_glyph
end

function getSubTextByWidth(text, face, width, kerning)
	local pen_x = 0
	local prevcharcode = 0
	local char_list = {}
	for uchar in string.gfind(text, "([%z\1-\127\194-\244][\128-\191]*)") do
		if pen_x < width then
			local charcode = util.utf8charcode(uchar)
			local glyph = getGlyph(face, charcode)
			if kerning and prevcharcode then
				local kern = face.ftface:getKerning(prevcharcode, charcode)
				pen_x = pen_x + kern
			end
			pen_x = pen_x + glyph.ax
			if pen_x <= width then
				prevcharcode = charcode
				table.insert(char_list, uchar)
			else
				break
			end
		end
	end
	return table.concat(char_list)
end

function sizeUtf8Text(x, width, face, text, kerning)
	if not text then
		DEBUG("sizeUtf8Text called without text");
		return
	end

	-- may still need more adaptive pen placement when kerning,
	-- see: http://freetype.org/freetype2/docs/glyphs/glyphs-4.html
	local pen_x = 0
	local pen_y_top = 0
	local pen_y_bottom = 0
	local prevcharcode = 0
	for uchar in string.gfind(text, "([%z\1-\127\194-\244][\128-\191]*)") do
		if pen_x < (width - x) then
			local charcode = util.utf8charcode(uchar)
			local glyph = getGlyph(face, charcode)
			if kerning and (prevcharcode ~= 0) then
				pen_x = pen_x + face.ftface:getKerning(prevcharcode, charcode)
			end
			pen_x = pen_x + glyph.ax
			pen_y_top = math.max(pen_y_top, glyph.t)
			pen_y_bottom = math.max(pen_y_bottom, glyph.bb:getHeight() - glyph.t)
			--DEBUG("ax:"..glyph.ax.." t:"..glyph.t.." r:"..glyph.r.." h:"..glyph.bb:getHeight().." w:"..glyph.bb:getWidth().." yt:"..pen_y_top.." yb:"..pen_y_bottom)
			prevcharcode = charcode
		end -- if pen_x < (width - x)
	end -- for uchar
	return { x = pen_x, y_top = pen_y_top, y_bottom = pen_y_bottom}
end

function renderUtf8Text(buffer, x, y, face, text, kerning, bgcolor, fgcolor)
	if not text then
		DEBUG("renderUtf8Text called without text");
		return 0
	end

	-- may still need more adaptive pen placement when kerning,
	-- see: http://freetype.org/freetype2/docs/glyphs/glyphs-4.html
	local pen_x = 0
	local prevcharcode = 0
	local buffer_width = buffer:getWidth()
	for uchar in string.gfind(text, "([%z\1-\127\194-\244][\128-\191]*)") do
		if pen_x < buffer_width then
			local charcode = util.utf8charcode(uchar)
			local glyph = getGlyph(face, charcode, bgcolor, fgcolor)
			if kerning and (prevcharcode ~= 0) then
				pen_x = pen_x + face.ftface:getKerning(prevcharcode, charcode)
			end
			buffer:addblitFrom(
				glyph.bb,
				x + pen_x + glyph.l, y - glyph.t,
				0, 0,
				glyph.bb:getWidth(), glyph.bb:getHeight(), 1)
			pen_x = pen_x + glyph.ax
			prevcharcode = charcode
		end -- if pen_x < buffer_width
	end -- for uchar

	return pen_x
end
